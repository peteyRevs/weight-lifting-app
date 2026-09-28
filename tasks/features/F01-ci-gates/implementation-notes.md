# F01 implementation notes

Base: `main` 8404d02. First pass committed as 0c74369. This round addresses the fix
findings in `test-findings.md` and Pete's decisions of 2026-09-27; it is uncommitted.
No GitHub or App Store Connect setting was changed.

## Decisions

1. **`check.sh` is the only definition of the gate.** CI runs it unmodified. It lies
   outside Touches but changed:
   - On Actions it passes the SwiftLint (`github-actions-logging`) and SwiftFormat
     (`github-actions-log`) reporters. Neither tool detects Actions itself (verified).
     This gives criterion 2's file:line annotations.
   - Step 2 runs `scripts/tests/*.test.sh`. That glob now includes the tester's suite, through
     `scripts/tests/adversarial.test.sh` (159 cases, about 22 s, host-only).
   - Step 5 always calls the coverage gate.
   - Contradictory flags exit 2 (F7). The summary survives bash 3.2 (F6).
2. **Pete: free Actions minutes, spending limit $0.**
   - `pr.yml` has one macOS job, `Check`, which runs the whole `check.sh` (lint, iOS, watchOS,
     coverage) in one VM, with a 30-minute timeout.
   - A Linux `Scope` job runs first and skips `Check` for docs-only PRs, so those start no Mac.
     It lists changed files with `--no-renames`, so a moved file counts at both paths (F1).
     `*.md` files under `Apps/` or `LedgerKit/` count as code (D4).
   - A new push cancels the superseded run.
   - The nightly is manual (`workflow_dispatch`), with `concurrency` (D9).
   - release-please runs on Linux. The dispatch of `pr.yml` onto its release PR is removed:
     it would cost about 13 macOS minutes on every push to `main`. The person merging a
     release PR runs `check.sh` on it first; the only code change there is `MARKETING_VERSION`.
3. **Pete: no branch protection.** Enforcement is the orchestrator's merge policy: a green local
   `check.sh` on the merge candidate, plus CI whenever CI ran. When the minutes run out, CI does
   not run and the local gate output is the G4 evidence.
   - This is recorded in ci-cd.md §4 and ADR-006's Consequences.
   - The checklist no longer has protection steps. It keeps *Allow GitHub Actions to create
     and approve pull requests*, which release-please needs.
   - Criterion 6 is waived by this decision.
4. **Coverage gate** (`scripts/coverage-gate.sh`, thresholds in `scripts/coverage-thresholds.json`):
   - A module is its folder `LedgerKit/Sources/<Module>/`, because coverage is plan-wide (F00 #17).
   - Percentages are floored, never rounded up.
   - Excluded: `LedgerTestSupport`, `LedgerSnapshotTesting`, the umbrella modules `LedgerAppKit`
     and `LedgerWatchAppKit`, `*+Previews.swift` and `*/Generated/*`.
   - A file measured twice keeps the measurement with the most executable lines, then the most
     covered (F2). One platform's lines therefore never hide the other's.
   - **`required`** lists every module that has code (today: `LedgerDomain`).
     - A required module missing from the report fails (F3).
     - A measured module that is not listed fails with "add it to required". The list therefore
       cannot go stale. When F06 or F05 add code, they add one line.
   - A malformed thresholds file or report exits 2 (F5). So does a module that is both gated
     and excluded (D5).
   - `LedgerDependencies` has no threshold on purpose. F07 decides it (D6).
5. **Caching and artifacts.**
   - Only `.derivedData/SourcePackages` is cached.
   - DerivedData is not cached. llbuild compares inode and mtime, so a restored tree rebuilds
     anyway, and it is several GB.
   - Result bundles (about 79 MB each) upload only on failure. `include-hidden-files` is set.
6. **Everything else.**
   - Least privilege: `pr.yml` has `contents: read`, and nightly defaults to `{}`.
   - Actions are pinned by SHA.
   - Every workflow with `run:` steps defaults to `shell: bash`, which adds pipefail (F4).
   - The nightly opens or updates a single `nightly` issue.
   - release-please's config sets `bootstrap-sha` = 8404d02.
   - `ci_post_clone.sh` writes to `$CI_PRIMARY_REPOSITORY_PATH`, because scripts run from
     `ci_scripts/`. It accepts only a whole-number build number (F8).

## Where I changed the tester's tests, and why

Each change follows Pete's decision or a design the tests could not express. None weakens
the property under test.
- **Workflows suite:**
  - WF04, WF05, WF07, WF08 and WF17, and the `scope` extraction, now describe the
    single-job structure, `Scope → Check`.
  - WF33 and WF34 now assert that release-please runs on Linux with no dispatch and no
    `actions: write`.
  - WF11 now tolerates a workflow with no cache step. The nightly lost its cache as
    budget trimming.
  - New cases: WF35 (D4: `*.md` under `LedgerKit/` runs Check) and WF36 (the nightly is
    manual, one run at a time).
- **Coverage suite:**
  - The shared thresholds gain `"required": ["LedgerDomain"]`, and C09b uses a derived
    file that also requires FeatureToday.
  - C14 as written needed the gate to guess from source files that LedgerDomain has code
    but LedgerDesign does not. That would be a heuristic. An explicit list that ratchets
    is deterministic, and its shrinking shows in the diff (D2). C14b checks that the error
    names LedgerDomain.

## Design questions

- D1 is answered by Pete: no protection (decision 3).
- D2: any gate file can be edited by the PR it gates. Recommendation: the G3 reviewer prompt
  asks "did the PR touch `scripts/`, `TestPlans/`, `.github/`, `ci_scripts/` or
  `coverage-thresholds.json`?". CODEOWNERS binds nothing without protection.
- D3: not added. G5 sets the squash subject explicitly (`gh pr merge --subject`), and that
  subject, not the PR title, is what release-please reads.
- D4, D5 and D9 are fixed. D6 is F07's. D8 is by design: paths resolve from the repo root,
  like `check.sh`.
- D7 (`SNAPSHOT_TESTING_RECORD` may not reach simulator tests) is F00/F06 code. It is
  unverified until the first snapshot test exists.

## Verification

- **Runner image** (`macos-26` = arm64, 20260907): Xcode 26.6 (17F113) is the default at
  `/Applications/Xcode_26.6.app`. iPhone 17 and Series 11 (46mm) run on 26.5. jq, gh and ruby
  are present.
- **Tests:**
  - `scripts/tests/adversarial/run.sh`: all 6 suites pass. `coverage-gate.test.sh`: 10 cases.
  - Mutations are caught: dropping `--no-renames` fails WF22 and WF23. The earlier ones still
    hold: worst measurement wins, and an off-by-one threshold.
- **Lint:** actionlint 1.7.12 with shellcheck 0.11.0 reports 0 errors, and shellcheck is clean
  on the new scripts.
- **Coverage:** LedgerDomain is at 1381/1398 = **98.78 %**, identical on iOS and watchOS, and
  overall is the same. No other module has executable lines yet.
- **Criterion 2:** a planted force unwrap gives `::error file=…/CIProbe.swift,line=3,col=14::…`.
- **Criterion 8:** checked offline with the release-please 17.11.2 library. feat + fix + chore
  go from 0.1.0 to 0.2.0, and only Features and Fixes appear in the changelog.
- **Post-clone:** with `CI_BUILD_NUMBER=42`, both apps resolve `CURRENT_PROJECT_VERSION = 42`.
  `abc`, `1.2.3.4` and a value with an embedded newline are refused, and the file is untouched.
- **Full `check.sh`** through the simulator lock, from a cold DerivedData, on the final tree:
  **green in 262 s**.
  - Step 2 took 21 s, with all adversarial suites and 10 fixture cases passing.
  - iOS took 169 s: 17 targets ran and passed.
  - watchOS took 71 s: 8 targets ran and passed.
  - Coverage was 98.78 %.
- **Estimated macOS minutes per PR run: about 12–15**, billed per job and rounded up.
  - Basis: the cold local run above (262 s). The runner is 3-core M1, against 10 cores here, so
    compiling should take about 2.5–3× longer.
  - Breakdown: setup and restore about 2 min, steps 0–2 about 1 min, iOS 6–8 min,
    watchOS about 3 min.
  - About 200 free minutes cover roughly 13–16 code PR runs a month. Docs-only PRs cost
    only about a Linux minute.
  - The first real run replaces this estimate.

## Pending (not verifiable locally)

- **Criteria 1–5 and 10** need GitHub. The first `pr.yml` run on the F01 PR covers
  criterion 1 and the cache logs. Criterion 1 now means one `Check` job.
- **Probe PRs:** the minutes budget argues for batching them into one throwaway PR with
  separate commits, pushed one at a time:
  - lint: a force unwrap;
  - test: a failing `#expect` in LedgerDomainTests;
  - coverage: the LedgerDomain threshold set to 99;
  - snapshot: after F06 lands.
- **Criterion 10:** `gh workflow run nightly.yml --ref <branch with a failing test>`, once
  F01 is on `main`.
- **Criteria 7 and 9 are manual** (Pete), in `docs/xcode-cloud/README.md` §6.
- **Squash-merge F01 with a `ci:` subject.** A `feat` subject would make release-please open
  a 0.2.0 release PR.
- **Follow-ups not done:**
  - SwiftLint analyzer (F00 #9);
  - Dependabot for the SHA pins;
  - Xcode 26 compilation caching (`COMPILATION_CACHE_ENABLE_CACHING`), to be measured once
    real run times exist;
  - testing-strategy §4 wording: the job names, `required`, and LedgerSnapshotTesting.
- **`check.sh:47`** has a shellcheck SC2154 false positive from F00, left untouched.
