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
