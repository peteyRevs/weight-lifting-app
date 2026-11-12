#!/usr/bin/env bash
# .github/workflows/*.yml: structure (triggers, names, permissions, pins, caching,
# shells) and the behaviour of their inline scripts, which are extracted and run
# here against throwaway git repos and a fake `gh`. YAML is read with the system
# Ruby (Psych); actionlint runs only if mise already has it (no download).
set -uo pipefail
source "$(dirname "$0")/lib.sh"

WF="$ROOT/.github/workflows"
T="$ADV_TMP"

if ! command -v ruby >/dev/null || ! ruby -ryaml -rjson -e '' 2>/dev/null; then
    fail "workflows suite" "no ruby with yaml/json (macOS and the runner both ship one)"
    finish; exit
fi

# json <workflow.yml>: the workflow as JSON. YAML 1.1 reads the key `on` as true.
json() {
    ruby -ryaml -rjson -e 'y = YAML.load_file(ARGV[0]); y["on"] = y.delete(true) if y.key?(true); puts JSON.generate(y)' "$1"
}
json "$WF/pr.yml" >"$T/pr.json"
json "$WF/nightly.yml" >"$T/nightly.json"
json "$WF/release-please.yml" >"$T/rp.json"
json "$WF/main-cache.yml" >"$T/mc.json"
q() { jq -r "$2" "$T/$1.json"; } # q <pr|nightly|rp|mc> <jq filter>

# ---- actionlint -------------------------------------------------------------------
# mise.toml pins both, and check.sh step 0 installs them: a missing one fails (S2).
al="$(cd "$ROOT" && mise which actionlint 2>/dev/null || true)"
sc="$(cd "$ROOT" && mise which shellcheck 2>/dev/null || true)"
if [[ -x "$al" && -x "$sc" ]]; then
    out="$(cd "$ROOT" && PATH="$(dirname "$sc"):$PATH" "$al" -no-color .github/workflows/*.yml 2>&1)"
    expect_exit "WF01 actionlint (with shellcheck) finds nothing" 0 $? "$out"
else
    fail "WF01 actionlint (with shellcheck) finds nothing" "actionlint or shellcheck missing; run: mise install"
fi

# ---- pr.yml shape ---------------------------------------------------------------------
check "WF02 PR runs on pull_request to main and on workflow_dispatch" \
    is "$(q pr '[.on | keys[]] | sort | join(",")') $(q pr '.on.pull_request.branches | join(",")')" \
    "pull_request,workflow_dispatch main"
check "WF03 no workflow-level paths filter (the Scope job decides, rename-safe)" \
    is "$(q pr '.on.pull_request | has("paths") or has("paths-ignore")')" false
# Pete, 2026-09-27: free minutes, so ONE macOS job (iOS since 2026-09-30) behind a Linux scope job; since
# 2026-09-30 the static checks run first, on Linux (ci-efficiency notes).
# Since 2026-11-11 Check is two shards, then Coverage (docs/ci-cd.md, "Shards").
check "WF04 jobs are Scope, Static checks, Check (one per shard), then Coverage" is "$(q pr '[.jobs[].name] | join("|")')" \
    'Scope|Static checks|Check (shard ${{ matrix.shard }}/2)|Coverage'
check "WF05 Check needs Scope and Static checks; Static checks needs Scope, and Coverage Scope and Check, with Check's condition" \
    is "$(q pr '(.jobs.check.needs | join(",")) + " " + .jobs.static.needs + " " + (.jobs.coverage.needs | join(","))
        + " " + (.jobs.check.if as $check | [.jobs.static.if, .jobs.coverage.if] | map(. == $check) | tostring)')" \
    "scope,static scope scope,check [true,true]"
check "WF06 PR token is contents: read, with no job-level override" \
    is "$(q pr '.permissions | tojson') $(q pr '[.jobs[] | has("permissions")] | any')" '{"contents":"read"} false'
# Pete, 2026-09-29 (F32): Xcode 27 now, so every macOS job runs on the xcode-27 preview image.
check "WF07 the macOS jobs (Check's shards and Coverage) run on the xcode-27 image; Scope and Static checks on Linux" \
    is "$(q pr '[.jobs | to_entries[] | "\(.key)=\(.value."runs-on")"] | join(",")')" \
    "scope=ubuntu-24.04,static=ubuntu-24.04,check=xcode-27,coverage=xcode-27"
check "WF50 the nightly's macOS jobs run on the xcode-27 image too; its report runs on Linux" \
    is "$(q nightly '[.jobs | to_entries[] | "\(.key)=\(.value."runs-on")"] | join(",")')" \
    "test=xcode-27,dependencies=xcode-27,report=ubuntu-24.04"
check "WF08 Static checks runs check.sh --static-only; Check runs --ios-only --skip-static, one shard each (watchOS: the full local gate, nightly)" \
    is "$(q pr '[.jobs[].steps[].run // empty | select(test("check\\.sh"))] | join(";")')" \
    'scripts/check.sh --static-only;scripts/check.sh --ios-only --skip-static --shard ${{ matrix.shard }}/2'
check "WF63 Static checks installs the tools with mise before check.sh, selects no Xcode, and points SwiftLint at SourceKit" \
    is "$(q pr '[.jobs.static.steps[] | .uses // .run | split("@")[0]] | join(" ")') \
$(q pr '.jobs.static.steps[] | select(.run // "" | test("check.sh")) | .env.LINUX_SOURCEKIT_LIB_PATH')" \
    "actions/checkout jdx/mise-action scripts/check.sh --static-only /usr/share/swift/usr/lib"
check "WF61 [F32] ... and no job or step name in pr.yml claims watchOS; Check's step names --ios-only" \
    is "$(q pr '[.jobs[] | .name, .steps[].name // empty] | map(select(test("watchOS"))) | length') \
$(q pr '.jobs.check.steps[] | select(.run // "" | test("check.sh")) | .name | test("iOS.*check\\.sh --ios-only")')" "0 true"
check "WF62 [F32] the nightly still tests both platforms, each in legs (docs/ci-cd.md, \"Nightly legs\")" \
    is "$(q nightly '[.jobs.test.strategy.matrix.include[].platform] | unique | join(",")')" "ios,watch"
check "WF09 concurrency is per PR and cancels superseded runs" \
    is "$(q pr '.concurrency.group + " " + (.concurrency["cancel-in-progress"] | tostring)')" \
    'pr-${{ github.event.pull_request.number || github.ref }} true'
check "WF10 failure uploads Results and SnapshotArtifacts as results-*, per run attempt and shard (criteria 3, 5)" \
    is "$(q pr '.jobs.check.steps[] | select(.uses // "" | test("upload-artifact")) | select(.if == "failure()") | [.with.name, (.with.path | test("\\.derivedData/Results") and test("\\.derivedData/SnapshotArtifacts")), .with["include-hidden-files"]] | map(tostring) | join(" ")')" \
    'results-${{ github.run_id }}-${{ github.run_attempt }}-shard${{ matrix.shard }} true true'
check "WF11 only package checkouts and Xcode's compilation cache are cached (never DerivedData's Build, or results)" \
    is "$(jq -r '.jobs[].steps[] | select(.uses // "" | test("actions/cache")) | .with.path' "$T/pr.json" "$T/nightly.json" "$T/mc.json" | sort -u | tr '\n' ' ')" \
    ".derivedData/CompilationCache.noindex .derivedData/SourcePackages "
check "WF52 [F32] the package cache restores on an exact key only (a stale Package.resolved then resolves cold, and fails)" \
    is "$(jq -r '[.jobs[].steps[] | select(.uses // "" | test("actions/cache")) | select(.with.path == ".derivedData/SourcePackages")
        | .with | has("restore-keys")] | tostring' "$T/pr.json" "$T/nightly.json" "$T/mc.json" | tr '\n' ' ')" \
    "[false] [false] [false] "
# The compilation cache (ci-efficiency notes): restored before check.sh, which turns it on, and saved after it,
# on a red run too, under the restore step's key. Its keys hash the Xcode and both lockfiles; restore-keys are
# the key without the commit, so a run starts from its PR's (or main's) newest cache.
lockfiles="hashFiles('.xcode-version', 'LedgerKit/Package.resolved', 'Ledger.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved')"
check "WF64 the compilation cache: restore, check.sh with LEDGER_COMPILATION_CACHE=YES, then shard 1 saves under the same key, unless cancelled" \
    is "$(q pr '.jobs.check.steps | map(select(.uses // .run | test("actions/cache/(restore|save)|check\\.sh")))
        | map(.uses // .run | split("@")[0]) | join(" ")') \
$(q pr '.jobs.check.steps[] | select(.uses // "" | test("actions/cache/restore")) | [.id, .with.key, .with["restore-keys"]] | join(" ")') \
$(q pr '.jobs.check.steps[] | select(.uses // "" | test("actions/cache/save")) | [.if, .with.key, .with.path] | join(" ")') \
$(q pr '.jobs.check.steps[] | select(.run // "" | test("check.sh")) | .env.LEDGER_COMPILATION_CACHE')" \
    "actions/cache/restore scripts/check.sh --ios-only --skip-static --shard \${{ matrix.shard }}/2 actions/cache/save \
compilation-cache compilation-\${{ $lockfiles }}-\${{ github.sha }} compilation-\${{ $lockfiles }}- \
\${{ matrix.shard == 1 && !cancelled() && steps.compilation-cache.outputs.cache-hit != 'true' }} \${{ steps.compilation-cache.outputs.cache-primary-key }} \
.derivedData/CompilationCache.noindex YES"
missing=""
for f in .xcode-version LedgerKit/Package.resolved Ledger.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved; do
    [[ -f "$ROOT/$f" ]] || missing="$missing $f"
done
check "WF12 every file in the cache key exists (hashFiles of a missing file is empty)" is "$missing" ""

# ---- every workflow ------------------------------------------------------------------
unpinned="$(cat "$WF"/*.yml | grep -E '^\s*-?\s*uses:' | grep -vE 'uses:\s*[^@]+@[0-9a-f]{40}(\s|$)' || true)"
check "WF13 every action is pinned to a full commit SHA" is "$unpinned" ""
# The pin is read as check-xcode-version.sh reads it, whitespace and a CRLF stripped (F32 T4; WF57 runs it).
IFS= read -r select_xcode <<'SH'
sudo xcode-select -s "/Applications/Xcode_$(tr -d '[:space:]' < .xcode-version).app"
SH
xcode_ok=""
for w in pr nightly mc; do
    xcode_ok="$xcode_ok$(jq -r --arg sel "$select_xcode" '[.jobs[] | select(."runs-on" | startswith("ubuntu") | not)
        | [.steps[].run // "" | contains($sel)] | any] | all' "$T/$w.json")"
done
check "WF14 every macOS job selects Xcode from .xcode-version, read as check-xcode-version.sh reads it" \
    is "$xcode_ok $(grep -cF "tr -d '[:space:]' < " "$ROOT/scripts/check-xcode-version.sh")" "truetruetrue 1"
# The xcode-27 image's README: Xcode 27.0 (27A266a) is /Applications/Xcode_27.app, linked as Xcode_27.0.app.
check "WF15 .xcode-version pins 27.0 (Xcode_27.0.app on the xcode-27 image)" is "$(tr -d '[:space:]' <"$ROOT/.xcode-version")" 27.0

# A `run:` without `shell:` is `bash -e {0}`: no pipefail, so `a | b` hides a's failure.
# Only an explicit `shell: bash` (bash -eo pipefail) or `set -o pipefail` covers it.
for w in pr nightly rp mc; do
    jq -c '.defaults.run.shell as $wd | .jobs | to_entries[] | .key as $job | (.value.defaults.run.shell // $wd) as $jd
           | .value.steps | to_entries[] | select(.value.run) | {job: $job, step: (.value.name // .value.id // "#\(.key)"),
             shell: (.value.shell // $jd), run: .value.run}' "$T/$w.json"
done >"$T/runs.jsonl"
unsafe=""
while IFS= read -r line; do
    shell="$(jq -r '.shell // ""' <<<"$line")"
    run="$(jq -r .run <<<"$line")"
    stripped="$(sed -e "s/'[^']*'//g" -e 's/"[^"]*"//g' <<<"$run")" # quoted text is not a pipe
    grep -qE '(^|[^|])\|([^|]|$)' <<<"$stripped" || continue
    [[ "$shell" == bash ]] && continue
    grep -qE 'set -[a-z]*o pipefail|set -o pipefail' <<<"$run" && continue
    unsafe="$unsafe
$(jq -r '"\(.job) / \(.step)"' <<<"$line")"
done <"$T/runs.jsonl"
if [[ -z "$unsafe" ]]; then pass "WF16 every piped run step fails when an upstream command fails"; else
    fail "WF16 [F4] every piped run step fails when an upstream command fails" "no pipefail in:$unsafe"; fi

# ---- the docs-only decision (pr.yml, Scope, step "scope") ----------------------------
q pr '.jobs.scope.steps[] | select(.id == "scope") | .run' >"$T/scope.sh"
# B1: check.sh's script tests read history (RP11), so a job that runs it checks out everything.
full="$(for w in pr nightly rp mc; do q $w '.jobs | to_entries[] | select([.value.steps[].run // "" | test("scripts/check\\.sh")] | any)
    | "\(.key): fetch-depth \([.value.steps[] | select(.uses // "" | test("actions/checkout")) | .with["fetch-depth"] // 1] | first)"'; done)"
shallow="$(grep -v 'fetch-depth 0$' <<<"$full" || true)"
check "WF47 [B1] every job that runs check.sh checks out full history (fetch-depth: 0)" \
    is "$([[ -n "$full" ]] && echo found) ${shallow:-none}" "found none"
check "WF17 Scope checks out 2 commits (the merge and its base) for the scope step" \
    is "$(q pr '.jobs.scope.steps[0].with["fetch-depth"]')" 2

# pr_repo <dir> <change...>: base commit on main, a PR branch with the changes, and
# HEAD = the merge commit, as actions/checkout gives a pull_request run.
pr_repo() {
    local dir="$1"; shift
    rm -rf "$dir"; mkdir -p "$dir"
    (
        cd "$dir" || exit 1
        git init -q -b main && git config user.email adv@test && git config user.name adv
        mkdir -p Apps/Ledger LedgerKit/Sources/LedgerDomain LedgerKit/Tests/LedgerDomainTests docs tasks design .github/workflows
        for f in Apps/Ledger/LedgerApp.swift LedgerKit/Sources/LedgerDomain/Weight.swift \
            LedgerKit/Tests/LedgerDomainTests/WeightTests.swift .github/workflows/pr.yml; do
            printf 'line one of %s\nline two\nline three\nline four\n' "$f" >"$f"
        done
        echo "# docs" >docs/ci-cd.md; echo "# todo" >tasks/todo.md; echo "# readme" >README.md
        git add -A && git commit -qm base
        git switch -qc pr
        for change in "$@"; do eval "$change"; done
        git add -A && git commit -qm change
        git switch -q main && git merge -q --no-ff pr -m merge
    ) >/dev/null 2>&1
}
# scope <repo> [event]: runs the extracted step as Actions does (bash -e) and prints code=…
scope() {
    : >"$T/out"
    (cd "$1" && GITHUB_EVENT_NAME="${2:-pull_request}" GITHUB_OUTPUT="$T/out" bash -e "$T/scope.sh") >/dev/null 2>&1 || echo "step-failed"
    cat "$T/out"
}
decide() { # <name> <expected code=…> <change...>
    local name="$1" want="$2"; shift 2
    pr_repo "$T/repo" "$@"
    check "$name" is "$(scope "$T/repo")" "$want"
}
decide "WF18 docs, tasks and *.md only -> Check skipped" code=false \
    'echo more >>docs/ci-cd.md' 'echo more >>tasks/todo.md' 'echo more >>README.md' 'echo x >design/notes.md'
decide "WF19 a Swift change -> Check runs" code=true 'echo "// x" >>LedgerKit/Sources/LedgerDomain/Weight.swift'
decide "WF20 a workflow change -> Check runs" code=true 'echo "# x" >>.github/workflows/pr.yml'
decide "WF21 deleting a Swift file -> Check runs" code=true 'git rm -q Apps/Ledger/LedgerApp.swift'
decide "WF22 [F1] moving an app source file into docs/ -> Check runs" code=true \
    'git mv Apps/Ledger/LedgerApp.swift docs/LedgerApp.swift'
decide "WF23 [F1] moving a test file into tasks/ -> Check runs" code=true \
    'git mv LedgerKit/Tests/LedgerDomainTests/WeightTests.swift tasks/WeightTests.swift'
decide "WF35 [D4] a Markdown file inside LedgerKit/ -> Check runs" code=true \
    'echo x >LedgerKit/Sources/LedgerDomain/Notes.md'
pr_repo "$T/repo" 'echo more >>docs/ci-cd.md'
check "WF24 workflow_dispatch always runs Check" is "$(scope "$T/repo" workflow_dispatch)" code=true
rm -rf "$T/shallow"
git clone -q --depth 2 "file://$T/repo" "$T/shallow" 2>/dev/null
check "WF25 a depth-2 clone of the merge commit is enough to decide" is "$(scope "$T/shallow")" code=false
rm -rf "$T/shallow1"
git clone -q --depth 1 "file://$T/repo" "$T/shallow1" 2>/dev/null
check "WF26 without the base commit the step fails rather than skipping Check" \
    is "$(scope "$T/shallow1" | head -1)" step-failed

# ---- round 2: the Scope job under hostile histories ---------------------------------
# Folders Xcode syncs into a target (PBXFileSystemSynchronizedRootGroup members): every
# file in them, *.md included, becomes part of the built product.
synced="$(python3 - "$ROOT/Ledger.xcodeproj/project.pbxproj" <<'PY'
import re, sys
p = open(sys.argv[1]).read()
ids = set(re.findall(r"^\s+([0-9A-F]{24}) /\*", "\n".join(re.findall(r"fileSystemSynchronizedGroups = \((.*?)\);", p, re.S)), re.M))
for gid, body in re.findall(r"([0-9A-F]{24}) /\* [^*]* \*/ = \{\s*isa = PBXFileSystemSynchronizedRootGroup;(.*?)\};", p, re.S):
    m = re.search(r"path = ([^;]+);", body)
    if gid in ids and m: print(m.group(1).strip('"'))
PY
)"
check "WF37 the synced-folder list was read from the pbxproj" grep -q '^Apps/Ledger$' <<<"$synced"
for dir in $(grep -v '^Apps/' <<<"$synced"); do
    decide "WF38 [R5] a Markdown file in $dir/ (synced into an app target) -> Check runs" code=true \
        "mkdir -p '$dir' && echo x >'$dir/NOTES.md'"
done
decide "WF39 a rename inside docs/ -> Check skipped" code=false 'git mv docs/ci-cd.md docs/ci.md'
decide "WF46 [R5] a Markdown file in any folder outside docs/, tasks/, design/ -> Check runs" code=true \
    'mkdir -p scripts && echo x >scripts/NOTES.md'
decide "WF40 deleting a Markdown file under LedgerKit/ -> Check runs" code=true \
    'echo x >LedgerKit/Sources/LedgerDomain/Notes.md && git add -A && git commit -qm add && git switch -q main && git merge -q pr && git switch -q pr' \
    'git rm -q LedgerKit/Sources/LedgerDomain/Notes.md' 'echo more >>docs/ci-cd.md'
decide "WF41 docs plus one Swift line -> Check runs" code=true \
    'echo more >>docs/ci-cd.md' 'echo more >>tasks/todo.md' 'echo "// x" >>Apps/Ledger/LedgerApp.swift'
decide "WF42 code changed then reverted inside the PR (no net code change) -> Check skipped" code=false \
    'echo "// x" >>Apps/Ledger/LedgerApp.swift' 'git commit -qam code' 'git revert --no-edit HEAD' 'echo more >>docs/ci-cd.md'
decide "WF43a force-push replaces a code commit with docs only -> the new head skips Check" code=false \
    'echo "// x" >>Apps/Ledger/LedgerApp.swift' 'git commit -qam code' 'git reset -q --hard main' 'echo more >>docs/ci-cd.md'
decide "WF43b force-push replaces docs with code -> the new head runs Check" code=true \
    'echo more >>docs/ci-cd.md' 'git commit -qam docs' 'git reset -q --hard main' 'echo "// x" >>Apps/Ledger/LedgerApp.swift'
decide "WF44a base moved (main gained code), PR is docs only -> Check skipped" code=false \
    'git switch -q main && echo "// main" >>Apps/Ledger/LedgerApp.swift && git commit -qam moved && git switch -q pr' \
    'echo more >>docs/ci-cd.md'
decide "WF44b the PR merged the moved main in, then docs -> Check skipped (main's code is the base)" code=false \
    'git switch -q main && echo "// main" >>Apps/Ledger/LedgerApp.swift && git commit -qam moved && git switch -q pr' \
    'git merge -q --no-edit main' 'echo more >>docs/ci-cd.md'
decide "WF44c the PR merged main in and changed code -> Check runs" code=true \
    'git switch -q main && echo "// main" >>docs/ci-cd.md && git commit -qam moved && git switch -q pr' \
    'git merge -q --no-edit main' 'echo "// pr" >>LedgerKit/Sources/LedgerDomain/Weight.swift'

# Check's `if:` runs Check unless Scope said 'false' (R-D1: an empty output fails safe,
# running Check). The link must still be intact.
check "WF45 Check's condition reads Scope's code output, which Scope's step writes" \
    is "$(q pr '[.jobs.check.if, .jobs.scope.outputs.code, ([.jobs.scope.steps[] | select(.id == "scope") | .run | test("code=.*GITHUB_OUTPUT")] | tostring)] | join(" | ")')" \
    "needs.scope.outputs.code != 'false' | \${{ steps.scope.outputs.code }} | [true]"

# ---- nightly.yml -----------------------------------------------------------------------
check "WF36 nightly is manual only (no schedule spends the free minutes) and runs one at a time" \
    is "$(q nightly '[.on | keys[]] | join(",")') $(q nightly '.concurrency.group')" "workflow_dispatch nightly"
check "WF27 nightly token is empty by default; tests read, report may write issues only" \
    is "$(q nightly '[(.permissions | tojson), (.jobs.test.permissions | tojson), (.jobs.dependencies.permissions | tojson), (.jobs.report.permissions | tojson)] | join(" ")')" \
    '{} {"contents":"read"} {"contents":"read"} {"issues":"write"}'
check "WF28 report runs after test and dependencies, on failure() only" \
    is "$(q nightly '(.jobs.report.needs | join(",")) + " " + .jobs.report.if')" "test,dependencies failure()"
# The leg's own steps are check.sh's (check-wiring W88-W90: the Nightly plans, their results, the boot and pins).
check "WF29 each nightly leg runs check.sh --nightly on its platform alone, without lint, for its leg" \
    is "$(q nightly '[.jobs.test.steps[].run // empty | select(test("check\\.sh"))] | join(";")')" \
    'scripts/check.sh --nightly "--$PLATFORM-only" --skip-lint --shard "$SHARD"'

q nightly '.jobs.report.steps[0].run' >"$T/report.sh"
mkdir -p "$T/ghbin"
cat >"$T/ghbin/gh" <<'SH'
#!/bin/sh
# Fake gh: logs each call; `issue list` prints $OPEN_ISSUE (the jq-filtered number).
printf '%s\n' "$*" >>"$GH_LOG"
case "$1 $2" in "issue list") [ -n "${OPEN_ISSUE:-}" ] && echo "$OPEN_ISSUE" ;; esac
exit 0
SH
chmod +x "$T/ghbin/gh"
nightly_report() { # [open issue number]
    export GH_LOG="$T/gh.log"; : >"$GH_LOG"
    OPEN_ISSUE="${1:-}" RUN_URL="https://github.com/o/r/actions/runs/99" PATH="$T/ghbin:$PATH" \
        bash -e "$T/report.sh" >/dev/null 2>&1
}
nightly_report
check "WF30 first failure opens one issue labelled nightly that links the run (criterion 10)" \
    is "$(grep -c '^issue create' "$GH_LOG") $(grep '^issue create' "$GH_LOG" | grep -c -- '--label nightly.*actions/runs/99')" "1 1"
nightly_report 7
check "WF31 a later failure comments on the open issue instead of opening another" \
    is "$(grep -c '^issue create' "$GH_LOG") $(grep -c '^issue comment 7 .*actions/runs/99' "$GH_LOG")" "0 1"

# The leg's step, run for each matrix entry with its env against a check.sh that logs its arguments.
NB="$T/nightly-sandbox"
mkdir -p "$NB/scripts"
printf '#!/bin/sh\necho "$*" >>"$NB_LOG"\n' >"$NB/scripts/check.sh" && chmod +x "$NB/scripts/check.sh"
q nightly '.jobs.test.steps[] | select(.run // "" | test("check\\.sh")) | .run' >"$T/nightly-test.sh"
export NB_LOG="$T/nightly.log"; : >"$NB_LOG"
while IFS='|' read -r platform leg legs; do
    (cd "$NB" && PLATFORM="$platform" SHARD="$leg/$legs" bash -eo pipefail "$T/nightly-test.sh")
done < <(q nightly '.jobs.test | .steps[] as $s | select($s.run // "" | test("check\\.sh"))
    | .strategy.matrix.include[] | [.platform, .leg, .legs] | map(tostring) | join("|")')
every_leg() { # <platform> <shards file>: the check.sh arguments of each of the file's legs, in order
    local n; n="$(awk '$1 !~ /^#/ && NF { print $1 }' "$ROOT/scripts/$2" | sort -u | wc -l | tr -d ' ')"
    for ((i = 1; i <= n; i++)); do printf -- '--nightly --%s-only --skip-lint --shard %s/%s;' "$1" "$i" "$n"; done
}
check "WF48 the legs run check.sh on every iOS leg, then every watchOS leg, each --nightly without lint" \
    is "$(tr '\n' ';' <"$NB_LOG")" "$(every_leg ios nightly-shards.txt)$(every_leg watch nightly-watch-shards.txt)"
check "WF48 ... and the step's env carries the leg from the matrix" \
    is "$(q nightly '.jobs.test.steps[] | select(.run // "" | test("check\\.sh")) | .env | "\(.PLATFORM) \(.SHARD)"')" \
    '${{ matrix.platform }} ${{ matrix.leg }}/${{ matrix.legs }}'
# Each platform's legs are its shards file's, 1 to its count, so a leg added there is added here.
legs_of() { # <platform> <shards file>: "<legs in the matrix>|<the file's legs>"
    echo "$(q nightly ".jobs.test.strategy.matrix.include[] | select(.platform == \"$1\") | \"\(.leg)/\(.legs)\"" | paste -sd , -)|$(
        n="$(awk '$1 !~ /^#/ && NF { print $1 }' "$ROOT/scripts/$2" | sort -u | wc -l | tr -d ' ')"
        for ((i = 1; i <= n; i++)); do echo "$i/$n"; done | paste -sd , -)"
}
ios_legs="$(legs_of ios nightly-shards.txt)" watch_legs="$(legs_of watch nightly-watch-shards.txt)"
check "WF76 the iOS legs are nightly-shards.txt's, and the watchOS legs nightly-watch-shards.txt's, a red leg cancelling none" \
    is "$([[ "${ios_legs%|*}" == "${ios_legs#*|}" ]] && echo ios) $([[ "${watch_legs%|*}" == "${watch_legs#*|}" ]] && echo watch) \
$(q nightly '.jobs.test.strategy."fail-fast"')" "ios watch false"
check "WF75 a leg's deadline is 2 min before its step's timeout, and its job outlasts the step by the upload's time" \
    is "$(q nightly '.jobs.test | (.steps[] | select(.run // "" | test("check.sh"))) as $step
        | "\($step.env.LEDGER_XCODEBUILD_DEADLINE) \($step."timeout-minutes") \(."timeout-minutes")
 \($step."timeout-minutes" * 60 - $step.env.LEDGER_XCODEBUILD_DEADLINE)"')" "7800 132 145
 120"
# main's caches: restored under Check's keys (main-cache.yml saves them there), never saved by the nightly.
check "WF78 each leg restores main's package checkouts and compiled output under Check's keys, saves neither, and check.sh caches" \
    is "$(q nightly '[.jobs.test.steps[] | select(.uses // "" | test("actions/cache")) | .uses | split("@")[0]] | join(",")') \
$([[ "$(q nightly '[.jobs.test.steps[] | select(.uses // "" | test("actions/cache")) | .with] | sort_by(.path) | tojson')" \
== "$(q pr '[.jobs.check.steps[] | select(.uses // "" | test("actions/cache(@|/restore)")) | .with] | sort_by(.path) | tojson')" ]] && echo keys) \
$(q nightly '.jobs.test.steps[] | select(.run // "" | test("check.sh")) | .env.LEDGER_COMPILATION_CACHE')" \
    "actions/cache/restore,actions/cache/restore keys YES"
# A watch leg tests on a new, never-paired simulator of check.sh's default watch, and deletes it (run 43170933804).
watch_default="$(sed -nE 's/^WATCH_DEST="\$\{LEDGER_WATCH_DEST:-(.*)\}"$/\1/p' "$ROOT/scripts/check.sh")"
q nightly '.jobs.test.steps[] | select(.id == "watch-sim") | .run' >"$T/watch-sim.sh"
q nightly '.jobs.test.steps[] | select(.name == "Delete the watch simulator") | .run' >"$T/watch-delete.sh"
WS="$T/watch-sim" && mkdir -p "$WS/scripts" && cp "$ROOT/scripts/sim-destination.sh" "$WS/scripts/"
fake_simctl "$WS/bin"
: >"$WS/xcrun.log" && : >"$WS/output"
created="$(cd "$WS" && PATH="$WS/bin:$PATH" XCRUN_LOG="$WS/xcrun.log" SIMCTL_JSON="$ROOT/scripts/tests/fixtures/simctl/xcode-27.json" \
    GITHUB_OUTPUT="$WS/output" bash -eo pipefail "$T/watch-sim.sh" >/dev/null 2>&1 && cat "$WS/output")"
check "WF80 a watch leg first creates a new simulator of check.sh's default watch (sim-destination.sh --fresh), on watch legs only" \
    is "$(q nightly '.jobs.test.steps[] | select(.id == "watch-sim") | .if')|$(grep -cF -- "--fresh \"$watch_default\"" "$T/watch-sim.sh")|$created" \
    "matrix.platform == 'watch'|1|destination=platform=watchOS Simulator,id=C4EA7ED0-0000-4000-8000-000000000001"
check "WF80 ... check.sh tests on it (its LEDGER_WATCH_DEST; empty on an iOS leg, which keeps check.sh's default)" \
    is "$(q nightly '.jobs.test.steps[] | select(.run // "" | test("check.sh")) | .env.LEDGER_WATCH_DEST')" '${{ steps.watch-sim.outputs.destination }}'
: >"$WS/xcrun.log"
(PATH="$WS/bin:$PATH" XCRUN_LOG="$WS/xcrun.log" DESTINATION="${created#destination=}" bash -eo pipefail "$T/watch-delete.sh")
check "WF80 ... and at the end, unless cancelled, deletes that simulator, never turning the leg red" \
    is "$(grep -E '^simctl (shutdown|delete)' "$WS/xcrun.log" | tr '\n' ';')|$(q nightly '.jobs.test.steps[] | select(.name == "Delete the watch simulator") | "\(.if) \(."continue-on-error")"')" \
    "simctl shutdown C4EA7ED0-0000-4000-8000-000000000001;simctl delete C4EA7ED0-0000-4000-8000-000000000001;|\${{ !cancelled() && steps.watch-sim.outputs.destination != '' }} true"
# Performance budgets on the runner (testing-strategy §2.2): the nightly's legs alone hold timings to twice them.
check "WF79 only the nightly's legs set the performance runner factor, 2, for the test runner (a median against twice the budget); no plan sets it" \
    is "$(q nightly '.jobs.test.steps[] | select(.run // "" | test("check.sh")) | .env.TEST_RUNNER_LEDGER_PERFORMANCE_RUNNER_FACTOR') \
$(cat "$WF"/*.yml | grep -c 'LEDGER_PERFORMANCE_RUNNER_FACTOR:') $(cat "$ROOT"/TestPlans/*.xctestplan | grep -c 'LEDGER_PERFORMANCE_RUNNER_FACTOR')" "2 1 0"
# A leg that fails or reaches its deadline still uploads its bundles, as one tar (35,000 files did not extract).
check "WF77 a red or interrupted leg packs its bundles into one tar and uploads it, per leg and attempt (not when cancelled)" \
    is "$(q nightly '.jobs.test.steps | map(select(.name // "" | test("^Pack|^Upload")) | .if) | join(",")')
$(q nightly '.jobs.test.steps[] | select(.uses // "" | test("upload-artifact")) | "\(.with.path) \(.with.name)"')" \
    '${{ !cancelled() }},${{ !cancelled() }}
nightly-results.tar nightly-${{ matrix.platform }}-leg${{ matrix.leg }}-${{ github.run_id }}-${{ github.run_attempt }}'
q nightly '.jobs.test.steps[] | select(.name // "" | test("^Pack")) | .run' >"$T/pack.sh"
PK="$T/pack" && mkdir -p "$PK/.derivedData/Results/Nightly-iOS-shard1.xcresult"
(cd "$PK" && bash -eo pipefail "$T/pack.sh")
packed="$(tar -tf "$PK/nightly-results.tar" | sort | tr '\n' ' ')"
rm -rf "$PK" && mkdir -p "$PK"
(cd "$PK" && bash -eo pipefail "$T/pack.sh") && empty="$([[ -e "$PK/nightly-results.tar" ]] && echo tar || echo none)"
check "WF77 ... the tar holds what exists, and a leg that never built packs nothing and does not fail there" \
    is "$packed|${empty:-failed}" "Results/ Results/Nightly-iOS-shard1.xcresult/ |none"
check "WF49 Check interrupts xcodebuild 1-5 min before its step's timeout, so its bundle is finalized" \
    is "$(q pr '.jobs.check.steps[] | select(.run // "" | test("check.sh")) | ."timeout-minutes" * 60 - .env.LEDGER_XCODEBUILD_DEADLINE
        | . >= 60 and . <= 300')" true
# docs/ci-cd.md, "Deadline": a build of up to 1,864 s (cache restored, #94), 165 s of format and script tests, 12 s of
# catalogs and boot, and a slow runner's ~1,600 s of a shard's tests end near 3,640 s; the deadline leaves 860 s past
# that, 2 min before the step's end.
check "WF65 the deadline is 4500 s, 2 min before the step's 77 min, and the job outlasts the step (82 min)" \
    is "$(q pr '.jobs.check | (.steps[] | select(.run // "" | test("check.sh"))) as $step
        | ($step."timeout-minutes" * 60 - $step.env.LEDGER_XCODEBUILD_DEADLINE) as $interrupt
        | "\($step.env.LEDGER_XCODEBUILD_DEADLINE) \($step."timeout-minutes") \(."timeout-minutes") \($interrupt)"')" \
    "4500 77 82 120"
# Seeds on the runner (tasks/chores/2026-10-09-pr-lane-time.md): Check alone cuts the seeded properties, by the
# plan's own variable under xcodebuild's TEST_RUNNER_ prefix. The plans keep their counts, and the nightly sets none.
check "WF66 Check runs 40 property seeds, fewer than the PR plan's; no other job, and no nightly step, sets a count" \
    is "$(q pr '.jobs.check.steps[] | select(.run // "" | test("check.sh")) | .env.TEST_RUNNER_LEDGER_PROPERTY_SEED_COUNT') \
$(jq -r '.defaultOptions.environmentVariableEntries[] | select(.key == "LEDGER_PROPERTY_SEED_COUNT") | .value | tonumber > 40' "$ROOT/TestPlans/PR.xctestplan") \
$(cat "$WF"/*.yml | grep -c 'LEDGER_PROPERTY_SEED_COUNT:')" "40 true 1"
# Sweeps on the runner (tasks/chores/2026-10-17-pr-sweeps.md): Check alone keeps the sweeps' representatives. No
# plan sets LEDGER_SWEEP, and the nightly and every other job leave it unset, so they sweep in full.
check "WF67 Check sets LEDGER_SWEEP=pr for the test runner; no plan, no other job and no nightly step sets it" \
    is "$(q pr '.jobs.check.steps[] | select(.run // "" | test("check.sh")) | .env.TEST_RUNNER_LEDGER_SWEEP') \
$(cat "$WF"/*.yml | grep -c 'LEDGER_SWEEP:') $(cat "$ROOT"/TestPlans/*.xctestplan | grep -c 'LEDGER_SWEEP')" \
    "pr 1 0"

# ---- main-cache.yml (tasks/chores/2026-10-17-main-cache.md) -------------------------------------------------
# A PR's run reads only its own caches and main's, and nothing else saves on main: this workflow builds what
# Check builds, on each push to main, and saves both caches there under Check's keys.
check "WF68 main-cache runs on push to main (and by hand), skipping the paths Scope calls docs-only, one run at a time, newest wins" \
    is "$(q mc '[.on | keys[]] | join(",")') $(q mc '.on.push.branches | join(",")') $(q mc '.on.push["paths-ignore"] | join(",")') \
$(q mc '.concurrency.group + " " + (.concurrency["cancel-in-progress"] | tostring)') $(q mc '.permissions | tojson')" \
    'push,workflow_dispatch main docs/**,tasks/**,design/**,*.md main-cache true {"contents":"read"}'
# Scope's allowlist, read from its step: the filter must name the same folders and root-level Markdown.
check "WF68 ... and those are exactly the paths Scope's step skips" \
    is "$(grep -oE '^ +docs/\* \| tasks/\* \| design/\* \|' "$T/scope.sh" | tr -d ' ')$(grep -cE '^ +\*\.md\) ;;$' "$T/scope.sh")" \
    "docs/*|tasks/*|design/*|1"
# The steps up to the build are Check's own, so the job selects the same Xcode and tools and reads and
# writes the same keys; the build is check.sh's, so its compile arguments, and with them every entry's key,
# are Check's too (check-wiring W77).
setup='[.jobs | to_entries[] | select([.value.steps[].run // "" | test("scripts/check\\.sh")] | any) | select(.value."runs-on" == "xcode-27") | .value.steps[]
    | select((.uses // "" | test("actions/checkout|mise-action|actions/cache(@|/restore)")) or (.run // "" | test("xcode-select")))]'
check "WF69 its one job runs on Check's image, and its checkout, Select, mise, package cache and restore are Check's, field for field" \
    is "$(q mc '[.jobs[]."runs-on"] | join(",")') $(jq -c "$setup" "$T/mc.json" | jq 'length') \
$([[ "$(jq -cS "$setup" "$T/mc.json")" == "$(jq -cS "$setup" "$T/pr.json")" ]] && echo same)" "xcode-27 5 same"
# --build-only runs step 0 and the iOS build alone, no test plan (check-wiring W77).
check "WF70 besides Select, its one run step is check.sh --build-only, with Check's cache setting alone (no runner variables)" \
    is "$(q mc '[.jobs[].steps[].run // empty | select(test("xcode-select -s") | not)] | join(";")') \
$(q mc '.jobs[].steps[] | select(.run // "" | test("check.sh")) | .env | tojson')" \
    'scripts/check.sh --build-only {"LEDGER_COMPILATION_CACHE":"YES"}'
check "WF71 it saves the compilation cache under the restore step's key after a green build only (not red, not cancelled)" \
    is "$(q mc '.jobs[].steps | map(.uses // .run | split("@")[0] | select(test("actions/cache/|check\\.sh"))) | join(" ")') \
$(q mc '.jobs[].steps[] | select(.uses // "" | test("actions/cache/save")) | [.if, .with.key, .with.path] | join(" ")')" \
    "actions/cache/restore scripts/check.sh --build-only actions/cache/save \
\${{ success() && steps.compilation-cache.outputs.cache-hit != 'true' }} \${{ steps.compilation-cache.outputs.cache-primary-key }} \
.derivedData/CompilationCache.noindex"
check "WF71 ... and the package checkouts through actions/cache, which saves its exact key after a green job" \
    is "$(q mc '[.jobs[].steps[] | select(.with.path // "" | test("SourcePackages")) | .uses | split("@")[0]] | join(",")')" actions/cache

# ---- pr.yml's shards (docs/ci-cd.md, "Shards") -----------------------------------------------------------
# One Check job per shard of scripts/pr-shards.txt, each "--shard <n>/<count>"; WF64 shows only shard 1 saves.
count="$(awk '$1 !~ /^#/ && NF { print $1 }' "$ROOT/scripts/pr-shards.txt" | sort -u | wc -l | tr -d ' ')"
check "WF72 Check's matrix is scripts/pr-shards.txt's shards, 1 to $count, and its name and --shard say /$count; a red shard cancels no other" \
    is "$(q pr '.jobs.check.strategy | (.matrix | keys | join(",")) + " " + (.matrix.shard | map(tostring) | join(",")) + " " + (."fail-fast" | tostring)') \
$(q pr '.jobs.check.name | test("/\\d+\\)$") and endswith("/'"$count"')")') \
$(q pr '.jobs.check.steps[] | select(.run // "" | test("check.sh")) | .run | endswith("--shard ${{ matrix.shard }}/'"$count"'")')" \
    "shard $(seq "$count" | paste -sd , -) false true true"
check "WF73 each shard packs its test bundle into one tar (35,000 files failed to extract) and uploads it under its own name, replacing an earlier attempt's, after a green check.sh only" \
    is "$(q pr '.jobs.check.steps[] | select(.run // "" | test("^tar -cf")) | [.run, .env.SHARD] | join(" ")')
$(q pr '.jobs.check.steps[] | select(.uses // "" | test("upload-artifact")) | select(.if == null)
        | [.with.name, .with.path, .with["if-no-files-found"], .with.overwrite] | map(tostring) | join(" ")')" \
    'tar -cf "PR-iOS-shard$SHARD.xcresult.tar" -C .derivedData/Results "PR-iOS-shard$SHARD.xcresult" ${{ matrix.shard }}
PR-iOS-shard${{ matrix.shard }} PR-iOS-shard${{ matrix.shard }}.xcresult.tar error true'
unpack="mkdir -p .derivedData/Results
for n in $(seq "$count" | paste -sd ' ' -); do tar -xf \"PR-iOS-shard\$n.xcresult.tar\" -C .derivedData/Results; done"
check "WF74 Coverage selects and checks the Xcode, downloads every shard's tar, unpacks each where check.sh wrote it, then runs check-shards.sh" \
    is "$(q pr '.jobs.coverage.steps[] | select(.uses // "" | test("download-artifact")) | "\(.with.pattern) \(.with["merge-multiple"])"')
$(q pr '[.jobs.coverage.steps[] | .uses // .run | split("@")[0] | split("\n")[0]] | map(select(test("xcode-select") | not)) | join(" ")')
$(q pr '.jobs.coverage.steps[] | select(.name == "Unpack them") | .run | rtrimstr("\n")')" \
    "PR-iOS-shard* true
actions/checkout scripts/check-xcode-version.sh actions/download-artifact mkdir -p .derivedData/Results scripts/check-shards.sh
$unpack"
check "WF74 ... and the bundles are the ones check.sh --shard writes (its result name, in the PR lane)" \
    is "$(grep -cF '"$LANE-iOS${SHARD:+-shard${SHARD%/*}}"' "$ROOT/scripts/check.sh") $(grep -c '^LANE=PR ' "$ROOT/scripts/check.sh")" "1 1"

# ---- release-please.yml ------------------------------------------------------------------
check "WF32 release-please runs on push to main only" \
    is "$(q rp '[.on | keys[]] | join(",")') $(q rp '.on.push.branches | join(",")')" "push main"
check "WF33 release-please token: contents, pull-requests, issues write; nothing else" \
    is "$(q rp '(.permissions | tojson) + " " + (.jobs["release-please"].permissions | to_entries | map("\(.key)=\(.value)") | sort | join(","))')" \
    "{} contents=write,issues=write,pull-requests=write"
check "WF34 release-please runs on Linux and starts no other workflow (no macOS minutes)" \
    is "$(q rp '.jobs["release-please"]."runs-on"') $(grep -c 'workflow run' "$WF/release-please.yml")" "ubuntu-24.04 0"

# F32 adversarial (tasks/features/F32-xcode-27-migration/test-findings.md): the toolchain pins are code. A PR
# that changes only the Xcode pin, a lockfile, the formatter's Swift version or actionlint's labels starts Check.
decide "WF59 only .xcode-version -> Check runs" code=true 'echo 27.1 >.xcode-version'
decide "WF59 only LedgerKit/Package.resolved -> Check runs" code=true 'echo "{}" >LedgerKit/Package.resolved'
decide "WF59 only the project's Package.resolved -> Check runs" code=true \
    'mkdir -p Ledger.xcodeproj/project.xcworkspace/xcshareddata/swiftpm && echo "{}" >Ledger.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
decide "WF59 only .swiftformat -> Check runs" code=true 'echo "--swiftversion 6.4" >.swiftformat'
decide "WF59 only .github/actionlint.yaml -> Check runs" code=true 'echo "self-hosted-runner: {}" >.github/actionlint.yaml'

finish
