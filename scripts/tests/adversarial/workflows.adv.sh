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
q() { jq -r "$2" "$T/$1.json"; } # q <pr|nightly|rp> <jq filter>

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
# Pete, 2026-09-27: free minutes, so ONE macOS job (lint + both platforms) behind a Linux scope job.
check "WF04 jobs are Scope then Check" is "$(q pr '[.jobs[].name] | join("|")')" "Scope|Check"
check "WF05 Check needs Scope" is "$(q pr '.jobs.check.needs')" scope
check "WF06 PR token is contents: read, with no job-level override" \
    is "$(q pr '.permissions | tojson') $(q pr '[.jobs[] | has("permissions")] | any')" '{"contents":"read"} false'
# Pete, 2026-09-29 (F32): Xcode 27 now, so every macOS job runs on the xcode-27 preview image.
check "WF07 exactly one macOS job (Check, on the xcode-27 image); Scope runs on Linux" \
    is "$(q pr '[.jobs | to_entries[] | "\(.key)=\(.value."runs-on")"] | join(",")')" "scope=ubuntu-latest,check=xcode-27"
check "WF50 the nightly's macOS jobs run on the xcode-27 image too; its report runs on Linux" \
    is "$(q nightly '[.jobs | to_entries[] | "\(.key)=\(.value."runs-on")"] | join(",")')" \
    "test=xcode-27,dependencies=xcode-27,report=ubuntu-latest"
check "WF08 Check runs the whole of check.sh, lint included" \
    is "$(q pr '[.jobs[].steps[].run // empty | select(test("check.sh"))] | join(";")')" "scripts/check.sh"
check "WF09 concurrency is per PR and cancels superseded runs" \
    is "$(q pr '.concurrency.group + " " + (.concurrency["cancel-in-progress"] | tostring)')" \
    'pr-${{ github.event.pull_request.number || github.ref }} true'
check "WF10 failure uploads Results and SnapshotArtifacts as results-* (criteria 3, 5)" \
    is "$(q pr '.jobs.check.steps[] | select(.uses // "" | test("upload-artifact")) | [.if, (.with.name | startswith("results-")), (.with.path | test("\\.derivedData/Results") and test("\\.derivedData/SnapshotArtifacts")), .with["include-hidden-files"]] | map(tostring) | join(" ")')" \
    "failure() true true true"
check "WF11 only package checkouts are cached (never build products or results)" \
    is "$(jq -r '.jobs[].steps[] | select(.uses // "" | test("actions/cache")) | .with.path' "$T/pr.json" "$T/nightly.json" | sort -u | tr '\n' ' ')" \
    ".derivedData/SourcePackages "
check "WF52 [F32] the package cache restores on an exact key only (a stale Package.resolved then resolves cold, and fails)" \
    is "$(jq -r '[.jobs[].steps[] | select(.uses // "" | test("actions/cache")) | .with | has("restore-keys")] | tostring' "$T/pr.json" "$T/nightly.json" | tr '\n' ' ')" \
    "[false] [] "
missing=""
for f in .xcode-version LedgerKit/Package.resolved Ledger.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved; do
    [[ -f "$ROOT/$f" ]] || missing="$missing $f"
done
check "WF12 every file in the cache key exists (hashFiles of a missing file is empty)" is "$missing" ""

# ---- every workflow ------------------------------------------------------------------
unpinned="$(cat "$WF"/*.yml | grep -E '^\s*-?\s*uses:' | grep -vE 'uses:\s*[^@]+@[0-9a-f]{40}(\s|$)' || true)"
check "WF13 every action is pinned to a full commit SHA" is "$unpinned" ""
xcode_ok=""
for w in pr nightly; do
    xcode_ok="$xcode_ok$(q $w '[.jobs[] | select(."runs-on" | startswith("ubuntu") | not) | [.steps[].run // "" | test("xcode-select -s \"/Applications/Xcode_\\$\\(cat \\.xcode-version\\)\\.app\"")] | any] | all')"
done
check "WF14 every macOS job selects Xcode from .xcode-version" is "$xcode_ok" truetrue
# The xcode-27 image's README: Xcode 27.0 (27A266a) is /Applications/Xcode_27.app, linked as Xcode_27.0.app.
check "WF15 .xcode-version pins 27.0 (Xcode_27.0.app on the xcode-27 image)" is "$(tr -d '[:space:]' <"$ROOT/.xcode-version")" 27.0

# A `run:` without `shell:` is `bash -e {0}`: no pipefail, so `a | b` hides a's failure.
# Only an explicit `shell: bash` (bash -eo pipefail) or `set -o pipefail` covers it.
for w in pr nightly rp; do
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
full="$(for w in pr nightly rp; do q $w '.jobs | to_entries[] | select([.value.steps[].run // "" | test("scripts/check\\.sh")] | any)
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
check "WF29 each nightly plan exists and its results are checked" \
    is "$(for p in $(q nightly '.jobs.test.strategy.matrix.include[].plan'); do [[ -f "$ROOT/TestPlans/$p.xctestplan" ]] && echo -n ok; done) $(q nightly '.jobs.test.steps[] | select(.run // "" | test("xcodebuild test")) | .run | test("check-test-results.sh")')" \
    "okok true"

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

# F01's first CI run: a watch destination by name was ambiguous on the runner (exit 70). The second: parallel
# testing's clones each paid a first boot, and the step timed out. The nightly's test step runs here with
# the real sim-destination.sh and sim-boot.sh against the xcode-27 image's simulators; xcrun and xcodebuild log to
# one file, in order.
NB="$T/nightly-sandbox"
mkdir -p "$NB/scripts" "$NB/bin"
cp "${ADV_SIM_DESTINATION:-$ROOT/scripts/sim-destination.sh}" "$NB/scripts/sim-destination.sh"
cp "${ADV_SIM_BOOT:-$ROOT/scripts/sim-boot.sh}" "$NB/scripts/sim-boot.sh"
fake_simctl "$NB/bin"
cat >"$NB/bin/xcodebuild" <<'SH'
#!/bin/sh
action="$1" dest="" parallel="" pinned=no diag=""
while [ $# -gt 0 ]; do
    case "$1" in
        -destination) dest="$2" ;; -parallel-testing-enabled) parallel="$parallel$2" ;;
        -parallel-testing-worker-count) parallel="$parallel+workers" ;;
        -onlyUsePackageVersionsFromResolvedFile) pinned=yes ;; -collect-test-diagnostics) diag="$2" ;;
    esac
    shift
done
echo "xcodebuild $action $dest parallel=$parallel" >>"$XCRUN_LOG"
echo "$action pinned=$pinned" >>"$XCRUN_LOG.pins"
echo "$action diagnostics=$diag" >>"$XCRUN_LOG.diag"
SH
printf '#!/bin/sh\ncat\n' >"$NB/bin/mise"
printf '#!/bin/sh\n' >"$NB/scripts/check-test-results.sh"
chmod +x "$NB/bin/xcodebuild" "$NB/bin/mise" "$NB/scripts/check-test-results.sh"
q nightly '.jobs.test.steps[] | select(.run // "" | test("xcodebuild test")) | .run' >"$T/nightly-test.sh"
export XCRUN_LOG="$T/nightly.log"; : >"$XCRUN_LOG"; : >"$XCRUN_LOG.pins"; : >"$XCRUN_LOG.diag"
nightly_ok=0
while IFS='|' read -r plan scheme destination; do
    (cd "$NB" && PLAN="$plan" SCHEME="$scheme" DESTINATION="$destination" PATH="$NB/bin:$PATH" \
        bash -eo pipefail "$T/nightly-test.sh" >/dev/null 2>&1) && nightly_ok=$((nightly_ok + 1))
done < <(q nightly '.jobs.test.strategy.matrix.include[] | [.plan, .scheme, .destination] | join("|")')
i="46F7C9EA-B38C-445A-BAD9-8A70A603E9E1" w="2416B270-8634-4D4A-9084-2B04B4498921" # the xcode-27 image's
check "WF48 the nightly boots, builds, waits for the boot and tests serially, each simulator by UDID" \
    is "$nightly_ok $(grep -E '^(simctl boot|xcodebuild)' "$XCRUN_LOG" | tr '\n' ';')" \
    "2 simctl boot $i;xcodebuild build-for-testing platform=iOS Simulator,id=$i parallel=;simctl bootstatus $i -b;\
xcodebuild test-without-building platform=iOS Simulator,id=$i parallel=NO;simctl boot $w;\
xcodebuild build-for-testing platform=watchOS Simulator,id=$w parallel=;simctl bootstatus $w -b;\
xcodebuild test-without-building platform=watchOS Simulator,id=$w parallel=NO;"
check "WF51 [F32] every nightly xcodebuild resolves packages only to the committed Package.resolved" \
    is "$(tr '\n' ';' <"$XCRUN_LOG.pins")" \
    "build-for-testing pinned=yes;test-without-building pinned=yes;build-for-testing pinned=yes;test-without-building pinned=yes;"
check "WF53 [F32] every nightly test run passes -collect-test-diagnostics never (a 600 s simctl diagnose on failure)" \
    is "$(grep '^test' "$XCRUN_LOG.diag" | tr '\n' ';')" "test-without-building diagnostics=never;test-without-building diagnostics=never;"
check "WF49 Check interrupts xcodebuild 1-5 min before its step's timeout, so its bundle is finalized" \
    is "$(q pr '.jobs.check.steps[] | select(.run // "" | test("check.sh")) | ."timeout-minutes" * 60 - .env.LEDGER_XCODEBUILD_DEADLINE
        | . >= 60 and . <= 300')" true

# ---- release-please.yml ------------------------------------------------------------------
check "WF32 release-please runs on push to main only" \
    is "$(q rp '[.on | keys[]] | join(",")') $(q rp '.on.push.branches | join(",")')" "push main"
check "WF33 release-please token: contents, pull-requests, issues write; nothing else" \
    is "$(q rp '(.permissions | tojson) + " " + (.jobs["release-please"].permissions | to_entries | map("\(.key)=\(.value)") | sort | join(","))')" \
    "{} contents=write,issues=write,pull-requests=write"
check "WF34 release-please runs on Linux and starts no other workflow (no macOS minutes)" \
    is "$(q rp '.jobs["release-please"]."runs-on"') $(grep -c 'workflow run' "$WF/release-please.yml")" "ubuntu-latest 0"

# F32 adversarial (tasks/features/F32-xcode-27-migration/test-findings.md): the toolchain pins are code. A PR
# that changes only the Xcode pin, a lockfile, the formatter's Swift version or actionlint's labels starts Check.
decide "WF59 only .xcode-version -> Check runs" code=true 'echo 27.1 >.xcode-version'
decide "WF59 only LedgerKit/Package.resolved -> Check runs" code=true 'echo "{}" >LedgerKit/Package.resolved'
decide "WF59 only the project's Package.resolved -> Check runs" code=true \
    'mkdir -p Ledger.xcodeproj/project.xcworkspace/xcshareddata/swiftpm && echo "{}" >Ledger.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
decide "WF59 only .swiftformat -> Check runs" code=true 'echo "--swiftversion 6.4" >.swiftformat'
decide "WF59 only .github/actionlint.yaml -> Check runs" code=true 'echo "self-hosted-runner: {}" >.github/actionlint.yaml'

finish
