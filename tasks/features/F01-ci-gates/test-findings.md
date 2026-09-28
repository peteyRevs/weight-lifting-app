# F01 test findings (Adversarial Tester)

Tested commit `0c74369` on `feat/F01-ci-gates`, 2026-09-27. I wrote the tests from the brief,
`docs/ci-cd.md`, ADR-006, testing-strategy §4/§7/§8 and the artefacts. I read
`implementation-notes.md` and `scripts/tests/` only afterwards, to cross-reference.

## How to run

```sh
scripts/tests/adversarial/run.sh            # all suites, ~20 s, no network, no simulator
scripts/tests/adversarial/run.sh coverage   # suites whose file name matches
```

The runner exits 1 while any finding below is open. Each failing case names its finding, as
in `C12 [F2] …`. The suites are plain bash that runs on macOS `/bin/bash` 3.2. They need
`python3`, `jq`, `git`, `rsync` and the system Ruby, which reads the workflow YAML. WF01 runs
actionlint only if mise already has 1.7.12 installed; otherwise it is skipped.
PC12 runs `xcodebuild -showBuildSettings` offline.

| Suite | What it attacks | Result |
|---|---|---|
| `coverage-gate.adv.sh` | fixture xccov reports (the real report's shape), boundaries, attribution, iOS/watchOS disagreement, bad inputs, fake `xcrun` | 35 ok, 4 FAIL |
| `check-test-results.adv.sh` | fake `xcresulttool` trees: missing, failed, skipped or nested bundles, garbage | 18 ok |
| `check-wiring.adv.sh` | the real `check.sh` in a sandbox of stub tools; each step is failed in turn | 33 ok, 2 FAIL |
| `workflows.adv.sh` | actionlint, workflow structure, the docs-only step run in real git repos, nightly-issue and dispatch scripts run against a fake `gh` | 31 ok, 3 FAIL |
| `release-please.adv.sh` | config, manifest, marker, tags, bump rules, bootstrap-sha, commit-msg types | 16 ok |
| `ci-post-clone.adv.sh` | the real script run from `ci_scripts/` against a copied tree, plus `xcodebuild -showBuildSettings` | 11 ok, 3 FAIL |

**The harness was mutation-tested.** Each of these was caught by exactly the expected cases:
check.sh without pipefail (W04, W06, W10), `coverage-gate.sh … || true` (W04, W07, W10),
script tests with `|| echo` (W04, W12), a coverage gate lenient by 1 point (C02–C04, C09, C15, C26),
and rounding instead of flooring (C03).

**The real gate** ran once through the simulator lock and was green in 232 s. PR ran 17
targets and PR-Watch 8. LedgerDomain was 1381/1398 = 98.78 %. I checked its reports:
- LedgerDomain's files appear only under the `LedgerDomainTests` target.
- Placeholder modules do not appear in the report at all.
- iOS and watchOS agree on every file's line count today.

---

## Bugs

### F1 — Moving a source file into `docs/`, `tasks/` or `design/` skips Check (bug, high)
The docs-only step in `pr.yml` (Lint, `id: scope`) runs `git diff --name-only HEAD^1 HEAD`.
With rename detection, which is git's default, a moved file is listed only under its new
path. A PR that moves `Apps/…/X.swift` or a test file into `docs/` then counts as
docs-only. Check is skipped, and a skipped required check counts as passed. The PR can
delete production code or tests with no build and no test run.

```sh
d=$(mktemp -d) && cd "$d" && git init -qb main && git config user.email a@b && git config user.name a
mkdir -p Apps docs && printf 'a\nb\nc\n' > Apps/Foo.swift && git add -A && git commit -qm base
git switch -qc pr && git mv Apps/Foo.swift docs/Foo.swift && git commit -qm move
git switch -q main && git merge -q --no-ff pr -m merge
git diff --name-only HEAD^1 HEAD              # docs/Foo.swift        -> code=false
git diff --name-only --no-renames HEAD^1 HEAD # Apps/Foo.swift, docs/Foo.swift -> code=true
```
Tests: WF22 (app source moved to `docs/`) and WF23 (test file moved to `tasks/`). The step
itself is extracted from `pr.yml` and run under `bash -e` on a merge commit, as Actions does.
**Fix:** add `--no-renames`, or use `--name-status` and check both paths.

### F2 — iOS and watchOS reports that disagree on a file's line count can shrink the denominator (bug, medium, latent)
`coverage-gate.sh` keeps each file's best measurement by `(ratio, executableLines)`. A file with
`#if os(...)` branches compiles to different code per platform, so the two bundles can
disagree on `executableLines`. The platform with fewer lines and a higher ratio then wins,
and the other platform's uncovered lines disappear. A `0/0` measurement scores 1.0 and beats
any real one. **Adding the watchOS bundle can turn a failing gate green.**

```sh
d=$(mktemp -d)
echo '{"overall":80,"modules":{"LedgerDomain":95},"excludedModules":[],"excludedFiles":[]}' > $d/t.json
echo '{"targets":[{"name":"T","files":[{"path":"/ci/LedgerKit/Sources/LedgerDomain/A.swift","coveredLines":50,"executableLines":100}]}]}' > $d/ios.json
echo '{"targets":[{"name":"T","files":[{"path":"/ci/LedgerKit/Sources/LedgerDomain/A.swift","coveredLines":10,"executableLines":10}]}]}' > $d/watch.json
LEDGER_COVERAGE_THRESHOLDS=$d/t.json scripts/coverage-gate.sh $d/ios.json              # 50.00 % ✗, exit 1
LEDGER_COVERAGE_THRESHOLDS=$d/t.json scripts/coverage-gate.sh $d/ios.json $d/watch.json # 10 / 10, 100.00 % ✓, exit 0
```
C13 is the `0/0` variant: iOS has A 0/100 and B 1000/1000, 90.90 %, exit 1. Adding a watch
report where A is `0/0` gives 1000/1000 and exit 0.

The bug is latent today, because Domain's line counts match on both platforms (checked on
the real reports). It becomes live when a module tested on both platforms has platform
branches. LedgerDesign, Persistence, Sync and Health are all in both PR plans.

Tests: C12, C13. **Fix:** rank by `(executableLines, coveredLines)`, which is the larger
denominator and then the most covered. Better still, merge line by line
(`xccov view --file`). The implementer's two-bundle fixture uses equal line counts, so it
still passes under either fix.

### F3 — A module with a threshold passes when it is missing from the report (bug, medium, latent)
A module that has a threshold but no lines in the report gets only a note, "No executable
lines measured yet", and the gate still exits 0. Placeholders are indistinguishable from
modules whose measurement was lost. The real report shows LedgerDomain's sources only
under `LedgerDomainTests`. So a PR that removes `LedgerDomainTests` from
`TestPlans/PR*.xctestplan` defeats both checks:
- `check-test-results.sh` derives its expected list from the plan, so it passes.
- The coverage gate drops LedgerDomain.

Today the overall line (0/0) still fails that PR, but only because Domain is the one measured
module. Once any other module has code (F03/F05), the PR passes.

```sh
echo '{"overall":80,"modules":{"LedgerDomain":95,"LedgerPersistence":90},"excludedModules":[],"excludedFiles":[]}' > $d/t2.json
echo '{"targets":[{"name":"T","files":[{"path":"/ci/LedgerKit/Sources/LedgerPersistence/S.swift","coveredLines":100,"executableLines":100}]}]}' > $d/nodomain.json
LEDGER_COVERAGE_THRESHOLDS=$d/t2.json scripts/coverage-gate.sh $d/nodomain.json  # exit 0, "No executable lines measured yet: LedgerDomain."
```
Test: C14. **Fix:** a module that has been measured once must stay measured. For example,
list the gated modules in `coverage-thresholds.json` (`"required": [...]`, adding each one
when it gains code) and fail when one is absent. Alternatively, have `check-test-results.sh`
assert a fixed list of test targets per plan, rather than trusting the plan it checks.

### F4 — Nightly `run:` steps pipe without pipefail (bug, low)
A `run:` with no `shell:` executes as `bash -e {0}`. Only an explicit `shell: bash` adds
`-o pipefail`. Two steps are affected:
- In `nightly.yml` › *Test the … plan*, `xcodebuild … | mise exec -- xcbeautify` ignores
  xcodebuild's status. Here `check-test-results.sh` on the next line catches failed or
  missing bundles.
- In *Available package updates*, `swift package … update --dry-run | tee` hides a failed
  report entirely.

Pipes in `pr.yml` are safe because they live inside `check.sh`. Repro: `bash -e -c 'false | true; echo reached'`.
Test: WF16. **Fix:** `defaults: { run: { shell: bash } }` at the top of each workflow.

### F5 — Malformed thresholds exit 1 with a traceback, not 2 (bug, low)
The header promises "2: bad input". An unparseable `coverage-thresholds.json`, or one missing
`overall`, raises a Python exception and exits 1, which reads as "a threshold missed". The gate
still fails closed. Repro: `echo '{"overall": 80,' > $d/bad.json; LEDGER_COVERAGE_THRESHOLDS=$d/bad.json scripts/coverage-gate.sh $d/ios.json; echo $?` → 1.
Test: C33.

### F6 — `check.sh` under bash 3.2: a failure in step 0 loses the summary and its exit code (bug, low)
The EXIT trap calls `summary`, which runs `printf '%s\n' "${TIMINGS[@]}"`. When step 0 fails
(`mise install`, a missing tool), `TIMINGS` is still empty. Under `set -u`, bash 3.2 (macOS
`/bin/bash`, which `#!/usr/bin/env bash` resolves to here) then aborts the trap with
`TIMINGS[@]: unbound variable`, and the exit code becomes 1, whatever the step returned.
It is still non-zero, so this does not open the gate. Test: W08.
**Fix:** `${TIMINGS[@]+"${TIMINGS[@]}"}`.

### F7 — `check.sh --lint-only --skip-lint` checks nothing and prints OK (bug, low)
It runs only step 0, then prints `check.sh (--lint-only) OK` with exit 0. `--record-snapshots
--lint-only` likewise exits 0 without recording. No workflow passes these combinations
today; a typo in one would make that job a no-op. Test: W13. **Fix:** reject contradictory flags with exit 2.

### F8 — `ci_post_clone.sh` writes any `CI_BUILD_NUMBER` verbatim (bug, low; hardening)
A missing or empty value is refused (PC04–PC06). A non-numeric value (`abc`), an invalid
`CFBundleVersion` (`1.2.3.4`) or a value containing a newline is appended as is. The newline
case injects a second build setting, e.g. `CURRENT_PROJECT_VERSION = 5` followed by
`DEVELOPMENT_TEAM = ATTACKER`. Xcode Cloud always sets an integer, so in practice this is a
late, confusing upload failure rather than an attack.
```sh
t=$(mktemp -d); mkdir -p $t/Config && cp Config/Base.xcconfig $t/Config/
(cd ci_scripts && CI_PRIMARY_REPOSITORY_PATH=$t CI_BUILD_NUMBER=abc ./ci_post_clone.sh); echo $?  # 0
tail -1 $t/Config/Base.xcconfig                                                                     # CURRENT_PROJECT_VERSION = abc
```
Test: PC07. **Fix:** `case $CI_BUILD_NUMBER in ''|*[!0-9]*) exit 1;; esac`.

---

## Design questions (no failing test)

- **D1 — The gates only advise until branch protection exists.** It needs GitHub Pro or a
  public repo (checklist §0, implementation notes). Until Pete decides, nothing enforces
  `Lint` or `Check`, and criterion 6 fails. This is the largest gap, and it is Pete's call.
- **D2 — A PR can weaken its own gate.** `pull_request` and `workflow_dispatch` both run the
  PR branch's own `pr.yml`, `check.sh`, `coverage-thresholds.json` and test plans. The PR
  can lower a threshold, add a module to `excludedModules`, disable a plan target
  (`check-test-results` skips `enabled: false`), or drop a step, while keeping the job
  names green. Approvals are 0 and Code Owners is off, so only review gates G3/G5 stand in
  the way. Proposal: a reviewer checklist item "gate files changed?". Add explicit
  CODEOWNERS lines for `.github/`, `scripts/`, `TestPlans/` and `ci_scripts/` now, so they
  bind the day a second maintainer joins.
- **D3 — Squash-merge titles are not checked.** The commit-msg hook sees only local commits.
  On `main` the squash subject is the PR title. A PR titled `Add Today screen` merges as a
  non-conventional commit, and release-please silently leaves it out of both version and
  changelog. Proposal: the Lint job runs `scripts/check-commit-msg.sh` on
  `github.event.pull_request.title`.
- **D4 — Any `*.md` counts as docs, including ones under `LedgerKit/` or `Apps/`.** None exist
  today. A Markdown file declared as a package resource could change the build while Check is
  skipped. Proposal: treat `.md` as docs only outside `LedgerKit/` and `Apps/`.
- **D5 — Files can opt out of coverage by name.** `*+Previews.swift` and `*/Generated/*`
  exclude any file named that way, logic included. A module that is both thresholded and in
  `excludedModules` passes silently, with only the "not measured yet" note. Proposal: fail
  when a module has a threshold and an exclusion at once.
- **D6 — `LedgerDependencies` has no threshold and no exclusion.** This is acknowledged in
  implementation notes #2. The gate fails closed the day F07 gives it an executable line, and
  F07's brief should say so.
- **D7 — `--record-snapshots` may record nothing.** *Not executed; it needs F06's snapshot
  tests.* `check.sh` exports `SNAPSHOT_TESTING_RECORD=all`, but `xcodebuild test` forwards
  only `TEST_RUNNER_`-prefixed variables into simulator test processes. This is F00's code.
  Verify with the first snapshot test (criterion 5's probe PR).
- **D8 — `coverage-gate.sh` resolves relative paths from the repo root.** It `cd`s there first,
  so relative inputs and `LEDGER_COVERAGE_THRESHOLDS` resolve against the root rather than
  the caller's directory. Run from elsewhere, a relative path is either not found (exit 2) or
  finds a different file of the same name under the root.
- **D9 — `nightly.yml` has no `concurrency`.** A manual dispatch that overlaps the scheduled
  run can race between `gh issue list` and `gh issue create` and open two issues. Proposal:
  `concurrency: { group: nightly }`.

## What held (evidence, not findings)

**Coverage gate:**
- The boundaries are exact: 95.00 passes, 94.99 fails, and 94.995 is floored to 94.99 and fails.
- Decimal thresholds work, and overall is enforced on its own.
- `LedgerDomainExtras` is not merged into LedgerDomain, and it fails for lacking a threshold.
- These never count: `Apps/`, `LedgerKit/Tests/`, SPM checkouts, `…/NotLedgerKit/Sources/…`,
  and loose files directly under `Sources/`.
- Exclusions work, and so does `Feature*`.
- Missing, empty, truncated, `null` or garbage reports fail. So does a bundle without
  coverage, whether xccov is faked or real, and so do malformed thresholds.
- The ✗ row reaches `$GITHUB_STEP_SUMMARY` (criterion 4).

**`check-test-results.sh`:**
- It fails closed on a failed, missing, skipped or "Expected Failure" bundle.
- It also fails closed on an extra tree level, non-JSON output, a node without `nodeType`,
  and a missing or empty plan.
- No committed plan disables a target.

**`check.sh` wiring:**
- An injected failure in any of the 14 steps stops the run non-zero, and no later step runs.
  The steps include xcodebuild, xcbeautify, check-test-results and the coverage gate.
- xcodebuild's own exit code (65) propagates.
- `--skip-lint` and `--lint-only` run exactly their steps.
- The Actions reporters are passed only on Actions (criterion 2).

**Workflows:**
- actionlint 1.7.12 with shellcheck reports 0 errors.
- Every action is pinned by SHA. I also checked each pin against its tag with `git ls-remote`
  once, online: all 5 match.
- The job names match branch protection. Permissions are minimal and set per job.
- Concurrency is per PR. A cancelled run is always an older SHA, so it cannot pass or block
  the head.
- Only `.derivedData/SourcePackages` is cached, never build products or results. Every
  cache-key file exists.
- Xcode is chosen from `.xcode-version`.
- A depth-2 checkout is enough for the docs-only decision, and depth 1 fails the step rather
  than skipping Check.
- The nightly report opens one issue, then comments on it. The release PR's dispatch
  targets its head branch.

**release-please:**
- The marker, the manifest and `MARKETING_VERSION` agree at 0.1.0. Tags are `vX.Y.Z`.
- `feat` bumps the minor, and only feat, fix and perf are visible in the changelog.
- bootstrap-sha is an ancestor of HEAD, and nothing overrides `MARKETING_VERSION`.
- Release-please's own behaviour was not executed here (it needs the GitHub API). What each
  merge type does follows from the config and was verified by the implementer with the
  release-please library:
  - `feat:` → 0.1.0 to 0.2.0.
  - `fix:` / `perf:` → patch.
  - `ci:`, `docs:`, `chore:`, `test:`, `build:` or `refactor:` alone → empty changelog, so no
    release PR.
  - `feat!:` → minor while below 1.0.

**Post-clone:**
- It refuses a missing or empty build number and a missing repository path.
- It is idempotent, and it copes with a missing final newline.
- It is committed with mode 100755.
- `xcodebuild -showBuildSettings` resolves `CURRENT_PROJECT_VERSION = 4242` for both
  `Ledger` and `LedgerWatch`.

---

## Round 2 (19d4050: fixes F1–F8, single macOS job, no branch protection)

Tested 2026-09-27 at `19d4050`. I read only the "Where I changed the tester's tests" section of
`implementation-notes.md`. Nothing is committed.

### Audit of the implementer's changes to this suite

My round-1 suite was untracked at `0c74369`, so `git diff 0c74369..19d4050` shows it as all new.
To audit it, I rebuilt my round-1 files in scratch and diffed them against `19d4050`.

- **Unchanged, byte for byte:** `lib.sh`, `run.sh`, `check-test-results.adv.sh`,
  `check-wiring.adv.sh`, `ci-post-clone.adv.sh` and `release-please.adv.sh`.
- **`workflows.adv.sh`: accepted.** Every change follows from Pete's decisions or a fix:
  - WF04/05/07/08/17 now describe the design where Scope runs, then Check.
  - WF11's jq now tolerates a workflow with no cache step. It is not weaker: the set of
    cached paths must still be exactly `.derivedData/SourcePackages`.
  - WF33/34 lose the release-PR dispatch (see R-D4).
  - WF35 and WF36 are new.
- **`coverage-gate.adv.sh`: accepted, except one side effect, which I repaired (R2 below).**
  C09b's `feature.json` and the new C14b are correct. C14b even catches a mutant that C14
  alone misses.

### Findings

#### R1 — The committed suite turned `check.sh` red (my test bug, high, fixed in the test)
RP06 lists every tracked file that carries the `x-release-please-` marker. Once `19d4050`
committed the suite, two of its own files matched: `release-please.adv.sh` and
`ci-post-clone.adv.sh` quote the marker. In round 1 they were untracked, so this never showed.

**Result at `19d4050`:** `scripts/check.sh --lint-only` exits 1 at step 2 (RP06), so G5 could
not have merged it.

**Fix (test only):** RP06 skips `scripts/tests/`. It now also searches untracked files, so a
marker that is added but not yet committed is caught too. Verified by planting
`Config/Probe.xcconfig` with a marker: RP06 fails, then passes again once the file is removed.

#### R2 — The shared `"required": ["LedgerDomain"]` hid what C05, C09a and C31 test (weakening, repaired)
With `required`, any unlisted module fails the gate by itself. After the change:
- C05's report (Design + Feature) failed because neither module was required, not because
  overall was below 80.
- C09a failed because FeatureToday was not required, not because of `Feature*`.

**Evidence:** two mutants survived the committed suite with zero failing cases:
- the overall check removed (`row("Overall", …, 0)`);
- every wildcard threshold 5 points lenient.

**Repair:**
- C05 and C09a use thresholds files that require exactly the modules they measure.
- New C05b, C09c and C31b assert the only error line.
- Both mutants are now caught: no-overall by C05/C05b, lenient-wildcard by C09a/C09c/C31b.

#### R3 — A module gated only by `Feature*` can be excluded silently (bug, low)
The new "cannot be both gated and excluded" check compares exact names
(`set(limits) & set(excluded)`). `"excludedModules": ["FeatureToday"]` with the `Feature*`
threshold is accepted. FeatureToday's 500 uncovered lines vanish, and the gate exits 0.

It takes a visible config edit, and FeatureToday must not be in `required`. Test: C43.
**Fix:** match each excluded module against the threshold patterns with `fnmatchcase`.

#### R4 — `required` is not type-checked (bug, low)
The gate still fails closed, but not with exit 2 ("bad input") as the header promises:
- `"required": "LedgerDomain"` is split into characters, one "has no threshold" row per
  letter, and exits 1.
- `"required": ["LedgerDomain", 7]` crashes with a `TypeError` traceback, exit 1.

`null` is rejected correctly (exit 2). Tests: C46, C47.
**Fix:** validate `required` as a list of strings next to the number checks.

#### R5 — A `.md` file in `Resources/Fonts/` ships in both apps while Scope calls the PR docs-only (bug, low)
`Resources/Fonts` is a `PBXFileSystemSynchronizedRootGroup` in both the `Ledger` and
`LedgerWatch` targets, so every file in it is bundled. The Scope step treats only `Apps/*`
and `LedgerKit/*` as code whatever the extension. So a PR that only adds
`Resources/Fonts/NOTES.md` runs no Check, yet changes both app bundles. A name that
collides with another bundled resource would break the build ("Multiple commands produce").

WF38 derives the synced folders from the pbxproj, so the test follows the project.
**Fix:** treat `Resources/*` as code, like `Apps/*`, or any folder synced into a target.

**Bundling evidence (full-gate build):** `Resources/Fonts/OFL.txt`, a non-code file like a
`.md` would be, is inside both `Ledger.app` and `LedgerWatch.app`.

### Design questions (round 2)

- **R-D1 — The Check condition fails open.** Check's `if:` is
  `needs.scope.outputs.code == 'true'`. A typo in the step id or output name would leave the
  output empty and skip Check on every PR. Each skip looks exactly like a docs-only skip.
  actionlint catches such typos, but it does not run in CI: WF01 is skipped when mise has no
  actionlint, and `mise.toml` does not pin it. WF45 now guards the link statically.
  Proposal: `if: needs.scope.outputs.code != 'false'`, so a missing value runs Check, and pin
  actionlint in `mise.toml`.
- **R-D2 — A skipped Check under G5.** G5 says "CI is green too whenever CI ran". A docs-only
  PR shows Scope ✓ and Check *skipped*, which `gh pr checks` also counts as passing. The
  Scope step no longer prints the `::notice::` that explained a skip. G5's local full
  `check.sh` still covers a misjudged scope. Proposal: G5 treats a skipped Check as a pass
  only when Scope's log says `code=false`, and restore the notice.
- **R-D3 — No run ever saves the SPM cache on `main`.** PR caches are scoped to the PR's merge
  ref, and other PRs can restore only from `main`. The nightly lost its cache step and is
  manual; release-please runs on Linux without one. So every PR's first Check resolves
  packages cold. This costs minutes, not correctness. Proposal: an occasional
  `workflow_dispatch` of `pr.yml` on `main`.
- **R-D4 — The release PR gets no CI.** A PR opened with `GITHUB_TOKEN` starts no workflow,
  and the dispatch is gone to save minutes. The release PR edits `Config/Base.xcconfig`, so
  only G5's local `check.sh` and Pete's release review cover it. The static RP02–RP05 checks
  guard the marker line. This is acceptable under G5 as written. Recorded so the gap is
  deliberate.
- **R-D5 — The F2 fix fails closed but can be over-strict.** When the two platforms disagree,
  the measurement with more lines wins wholesale. Say iOS covers 99 of 100 lines, and a
  watch-only branch makes it 101 lines on watchOS, where no test runs it (0 covered). The
  file then counts 0/101 = 0 %. The gate is never too lenient, but a module tested on one
  platform only can become unpassable. The exact answer is a per-line union
  (`xccov view --file`). Repro:
  `iOS {"coveredLines":99,"executableLines":100}` with `watch {0, 101}` gives 0.00 %.

### Scope job: what held (new cases WF39–WF45)

**Rename, deletion and mixed-commit cases** (WF22, WF23, WF35, WF39–WF41):
- Moving code or tests into `docs/` or `tasks/` runs Check.
- A rename inside `docs/` skips it.
- Deleting a `.md` under `LedgerKit/` runs Check.
- Docs plus one Swift line runs Check.

**History cases:**
- A code change reverted within the PR skips Check. The merge tree has no code change, which
  is correct (WF42).
- A force-push that replaces code with docs, or docs with code, is judged on the new merge
  only (WF43a/b).
- When the base moves, Scope diffs against the new base (WF44a–c). A docs-only PR stays
  docs-only even when main gained code, and even when the PR merged that main in. A PR that
  merged main and changed code runs Check.
- A depth-1 checkout fails the step rather than skipping Check (WF26).

**Unusual file names:** git quotes non-ASCII and control characters (`"docs/…"`), so they
match no docs pattern and run Check. Only the safe direction is possible.

**Concurrency:** the group key and `cancel-in-progress` are unchanged (WF09). A cancel only
ever hits the older SHA's run, and Scope and Check are cancelled together.

**Caching:** only `.derivedData/SourcePackages` is cached, and every file in the key exists
(WF11, WF12).

**actionlint 1.7.12:** 0 errors on the new workflows.

### The suite gates `check.sh`: live proof

`scripts/tests/adversarial.test.sh` execs `run.sh` from step 2 (W20–W22 check this
statically). I checked the loop live on the committed suite plus the RP06 fix, restoring
each file afterwards and confirming with `git diff`:

| Step | `check.sh --lint-only` | Failing cases |
|---|---|---|
| Committed tree | exit 0 | none |
| `--no-renames` removed from `pr.yml` (F1 reopened) | exit 1 | WF22, WF23 |
| `pr.yml` restored | exit 0 | none |
| `coverage-gate.sh` back to ratio-wins (F2 reopened) | exit 1 | C12, C13 |
| `coverage-gate.sh` restored | (restored) | |

**Mutation checks on the coverage suite** (each mutant is caught):

| Mutant | Caught by |
|---|---|
| no "has coverage now" failure | C36, C36b, C37b, C44 |
| required modules not iterated | C14b, C37b, C38 |
| no contradiction check | C41, C42, C45 |
| ratio-wins | C12, C13, C49 |
| no overall check | C05, C05b |
| lenient wildcard | C09a, C09c, C31b |

### Full gate on `19d4050`

I ran the full gate once through the simulator lock, on `19d4050` plus the RP06 test fix,
with the committed suite. Result: **green in 251 s**.
- Step 2 passed: the adversarial suite and `coverage-gate.test.sh` (10 cases).
- PR ran 17 targets and PR-Watch ran 8.
- The coverage gate passed with `required: ["LedgerDomain"]`: 1381/1398 = 98.78 %.

I deleted `.derivedData` afterwards.

With my round-2 cases added, step 2 fails on R3–R5 until they are fixed. That is the
intended loop.

### Round 2 status

The suite now has 194 cases: 190 pass and 4 fail. The runner exits 1 until R3, R4 and R5
are fixed:

| Case | Finding |
|---|---|
| C43 | R3 |
| C46, C47 | R4 |
| WF38 | R5 |

Every F1–F8 case passes at `19d4050`.
