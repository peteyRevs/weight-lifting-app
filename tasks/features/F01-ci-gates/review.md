# F01 — Review

This is the reviewer pass on `feat/F01-ci-gates` at `97fbab8`. The diff reviewed is
`git diff main...HEAD`, with `main` at `8404d02`: 4 commits and 31 files. I am a fresh agent
and did not write this code. Pete's decisions of 2026-09-27 are treated as requirements, not
findings:
- the free plan, with no branch protection;
- one lean macOS job per PR behind a Linux scope job;
- a manual nightly;
- Xcode Cloud and criteria 6, 7 and 9 as his manual steps.

## Verdict

**Changes requested: 1 Blocking, 3 Should fix, 10 Nits.**

- **Blocking (B1).** Every code PR's `Check` would fail on GitHub whatever the code.
  - Test RP11 needs git history.
  - The Check job's checkout is depth 1.
  - The failure is in `check.sh` step 2.
  - I reproduced it, and the code-review pass found it independently. The fix is two lines.
- **Otherwise the work is strong.**
  - Workflow security is tight: permissions are minimal per job, every action is SHA-pinned (all 5 pins match their tags), there is no `pull_request_target`, and `run:` blocks contain no `${{ }}`.
  - The coverage gate fails closed.
  - The Scope job is rename-safe and uses an allowlist.
  - Release-please behaves as intended, which I confirmed with the library itself.
  - The adversarial suite catches every mutation I tried (8 of 8).
- **After B1 is fixed,** the remaining acceptance criteria are *pending: first GitHub run* or *pending: Pete (manual)*. The map below lists each one.

## Gate and checks run

| Check | Result |
|---|---|
| `scripts/check.sh --lint-only` (host, `/bin/bash` 3.2.57) | **OK in 30 s.** Format and `swiftlint --strict` are clean and the package graph matches. The adversarial suites pass 195 cases (18 + 38 + 14 + 60 + 16 + 49), and `coverage-gate.test.sh` passes 10. |
| Full `scripts/check.sh` through the simulator lock | **OK in 272 s** (lint 27 s, iOS 165 s, watchOS 77 s, coverage 2 s). PR ran 17 test targets and PR-Watch 8, all passing. Coverage gate: LedgerDomain and overall are both at 1381/1398 = **98.78 %**. It is green locally only because the worktree has full history (B1). |
| The suites in a **CI-shaped checkout** (`git clone --depth 1`, `GITHUB_ACTIONS=true CI=true`, `GITHUB_STEP_SUMMARY` set) | **`run.sh` exits 1: `FAIL RP11 … fatal: Not a valid commit name 8404d022…`.** Everything else passes, and nothing writes into the step summary (0 bytes). |
| Mutation checks (scratch clone, one mutant at a time) | 8 of 8 caught. See §Tests. |
| Action pins (`git ls-remote` against each tag) | All 5 match: checkout v7.0.1, mise-action v4.3.0, cache v6.1.0, upload-artifact v7.0.1, release-please-action v5.0.0. |
| release-please 17.11.2 (the library, run offline) | feat + fix + chore goes from 0.1.0 to **0.2.0** with 2 visible entries (Features, Fixes). The `Generic` updater rewrites only `MARKETING_VERSION = 0.2.0 // x-release-please-version`. |
| Linters with the Actions reporters, on a probe file | SwiftLint exits 2 with `::error file=…/CIProbe.swift,line=4,col=14::Force unwrapping…`. SwiftFormat exits 1 with `::warning file=…,line=N::…`. |
| shellcheck 0.11.0 (the pinned version) | Production scripts are clean except the known F00 false positive (`check.sh:52`, SC2154). Test suites: minor warnings only (N8). |
| `code-review` skill, level high | It found B1 independently. Its other findings are S2, S3 and N1, N6, N7, N11 and N13 below. |

## Findings

### Blocking

**B1. `Check` goes red on every code PR: RP11 needs git history that CI's checkout does not have.**
- **Where:**
  - `scripts/tests/adversarial/release-please.adv.sh:45-46` runs `git merge-base --is-ancestor <bootstrap-sha> HEAD`;
  - `.github/workflows/pr.yml:61`: Check's `actions/checkout` has no `with:`, so it fetches depth 1.
- **Failure path:**
  1. On the runner, only the PR's merge commit exists, so `8404d02` is not a valid object.
  2. RP11 fails, `run.sh` exits 1, and `scripts/tests/adversarial.test.sh` execs it from `check.sh` step 2 (`for test in scripts/tests/*.test.sh`).
  3. `check.sh` exits 1 about 2–3 minutes into every code PR run and every `workflow_dispatch`, whatever the change.
  4. Under G5 ("CI is green whenever it ran"), nothing could merge. Every PR would also burn roughly 3 macOS minutes on a false red.
- **Evidence:** a depth-1 clone of this branch gives `FAIL RP11 bootstrap-sha is an ancestor of HEAD` / `fatal: Not a valid commit name 8404d022e1b46b29a2f5eaa2c814267fa74b5aa0`, and `release-please.adv.sh: 15 passed, 1 failed`.
  - It passed locally only because the worktree has full history.
  - No other case depends on history: `git ls-files -s` (W21, PC09) and `git ls-files` (RP06) work shallow.
- **Fix (preferred, +2 non-test lines):** in `pr.yml` Check, add `with: { fetch-depth: 0 }` to the checkout, with a comment that RP11 reads history back to `bootstrap-sha`.
  - The repository is small, so this costs seconds.
  - CI then runs exactly what G5 runs locally.
  - Add a workflows case (for example WF47: "Check's checkout has `fetch-depth: 0`") so the link cannot silently break again.
  - Budget-neutral alternative: in RP11, detect `git rev-parse --is-shallow-repository` and check only that the SHA is 40 hex characters, leaving ancestry to G5's local gate. This is weaker in CI.
- **Process lesson for the Tester and Implementer:** run the suite once in a CI-shaped checkout (a depth-1 clone with `CI=true GITHUB_ACTIONS=true`) before calling a CI feature green.

### Should fix

**S1. `docs/ci-cd.md:12-13` states the pre-R5 docs-only rule.**
- The doc says Check is skipped when only "`docs/`, `tasks/`, `design/` or `*.md` outside `Apps/`/`LedgerKit/`" change.
- Since R5, `pr.yml:43-48` treats only **root-level** `*.md` as docs. `scripts/NOTES.md` and `.github/README.md` run Check (WF46).
- This header is the record of verified deviations, so it must match the code.
- **Fix:** "…when only files under `docs/`, `tasks/` or `design/`, or `*.md` at the repository root, change (renames count at both paths)". The edit is to a new line, so it is budget-neutral.

**S2. The workflow lint can silently stop running: WF01 and the whole workflows suite report "skip", which passes.**
- **Where:** `scripts/tests/adversarial/workflows.adv.sh:28-35` (actionlint) and `:12-15` (no Ruby).
- **Evidence:** in a fresh clone without `CI=true`, mise did not resolve the pinned tool, and the result was `workflows.adv.sh: 48 passed, 0 failed, 1 skipped` with exit 0.
- `mise.toml` now pins actionlint and shellcheck, and `check.sh` step 0 installs them. A missing binary therefore means the gate is broken, not an optional tool.
- **Fix:** `fail` instead of `skip` for WF01, at least when `$CI` is set, and treat missing Ruby the same way. The change is test-only.

**S3. The nightly dependency report always lists every pin as a change.**
- **Where:** `.github/workflows/nightly.yml:71`.
- `swift package update --dry-run` on a fresh checkout has no workspace state. It therefore reports all 9 pinned dependencies (`+ grdb.swift 7.11.1`, …, the exact `Package.resolved` versions) as changes.
- The code-review pass ran it. That is consistent with SwiftPM diffing against the managed-dependency state, not against `Package.resolved`. I did not re-run it.
- **Fix:** resolve first, on the same line so it is budget-neutral: `swift package --package-path LedgerKit resolve && swift package --package-path LedgerKit update --dry-run | tee updates.txt`. Confirm on the first nightly.

### Nits

- **N1. The `check.sh:5-8` header is stale.**
  - It says `--skip-lint` exists because "CI runs lint in its own job". CI now runs the whole script.
  - The header does not say that `--skip-lint` also skips the script tests and the adversarial suite.
  - The line pre-exists on `main`, so editing it costs 2 budget lines. See §Line budget.
- **N2. `implementation-notes.md:3-5`** still says the round-2 fixes "are uncommitted". They are in `97fbab8`.
- **N3. `docs/ci-cd.md` has two inaccuracies.**
  - §8 (`:250`) says tokens are "`contents: read` except release-please", but the nightly `report` job has `issues: write`.
  - §9 (`:256-268`) still shows the paid-plan budget of $105/month. Put the free-tier estimate (§Cost below) in the header, where edits are free.
- **N4. Standards that now contradict Pete's decision.** These are outside F01's Touches, so they are follow-ups for the orchestrator:
  - `docs/engineering-standards.md:191` says "`main` is protected: no direct pushes, required CI checks, linear history";
  - `:224` says "CI green on the PR". It should read "CI green whenever it ran; else the local gate", per ci-cd.md §4.
  - `docs/testing-strategy.md:283,296` still name the `test-ios`/`pr-gate` jobs and the "higher value per target" rule. The implementation notes already list these as follow-ups.
- **N5. A hang uploads no result bundle.**
  - The upload step's `if: failure()` (`pr.yml:74`) probably does not fire when the **job-level** 30-minute timeout cancels the job. That is exactly when the bundle matters.
  - Give the `check.sh` step its own `timeout-minutes: 27`. A hang then fails the step, and the bundle uploads. The cost is +1 line.
- **N6.** Step 2 now runs the adversarial suite on every `check.sh`, about 30 s. On CI that is about 0.5 billed macOS minutes per run, or 3–4 %. This is acceptable. If minutes get tight, run the host-only suites in the Linux Scope job instead.
- **N7. Test harness duplication.**
  - `is()` is defined five times (workflows, check-wiring, ci-post-clone, coverage-gate and release-please suites). It belongs in `lib.sh`.
  - `coverage-gate.test.sh` and `coverage-gate.adv.sh` overlap on about 7 cases. Fold them together later.
- **N8. Minor script issues.**
  - `adversarial/run.sh:12` has `cd` without `|| exit`. It still fails closed: the glob finds nothing, and the literal fails.
  - `lib.sh` has no shellcheck `shell` directive (SC2148), and it is committed as 100755 although it is only sourced.
- **N9. The cache-seeding advice may cost more than it saves.**
  - ci-cd.md §4 says to dispatch `pr.yml` on `main` after each dependency bump to seed the SwiftPM cache.
  - That costs a full Check (about 13–18 macOS minutes) to save perhaps 1 minute on each PR's first run.
  - GitHub also evicts caches after 7 days without access.
  - Measure the saving on the first real runs before adopting it.
- **N10. There is a much cheaper way to verify criterion 10.**
  - A nightly dispatch starts three macOS jobs, which could take 40–60 minutes, about a quarter of the month.
  - Instead, dispatch on a throwaway branch whose `.xcode-version` names a missing Xcode.
  - Every macOS job then fails at *Select Xcode* within a minute, and `report` still opens the `nightly` issue.
- **N11.** The coverage gate keeps the larger measurement of a file wholesale (R-D5). It fails closed but can be over-strict with `#if os(...)` branches. This is known and deferred; the fix is a per-line union with `xccov --archive`.
- **N12.** SwiftFormat's `github-actions-log` reporter annotates as `::warning`, not `::error`. The step still exits 1, so the gate holds. Reviewers should expect format violations as yellow annotations.
- **N13.** `tasks/todo.md` does not yet show F01 progress, which the root `CLAUDE.md` asks for. This is for the orchestrator at merge.

## (a) Security

| Item | Status |
|---|---|
| `permissions` | **Minimal.** `pr.yml`: `contents: read` at workflow level, with no job overrides (WF06). `nightly.yml`: `{}` at workflow level; `test` and `dependencies` have `contents: read`, and `report` has only `issues: write` (WF27). `release-please.yml`: `{}` at workflow level; the job has `contents`, `pull-requests` and `issues: write`, the three the action's README requires (WF33). |
| `pull_request_target` | Absent. `pr.yml` uses `pull_request` and `workflow_dispatch` only. |
| Script injection | No `${{ … }}` inside any `run:`. Matrix values and URLs reach scripts through `env:` (nightly `PLAN`, `SCHEME`, `DESTINATION`, `WORKERS`, `RUN_URL`). File names in Scope go only through `case`, never `eval`, and git quotes unusual names, which then run Check. |
| Pinned actions | All five are pinned by full SHA with a version comment (WF13), and each matches its tag online. |
| Tokens and secrets | No secrets. release-please uses `GITHUB_TOKEN`. Its PRs and tags start no Actions workflows, which is the intended behaviour here. The Xcode Cloud GitHub App still receives the tag webhook. `mise-action` uses the read-only token only for download rate limits. |
| `ci_post_clone.sh` | It accepts only a whole-number `CI_BUILD_NUMBER`, closing the newline-injection hole (F8, PC07), and it writes through `$CI_PRIMARY_REPOSITORY_PATH`. |
| Gate files editable by the PR they gate (D2) | Accepted by design (no protection). Partly mitigated: the adversarial suite pins `pr.yml`'s structure, so weakening the workflow also means editing tests, which G3 sees. |

## (b) Gate correctness

- **The `check.sh` path is sound, apart from B1.**
  - It uses `set -euo pipefail`, and each `xcodebuild … | beautify` pipe propagates xcodebuild's code (W06: 65).
  - An injected failure at each of the 14 steps stops the run with no later step (W04).
  - The script tests run as bare commands in the loop, so `-e` stops at the first failure (W12, and my `|| true` mutant was caught).
  - Contradictory flags exit 2.
  - The bash 3.2 empty-array trap is fixed (W08).
  - `check-test-results.sh` refuses skipped, missing or failed plans.
  - The coverage gate fails on a required module that is missing, an unlisted measured module, a module with no threshold, or bad input (exit 2).
- **`pr.yml`:**
  - There is no `continue-on-error`.
  - Check's `if: needs.scope.outputs.code != 'false'` runs Check on a missing output (WF45).
  - A failed Scope skips Check, but the workflow run is then red, so it is not a silent pass.
  - The upload step's `if: failure()` cannot turn a failure green.
  - `shell: bash` is the default, which adds pipefail (WF16).
- **Scope:**
  - `--no-renames` counts a moved file at both paths (WF22, WF23).
  - Docs-only is an allowlist, and every other path runs Check (WF46).
  - A depth-1 checkout fails the step rather than skipping Check (WF26).
  - No build input reads `docs/`, `tasks/` or `design/`. I checked `Package.swift`, the pbxproj, the plans and the gate scripts; `design/` holds only `prototype/`.
- **A skipped Check reads as success.** That is inherent to the design. ci-cd.md §4 makes G5 accept a skip only when Scope logged `code=false`, and the `::notice::` is restored.
- **Skips that pass:** S2.

## (c) Cost

- **Code PR:** one macOS job, Check. Estimate: about 1–2 min setup and caches, about 1.5 min for steps 0–2 (including 0.5 for the suite), 7–10 min iOS cold on a 3-vCPU M1, 3–4 min watchOS, and under 0.5 min for the coverage gate. That is **about 13–18 billed macOS minutes**, rounded up per job, or roughly **11–15 code-PR runs a month** from 200 minutes.
  - The local cold run is 262 s on 10 cores.
  - The implementer's 12–15 estimate is plausible. The first run replaces both numbers.
  - PRs open only after test and review (subagent-workflow), so most PRs cost one run.
- **Docs-only PR:** Scope only, about 1 Linux minute, which is 1× and negligible. Check does not start.
- **Pushes to `main`:** release-please takes about 1 Linux minute per push. Xcode Cloud is billed separately.
- **Concurrency:** grouped per PR with `cancel-in-progress: true`. A superseded run's Scope and Check are cancelled together, and a cancel only ever hits an older SHA.
- **Caches:**
  - Only `.derivedData/SourcePackages` is cached, keyed on `.xcode-version` and both `Package.resolved` files (every file exists: WF12).
  - `restore-keys: spm-`; the save happens only on success.
  - Not caching DerivedData is the right call (llbuild keys on inode and mtime).
  - `mise-action` caches the tools under its own key.
- **Nightly:** manual only, so it costs 0 minutes until dispatched. See N10 before verifying criterion 10.

## (d) release-please

- **Config, manifest and marker agree.**
  - The manifest says 0.1.0.
  - The only marker is on `Config/Base.xcconfig:28` `MARKETING_VERSION = 0.1.0 // x-release-please-version`, and it is the only `extra-files` entry (RP02–RP07).
  - Tags are `v0.2.0`: `simple`, no component, `v` kept (RP08).
  - `bootstrap-sha` 8404d02 is the current `main`.
  - `version.txt` is not created (`createIfMissing: false`).
- **Commit types that cut a release:**
  - `feat` → minor while below 1.0;
  - `fix` and `perf` → patch;
  - any type with `!` or `BREAKING CHANGE` → minor below 1.0.
  - `ci`, `docs`, `chore`, `test`, `build`, `refactor` and `style` alone leave the changelog empty, so no release PR opens.
- **Merge method matters for this PR** (library-verified):
  - A **squash** with a `ci:` subject opens no release PR, with GitHub's default bullet body or with an empty body.
  - A **merge commit** would put the branch's `fix(ci):` commits on `main`, and release-please would open a **0.1.1** release PR.
  - All three merge methods are enabled today (README §1).
  - **G5 must use** `gh pr merge --squash --subject "ci: …"`.
  - A small correction to the notes: release-please reads the whole commit message, not only the subject. The default body is safe here.
- Criterion 8's release PR is the first real exercise of this. The repository setting *Allow GitHub Actions to create and approve pull requests* must be on first (README §1).

## (e) Scripts

- **Bash 3.2 compatible.**
  - No bash-4 constructs appear (`declare -A`, `mapfile`, `${x,,}`, `|&`, …).
  - The suites and `--lint-only` ran under `/bin/bash` 3.2.57.
  - `read -r -d '' GATE … || true` is the correct idiom for loading the embedded Python.
- **`set -euo pipefail` holes: none found** in `check.sh`, `coverage-gate.sh` or `coverage-gate.test.sh`.
  - The workflows default to `shell: bash`.
  - `ci_post_clone.sh` is POSIX `sh` with `set -eu` and no pipes.
- **Python:** the embedded Python works on Xcode's `python3` (3.9). Floors are exact at the boundaries, because integer ÷ integer in float is correctly rounded (95.00 passes, 94.99 fails, 94.995 fails).
- **shellcheck** is clean on the production scripts except the F00 SC2154 false positive.

## (f) Tests

- The suites assert behaviour, not text. Each one does real work:
  - the Scope step is extracted and run in about 25 throwaway git repos, including renames, reverts, force-pushes and base moves;
  - the real `check.sh` runs in a stub sandbox, and each step is failed in turn;
  - the real gate runs on crafted reports;
  - the real post-clone script runs from `ci_scripts/`, followed by `xcodebuild -showBuildSettings` (Release);
  - the nightly report runs against a fake `gh`.
- **My independent mutants were all caught:**

| Mutant | Caught by |
|---|---|
| Check `if:` becomes `== 'true'` (fails open) | WF45 |
| The upload runs on `success()` | WF10 |
| Scope treats any `*.md` as docs | WF35, WF38, WF40, WF46 |
| The nightly `report` runs on `always()` | WF28 |
| `pr.yml` gains `pull-requests: write` | WF06 |
| Post-clone accepts any build number | PC07 |
| The overall threshold is set to 0 | C05, C05b |
| The script-test loop gets `\|\| true` | W04, W12, W20 |

- **Gaps:** B1 (the suites never ran in a CI-shaped checkout) and S2 (skips pass).

## (g) Docs

- **`docs/ci-cd.md`:**
  - The "Verified 2026-09-27 (F01)" header records the runner facts, Pete's decisions and the §5/§6 deviations, but its docs-only wording is stale (S1).
  - §4 accurately states that there is no protection, the G5 policy, skipped-Check semantics and the minutes-exhausted fallback.
  - §8 and §9 have small inaccuracies (N3).
- **ADR-006:** the 2026-09-27 consequence note is accurate and points to §4.
- **`docs/xcode-cloud/README.md`:** the steps are concrete and in order, with exact setting names, screenshot file names and bundle IDs.
  - **§1:** the $0 budget, the *Allow GitHub Actions to create … pull requests* setting, and squash only plus auto-delete.
  - **§2:** App IDs with HealthKit, the app record, TestFlight groups and export compliance.
  - **§3:** connecting Xcode Cloud.
  - **§4 Beta:** Xcode 26.6 pinned, no clean build, `main` only, Archive with TestFlight (Internal Testing Only).
  - **§5 Release:** a clean build, tags starting with `v` plus Manual Start, and an explicit manual App Review.
  - **§6:** criteria 7 and 9, including "CI does not run on the release PR; run `check.sh`".
  - I found no errors. One suggestion: add to §1 that merging must use squash until the merge-commit setting is off (see §d).

## (h) Acceptance criteria → evidence

| # | Criterion | Evidence | Status |
|---|---|---|---|
| 1 | Check runs on `macos-26` with Xcode 26.6 in ≤ 30 min warm | Per Pete's decision, one `Check` job replaces `Lint` + `Check (iOS + watchOS)` (ci-cd.md header, notes decision 2). `pr.yml:58-63`: `macos-26`, Xcode from `.xcode-version` = 26.6, `timeout-minutes: 30`. The runner image facts are in the notes' Verification section. | **Blocked by B1**, then *pending: first GitHub run* (runtime) |
| 2 | A SwiftLint warning fails with a file:line annotation | `check.sh:72`: `--strict` plus `github-actions-logging` on Actions (W16–W18). My probe gave exit 2 and `::error file=…,line=4,col=14::Force unwrapping…`. | Met locally; *pending: probe PR* |
| 3 | A failing Swift Testing test fails the job, and the bundle is uploaded | Pipefail and `check-test-results.sh` (W04, W06). `pr.yml:73-83`: upload `if: failure()` of `.derivedData/Results` with `include-hidden-files` (WF10). | Wired; *pending: probe PR* |
| 4 | Domain at 94 % fails with the ✗ row in the step summary | `coverage-gate.test.sh` case 3: exit 1, and the ✗ row is written to `$GITHUB_STEP_SUMMARY`. C15/C15b. | **Met (fixture)**; rendering *pending: first GitHub run* |
| 5 | A changed snapshot's diffs appear under `results-*`, and the test fails | The upload includes `.derivedData/SnapshotArtifacts` as `results-<run>-<attempt>`. The notes verify that `$(PROJECT_DIR)` expands. No snapshot test exists yet (F06), and D7 (`SNAPSHOT_TESTING_RECORD` reaching the simulator) is open. | *Pending: F06 plus a probe PR* |
| 6 | A direct push to `main` is rejected | Waived by Pete's decision (no protection). ci-cd.md §4 and ADR-006. | **Waived** |
| 7 | The Beta build has `CURRENT_PROJECT_VERSION == CI_BUILD_NUMBER` | `ci_post_clone.sh`. PC01–PC12: `xcodebuild -showBuildSettings` (Release) resolves 4242 for Ledger and LedgerWatch, and no other file sets the value. | *Pending: Pete (manual)*, README §6 |
| 8 | feat + fix + chore opens a release PR from 0.1.0 to 0.2.0, listing only feat and fix | Config and marker (RP01–RP13). The library confirms 0.2.0 with 2 visible entries and the `MARKETING_VERSION` rewrite. | Verified offline; *pending: first GitHub run* (needs the Actions PR setting) |
| 9 | Tag `v0.2.0` starts Xcode Cloud "Release" | The tag format is `vX.Y.Z` (RP08). README §5 and §6 give the steps and the Manual Start fallback. | *Pending: Pete (manual)* |
| 10 | A nightly failure opens an issue labelled `nightly` that links the run | `nightly.yml:74-95`. WF27–WF31 with a fake `gh`: a first failure opens one issue, and a later one comments on it. | Wired; *pending: first GitHub run* (N10) |

**Test plan and DoD:**
- The fixture test is done: `coverage-gate.test.sh`, run by step 2.
- The probe PRs are pending. The notes propose batching them into one throwaway PR, which fits the budget.
- Screenshots are pending (Pete).
- The ci-cd.md "verified" header is done (fix S1).

**Non-functional:**
- Security is met.
- Cost is within the free tier (§c).
- The `paths:` filter was replaced by the rename-safe Scope job. Docs-only PRs get no macOS job, by Pete's decision, instead of the brief's "Lint only".

## Line budget (engineering-standards §10: ≤ 500 changed lines excluding tests)

| Scope | Changed lines (added + deleted) |
|---|---|
| Everything | 2,365 |
| Excluding `scripts/tests/**` | 1,147 |
| **Excluding `scripts/tests/**` and the `tasks/` delivery artefacts** (implementation notes and test findings, which the workflow mandates for every feature) | **497 (474 + 23): within the limit** |

The budget is tight:
- The B1 fix adds 2 lines, giving 499.
- The S1 and S3 fixes are edits to new lines, so they are free.
- The S2 fix is test-only.
- N1 and N5 would push the total past 500. Take them only by trimming elsewhere (for example the three-line header comment in `pr.yml`), or defer them.

## Merge notes (G5)

- **G5 must stop for Pete** before merging. The PR edits ADR-006 and touches releases (release-please), TestFlight and App Store delivery (Xcode Cloud) and signing-adjacent build numbers. docs/subagent-workflow.md's G5 row requires Pete's review in those cases.
- **Merge with** `gh pr merge --squash --subject "ci: …"`. A merge commit would open a 0.1.1 release PR (§d).
- **After merge:**
  1. Pete's checklist, README §1 first.
  2. The first `pr.yml` run gives criterion 1's numbers.
  3. The batched probe PR covers criteria 2–4.
  4. Criterion 10, the cheap way (N10).
