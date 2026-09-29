# F01 implementation notes

Base: `main` 8404d02. Commits so far: 0c74369 (first pass), 19d4050 (F1–F8 and Pete's
decisions), cd2aae2 (tester round 2), 97fbab8 (R3–R5, R-D1–R-D5), 268f58e (the review
fixes: B1, S1–S3 and the cheap nits) and 60cb474 (the first-CI-run fix). The second-CI-run fix is
uncommitted. No GitHub or App Store Connect setting was changed.

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

## Round 2 (R3–R5 fixed; R-D1–R-D5 answered)

**Fixes:**
- **R3.** The gate rejects an excluded module that matches any threshold key, by name or
  by pattern (`fnmatchcase`). It exits 2.
- **R4.** `excludedModules`, `excludedFiles` and `required` must each be a list of strings,
  or the gate exits 2.
- **R5.** Docs-only is now an explicit allowlist: files under `docs/`, `tasks/` or
  `design/`, and `*.md` at the repo root. Every other path, Markdown included, runs Check.
  This covers `Resources/Fonts/` and every other synced folder, so `.github/*.md` runs
  Check too. That is conservative, and cheap. New case WF46: a nested `.md` elsewhere runs
  Check. Dropping the `*/*` line is caught by WF35, WF38, WF40 and WF46.

**The RP06 class cannot recur here:**
- RP06 now scans tracked and untracked files (the tester's fix). A scan therefore gives
  the same result before and after a commit.
- The only other git-state checks read file modes (`ls-files -s`: PC09, W20–W22). An
  untracked file makes them fail, so they fail before the commit, never after it.
- This round adds no new file. The gate run below therefore saw exactly the content that
  will be committed.
- Lesson for the implementer: run the final gate with every new file present in the form
  it will be committed, and prefer scans that ignore git state.
- **Full gate, round 2**, through the simulator lock: **green in 273 s**.
  - Step 2 passed: 195 adversarial cases (WF01 actionlint now among them) and 10 fixture cases.
  - PR ran 17 targets and PR-Watch 8. The coverage gate passed at 98.78 %.

**Design questions:**
- **R-D1: adopted.** Check's condition is `needs.scope.outputs.code != 'false'`, so a
  missing output runs Check (WF45 updated). actionlint 1.7.12 and shellcheck 0.11.0 are now
  pinned in `mise.toml`. The step-0 `mise install` installs them, so WF01 runs in the gate,
  including in CI.
- **R-D2: adopted.** The Scope step prints
  `::notice::Docs-only change: Check is skipped.` ci-cd.md §4 says a skipped Check counts
  only when Scope logged `code=false`.
- **R-D3: adopted as procedure.** Seeding needs no extra workflow or trigger. After a
  dependency bump, `gh workflow run pr.yml` on `main` once seeds the package cache
  (ci-cd.md §4).
- **R-D4: agreed, deliberate.** Only G5's local `check.sh` covers the release PR.
- **R-D5: agreed, not fixed.** The fix fails closed, so it can be too strict but never too
  lenient.
  - It bites only when a platform-only branch runs in no test. Running that module's tests
    on both platforms also covers it.
  - The exact fix is a per-line union (`xcrun xccov view --archive --file`) for the files the
    bundles disagree on. Proposed for when it first happens; it would not fit the line budget
    now.

## Review fixes (`review.md`: B1, S1–S3, nits)

- **B1.** The Check job was checked out at depth 1, but RP11 needs history, so `check.sh`
  step 2 would fail every PR.
  - `pr.yml` Check now checks out with `fetch-depth: 0`. The repository is small, so this
    costs seconds.
  - **WF47** fails when any job that runs `check.sh` checks out shallow. Removing the line
    fails WF47.
  - In a shallow repo, RP11 now names its cause: "shallow checkout: check.sh needs full
    history".
  - *Proof, in a scratch clone* (`git clone --depth 1 file://…` of 97fbab8, plus this
    round's changes, with `CI=true GITHUB_ACTIONS=true`; the clone is deleted):
    - At depth 1, `check.sh --lint-only` exits 1. The only failure is RP11, with that message.
    - After `git fetch --unshallow`, which is what `fetch-depth: 0` gives, it exits 0.
      All suites pass, including WF01's actionlint, and 0 bytes reach the step summary.
  - With `CI=true`, mise trusts `mise.toml` without asking, so the pinned tools resolve on
    the runner. Without CI, a fresh clone needs `mise trust`, as before.
  - The Scope job keeps depth 2 because it reads only the merge and its base. The nightly
    runs no history-dependent check.
- **S1.** The ci-cd.md header states the R5 allowlist: files under `docs/`, `tasks/` or
  `design/`, or `*.md` at the repository root.
- **S2.**
  - WF01 now **fails** when actionlint or shellcheck is missing, instead of skipping. It
    finds them with `mise which` from `mise.toml`, so a pin bump needs no test edit.
  - A missing Ruby fails the workflows suite too.
  - A mutant that hides the tools fails WF01.
- **S3.** The nightly runs `swift package resolve` before `update --dry-run`. Measured:
  - on a fresh workspace, the dry-run alone lists all 9 pins as changes;
  - resolved first, it reports "0 dependencies would change".

**Nits fixed:**
- **N1:** `check.sh`'s header describes `--skip-lint` correctly.
- **N2:** these notes.
- **N3:**
  - §8's token row now names the nightly report's `issues: write`.
  - The header now carries the free-tier cost (about 13–18 minutes per code PR; §9 is superseded).
- **N5:** the `check.sh` step has `timeout-minutes: 27`, so a hang fails the step and the
  bundles still upload before the 30-minute job timeout.
- **N7 (part):** one `is()` in `lib.sh` instead of five copies.
- **N8:** `run.sh` does `cd … || exit 1`. `lib.sh` has a shellcheck `shell` directive, a
  justified SC2034, and mode 100644.
- **N9:** ci-cd.md §4 now says to seed the cache only if the first runs show slow resolution.
- **Review §d:** the checklist says to squash only, and why.

**Nits deferred, with reasons:**
- **N4** touches files outside F01's Touches: engineering-standards §10/§12 and
  testing-strategy §4. They should state Pete's no-protection decision and the gate's real
  rules. This is for the orchestrator.
- **N6** (the suite adds about 0.5 billed minutes per run) is accepted. If minutes get
  tight, move the host-only suites into the Linux Scope job.
- **N7 (rest):** folding `coverage-gate.test.sh` into `coverage-gate.adv.sh` changes no
  behaviour. It is left for a test-only cleanup.
- **N10** is adopted as the plan for criterion 10 (see Pending).
- **N11** is R-D5, deferred as explained above.
- **N12** is informational: SwiftFormat's reporter emits `::warning`, and the step still
  exits 1.
- **N13** is for the orchestrator at merge.

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
- **macOS minutes per PR run: the estimate was about 12–15; the first run
  (36373847443) measured more**, billed per job and rounded up.
  - The estimate's basis was the cold local run above (262 s), with compiling 2.5–3× slower
    on the runner (3-core M1, against 10 cores here).
  - Measured: the run took 20m29s, and its Check job took 20m08s (21 billed minutes). It stopped
    at step 4, so watchOS and coverage are not in that figure.
    - Setup: 17 s. Steps 0–2: 87 s.
    - The iOS step took **1083 s (about 18 min)**: about 3 min of build, then **858 s of
      testing** (IDETestOperationsObserverDebug), against about 1.5 min locally.
  - So a green code PR costs at least 21 billed minutes plus the watchOS step. About 200
    free minutes then cover at most 9 code PR runs a month, not 13–16. Docs-only PRs still cost
    only about a Linux minute.
  - The build scaled as estimated; the test phase did not. See "First CI run", open question.

## First CI run (PR #5, run 36373847443)

**Failure.** Check passed steps 0–3, then failed 5 s into step 4 (watchOS) with exit 70
(`gh run view 36373847443 --log-failed`, abridged):

```
xcodebuild: error: Unable to find a device matching the provided destination specifier:
		{ platform:watchOS Simulator, OS:26.5, name:Apple Watch Series 11 (46mm) }
	The requested device could not be found because multiple devices matched the request. (
    SimDevice: Apple Watch Series 11 (46mm) (07C1BE1A-…, watchOS 26.5, Shutdown)
    SimDevice: iPhone 17 Pro Max (841190F6-…, iOS 26.5, Shutdown)
        PairedSim: … Apple Watch Series 11 (46mm) (07C1BE1A-…, watchOS 26.5, Shutdown)
    SimDevice: iPhone 17 Pro Max (BA9128D4-…, iOS 26.2, Shutdown)
        PairedSim: … Apple Watch Series 11 (46mm) (68A3C4E4-…, watchOS 26.2, Shutdown)
check.sh FAILED (exit 70)
```

**Root cause.**
- The runner image has an Apple Watch Series 11 (46mm) on watchOS 26.2, 26.4 and 26.5. It pairs
  the 26.5 one and the 26.2 one, each with an iPhone 17 Pro Max.
- For a destination by name, xcodebuild also matches each iPhone whose paired watch has that
  name, and for those it ignores `OS`. `OS=26.5` therefore excluded the 26.2 watch, but not the
  26.2 iPhone paired with it. Two different watches matched, so xcodebuild refused (exit 70).
- The iOS step's "Using the first of multiple matching destinations" warning is harmless: it
  names one UDID twice (arm64 and x86_64).
- Measured locally, under the simulator lock (Xcode 26.6; this Mac has only the 26.5 runtimes):
  - With one pair (the 26.5 Series 11 (46mm) and an iPhone 17 Pro Max), the old destination by
    name still works: `test` exits 0 (131 s) and `build-for-testing` exits 0 (11 s). A watch and
    the iPhone paired with it count as one device. On the runner, the second (26.2) pair made it
    two.
  - `OS` is ignored for paired iPhones: `name=Apple Watch Series 11 (46mm),OS=26.2` (no such
    runtime here) exits 70 with "no available devices matched" when unpaired, and builds (exit 0)
    once the 26.5 watch is paired.
  - Two different same-named watches give the runner's exact error (exit 70). Here the second
    one has to be a 26.5 twin (created, then deleted), which is ambiguous even unpaired. The
    runner's exact shape (a twin on another runtime, reached only through its pair) needs a second
    watchOS runtime, which was not installed for this.

**Fix.**
- `scripts/sim-destination.sh` turns `platform=…,name=…,OS=…` into `platform=…,id=<UDID>`. It
  reads `simctl list devices available --json` and matches the runtime exactly. An `id=`
  destination passes as is. No match exits 1 with nothing on stdout, so no xcodebuild runs.
- It then unpairs every pair that holds that UDID. simctl's output goes to stderr.
- `check.sh` resolves both destinations after the `--lint-only` and `--fast` exits, so only full
  runs look anything up. The nightly's test step resolves its matrix destination the same way.
- The UDID is the fix. `id=` resolves under the same conditions: with the target watch and a
  same-named twin both paired, `build-for-testing` by id exits 0.
- Unpairing is defence in depth, kept on purpose:
  - Pairing changes how xcodebuild matches destinations (it drops `OS`, above), and that
    behaviour is undocumented. With the device unpaired, the paired-device path cannot match it,
    whatever Xcode does.
  - No observed failure needs it: locally, `test` by id passed with the pair present.
  - The cost is one `simctl list pairs` per destination. A developer who pairs simulators loses
    only the pairs that hold the gate's two devices.

**Tests.**
- `sim-destination.adv.sh` (new, 20 cases) runs the real script against a fake `xcrun`
  (`lib.sh` `fake_simctl`), which lists `scripts/tests/fixtures/simctl/macos-26.json`.
  - The fixture has the runner's simulators and the two Series 11 (46mm) pairs from the log.
  - It adds an iPhone 17 + Ultra 3 pair. That pair was assumed, because the log does not say
    whether iPhone 17 is paired; it is now confirmed (see "Second CI run"). It also adds an
    unavailable iPhone 17 twin.
  - SD01–SD06: the defaults and overrides resolve, by name and OS or by id, in any key order.
  - SD07–SD08: no match, or a failing simctl, fails closed.
  - SD09–SD15: exactly the resolved device's pairs are unpaired, and a failing `simctl` fails.
- `check-wiring.adv.sh`:
  - W23: xcodebuild gets both defaults by UDID.
  - W24: both are unpaired first.
  - W25: `LEDGER_*_DEST` overrides reach xcodebuild as UDIDs.
  - W26: a destination with no match stops check.sh before any xcodebuild.
  - W27: `--lint-only` and `--fast` look nothing up.
- `workflows.adv.sh` WF48: the nightly's test step, extracted and run for each matrix entry,
  passes each simulator by UDID.

**Verification.**
- a. Every `scripts/tests/*.test.sh` passes. `adversarial.test.sh` ran 222 cases in 7 suites
  (check-test-results 18, check-wiring 43, ci-post-clone 14, coverage-gate 60, release-please 16,
  sim-destination 20, workflows 51). `coverage-gate.test.sh` ran 10 cases.
- b. The new tests fail against the old code:
  - HEAD's `check.sh` (`ADV_CHECK_SH`): W23–W26 fail. W27 passes, because HEAD looks nothing up
    in any mode. A second mutant, which resolves before the `--lint-only`/`--fast` exits, fails
    W27 (6 lookups instead of 0).
  - `sim-destination.sh` without the unpair loop (`ADV_SIM_DESTINATION`): SD09, SD11, SD12 and
    SD13 fail, and so do SD15 (`unpair` failing) and W24.
  - HEAD's `nightly.yml`, swapped in for one run and then restored: WF48 fails.
- c. The runner, reproduced locally. The simulator lock was held from pairing to cleanup, so no
  other worktree saw the pair.
  - Before: no pairs. The 26.5 Series 11 (46mm) was paired with the 26.5 iPhone 17 Pro Max.
  - With that one pair, the old destination by name did **not** fail (see Root cause). Exit 70
    came only when two different watches matched.
  - The full `check.sh`, with the pair present, was **green in 208 s** (warm DerivedData).
    - Step times: tools 0 s, format 0 s, lint and script tests 29 s, iOS 103 s, watchOS 74 s,
      coverage 2 s.
    - Step 2 ran 222 adversarial cases and 10 fixture cases.
    - Before step 3 it printed `sim-destination: unpairing 42705AE5-…`. Afterwards,
      `simctl list pairs` was empty.
    - PR: 17 targets, 431 tests passed, on iPhone 17 (26.5, by UDID).
    - PR-Watch: 8 targets, 422 tests passed, on the Series 11 (46mm) (26.5, by UDID).
    - Coverage: LedgerDomain at 98.78 %.
  - The two 26.5 Series 11 (46mm) twins created for the probes were deleted. No pair remains.
  - **Environment (this Mac, not the repo).** The Command Line Tools updated to 27.0 at 16:20 on
    2026-09-28.
    - `sim-lock.py` runs under `/usr/bin/python3`, an xcrun shim, which exports
      `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`. That is now the macOS 27 SDK
      (Swift 6.4), and Xcode 26.6's Swift 6.3.3 cannot read it.
    - So every gate started through `sim-lock.py` fails in step 2, at `check-package-graph.sh`.
      The first two attempts failed there.
    - The green run used `sim-lock.py env -u SDKROOT …`. A terminal and CI set no `SDKROOT`.

**Open question: why testing took 858 s on the runner. Closed** by "Second CI run (36489285602)
and the slow test phase" below. The app-hosted LedgerTests and the UI test waited 517 s and 384 s to
launch, because their parallel-testing clones of a never-booted iPhone 17 were still on their first
boot. The notes as written before the second run:
- The PR plan ran 17 targets on clones of iPhone 17: 15 logic-test processes, the app-hosted
  SmokeTests, and the UI test (22.8 s) on a second clone.
- LedgerDomainTests, which holds the 200-seed property tests, ran as one process.
  - Its tests reported durations of up to 181.9 s, trivial ones included
    (`SettingsTests.default_matchesPrototype`).
  - Swift Testing runs them in parallel and times each from start to finish. So the process
    probably lasted about 3 min, its tests queued for the runner's 3 cores.
- The other 14 logic targets ran one or two tests each, none over 50 ms.
- No test duration accounts for about 11 minutes (858 − 182 − 23 ≈ 650 s). That time went on
  launching test processes, the app and clones, or on waiting between them.
  - The log gives no per-target times: xcodebuild's output reached it in two bursts.
  - Every logic target's results were in the first burst, at 03:37:36, about 4 min into
    testing (which started about 03:33:23).
  - SmokeTests' and the UI test's results were in the second, at 03:48:13. If the bursts
    track completion, most of the gap is in those two app-hosted targets.
- Candidates, none tested:
  - the launch cost per target on a 3-core runner;
  - the parallel-testing clones;
  - iPhone 17 being paired on the runner (the log does not say; the fix now unpairs it).
- If the next run is as slow, the result bundle's per-target timings split the time. It uploads
  only on failure.

## Second CI run (36489285602) and the slow test phase

**Failure.** Check timed out after 27 minutes, in step 3 (iOS). Steps 0–2 took 99 s and the iOS build
167 s. Testing then ran until the step's timeout killed check.sh, 10 s into the UI test. It did not
kill xcodebuild: the post-job cleanup reports "Terminate orphan process: pid (51394) (xcodebuild)". The
uploaded `PR-iOS.xcresult` has no `Info.plist`, so xcresulttool cannot read it. The diagnosis rebuilt
per-test times from file modification times.

**Diagnosis** (a separate agent, high confidence, reproduced locally). The evidence is in the session
scratchpad, `ci-diag/`: `v-*/timeline.txt` per variant, `variant.sh`, `variant-watch.sh`, `hog.sh`
and `run1-action.json`.
- The time does not go on the build (167 s on the runner), on per-target launches, on coverage
  (about 4 s), or on a hang.
- Parallel testing clones the runner's never-booted iPhone 17 twice. Each clone must finish a first
  boot (data migration, then SpringBoard) before an app can launch in it.
  - Logic tests do not wait for that.
  - The app-hosted `LedgerTests` and the UI-test runner do.
- Launch waits of the two app-hosted targets, from the bundles' session logs:

  | Run | LedgerTests launch | LedgerUITests runner launch |
  |---|--:|--:|
  | Run 1, runner (parallel, clones) | 517.5 s | 383.8 s, after a 75.7 s install |
  | v8: fresh device, 8 CPU hogs, parallel (the CI shape) | 376.1 s | 142.5 s |
  | v1: fresh device, parallel | 96.6 s | 78.1 s |
  | v9: fresh device, 8 CPU hogs, pre-booted, serial | 0.5 s | 0.2 s |

  - Run 1: those two launches took 517 s and 384 s of its 858 s of testing.
  - Run 2: LedgerTests waited about 15.5 min, and the step then timed out 10 s into the UI test.
- Local variants: `test-without-building` of the PR plan on an iPhone 17 (26.5), in seconds. "Fresh"
  means created and never booted, as on a runner. "Hogs" means 8 busy loops (`hog.sh 8`), which stand
  in for the 3-core runner.

  | Variant | Device | Parallel testing | `bootstatus -b` first | Boot | Test | Total |
  |---|---|---|---|--:|--:|--:|
  | v0 | existing | on | no | – | 139 | 139 |
  | v1 | fresh | on | no | – | 202 | 202 |
  | v12 | fresh | on, 1 worker | no | – | 126 | 126 |
  | v10 | fresh | off | no | – | 85 | 85 |
  | v2 | fresh | off | yes | 34 | 72 | 106 |
  | v11 | existing | off | yes | 7 | 48 | 55 |
  | **v8**, hogs (the CI shape) | fresh | on | no | – | **458** | **458** |
  | **v9**, hogs | fresh | off | yes | 109 | 93 | **202** |

- watchOS (PR-Watch, fresh Series 11 (46mm)):
  - w1, the CI shape (parallel, 1 worker): 60 s.
  - w2, pre-booted and serial: 56 s (boot 20 s + test 36 s).
- With parallel testing off, Swift Testing also runs serially, in process. In the simulator that is
  faster: the Domain tests took 12–16 s instead of 52 s. `-only-testing:LedgerDomainTests` took 27 s
  (serial, no coverage) and 19 s (serial, coverage), against 71 s (parallel, coverage).
- **The runner pairs iPhone 17 with an Apple Watch Ultra 3 (49mm), now confirmed.** Run 1's session
  logs show `Clone 1 of iPhone 17 (…, iOS 26.5)` with `PairedSim: Clone 1 of Apple Watch Ultra 3
  (49mm) (…, watchOS 26.5)`.
  - The fixture's pair and the comments in `lib.sh` and `sim-destination.adv.sh` now say confirmed.
    The pair ids stay fake.
  - `sim-destination.sh` already unpairs it.

**The change: the diagnosis's option 1.** It is in `check.sh`, so the local gate and CI run one code
path, and the nightly's test step does the same.
- **`scripts/sim-boot.sh`** (new, 37 lines).
  - `sim-boot.sh <destination>` starts `xcrun simctl boot` on the destination's `id=` and returns at
    once.
    - A simulator that is already booted or booting is silent. The real simctl answers "Unable to
      boot device in current state: Booted" with exit 149 (verified).
    - Any other error is printed and left to `--wait`, because `bootstatus -b` boots the simulator
      too and an erase may cure it.
  - `sim-boot.sh --wait <destination>` runs `xcrun simctl bootstatus <udid> -b` with a timeout,
    `LEDGER_BOOT_TIMEOUT` (default 240 s).
    - On a failure or a timeout it runs `shutdown` (a failure is tolerated), `erase`, and one more
      `bootstatus -b`.
    - A second failure exits 1 with "error: simulator <udid> did not boot within 240s, even after
      an erase". check.sh stops there, before any test run.
    - On each failure, the last 4 lines of bootstatus's output go to stderr: the boot state it
      reached. Otherwise that output stays out of the log (372 lines for v9's first boot).
  - **The timeout** is perl's `alarm`, which survives `exec`. macOS has no coreutils `timeout`, and
    perl ships with macOS and the runner.
    - A bash polling loop would add up to 1 s to each of the roughly 70 waits in the adversarial
      suite.
    - A background killer either leaves an orphaned `sleep` or can kill a reused PID.
  - **Why 240 s:**
    - The runner's first boot takes about 1–2 min (the diagnosis). The slowest local first boot took
      109 s (v9, hogs).
    - The wait starts after the build, so a boot also gets the build's time (167 s for iOS on the
      runner).
    - A retry costs at most 2 × 240 s = 8 min. That still fits the 27-minute step alongside a normal
      run's 12–17 min.
- **`check.sh` steps 3 and 4** are now one function, `test_platform`, called once per platform. It
  runs:
  1. `sim-boot.sh`, which starts the boot.
  2. `xcodebuild build-for-testing` with the scheme, plan, destination (by UDID) and derived-data
     flags as before, `-quiet`, piped through xcbeautify.
     - Its own bundle, `$RESULTS/<name>-build.xcresult` (about 75 KB), means a build failure still
       leaves a bundle to upload. The `test` action's bundle used to hold the build log.
  3. `sim-boot.sh --wait`.
  4. `xcodebuild test-without-building` with the same arguments, the result bundle as before,
     `-parallel-testing-enabled NO`, `-test-timeouts-enabled YES` and
     `-default-test-execution-time-allowance 60`, piped through xcbeautify. Then
     `check-test-results.sh`.
  - The summary gets three lines per platform: build, boot and tests.
  - The watch's `-parallel-testing-worker-count 1` is gone. It limited the clones to one (F00 #17),
    and serial testing makes no clones.
  - `--fast` and `--lint-only` exit before any of this, so they still touch no simulator (W27).
  - The simulators stay booted after a run, as `xcodebuild test` leaves them. The next run's boot
    then takes no time ("waited 0s").
- **Watchdog.** A step timeout kills check.sh but not xcodebuild, and the bundle it leaves is
  unreadable (above).
  - `pr.yml` sets `LEDGER_XCODEBUILD_DEADLINE: 1500` on the check.sh step, whose timeout is 27 min
    (1620 s).
  - check.sh starts `(sleep "$LEDGER_XCODEBUILD_DEADLINE" && pkill -INT -P $$ -x xcodebuild) &` and
    kills it on exit.
  - `-P $$` confines it to check.sh's own xcodebuild. Locally, other worktrees run theirs.
  - **Measured** through check.sh on the real xcodebuild, with the SIGINT at 30 s, mid-iOS-test:
    - xcodebuild printed "** TEST EXECUTE INTERRUPTED **" at once.
    - It then waited 30 s for the action log, warned that the log could not be saved, and exited 73,
      31 s after the SIGINT.
    - The bundle reads with xcresulttool: per-target results up to the interruption (9 targets
      passed, the running one Failed).
    - The 120 s margin covers the 31 s.
  - It fires once. If the deadline falls between two xcodebuild runs, nothing is interrupted, and
    the timeout acts as before. A first try at 45 s hit the gap after iOS testing.
  - The nightly's steps have no step timeout (the job has 120 min), so the nightly has no watchdog.
- **Nightly** (`nightly.yml`, test step): the same sequence, inline.
  - Resolve by UDID, `sim-boot.sh`, `build-for-testing` (with its own bundle), `sim-boot.sh --wait`,
    `test-without-building -parallel-testing-enabled NO`, then `check-test-results.sh`.
  - The matrix's `workers` input is removed. With parallel testing off, a worker count means nothing:
    xcodebuild runs one test process at a time, on the one simulator.

**Tests.**
- `lib.sh` `fake_simctl` now answers `boot`, `bootstatus`, `shutdown` and `erase`.
  - `XCRUN_BOOTED=1` makes `boot` answer as simctl does for a booted simulator.
  - `XCRUN_HANG=always` makes `bootstatus` hang until killed. `XCRUN_HANG=unerased` makes it hang
    until the log shows that simulator erased.
- `check-wiring.adv.sh` now has 55 cases, up from 43.
  - The real `sim-boot.sh` runs in the sandbox; `ADV_SIM_BOOT` overrides it.
  - The fake xcrun logs to the stubs' log, so the order of simctl and tool calls is visible.
  - The xcodebuild stub's id now includes the action.
  - W02, W04, W06, W09, W10, W23 and W25 name `build-for-testing` and `test-without-building`. W24
    and W27 read the shared log. W27 now also covers booting and waiting.
  - W28: per platform, boot, build-for-testing, bootstatus, then test-without-building, each by UDID.
  - W29: both test runs pass `-parallel-testing-enabled NO`, with no YES and no worker count.
  - W30: a boot that times out is erased and waited for once more (once per platform), and then the
    tests run.
  - W31: a second timeout stops check.sh before any test run and prints the error.
  - W32: a bootstatus that fails, rather than hangs, takes the same path.
  - W33: an already-booted simulator is fine and prints nothing.
  - W34: any other boot error is printed, and the wait decides.
  - W35: `LEDGER_XCODEBUILD_DEADLINE` interrupts a hung xcodebuild. check.sh exits 130, long before the
    hang would end, and checks no test results.
    - The hung stub `exec`s `/bin/sleep` through a symlink named `xcodebuild`, so `pkill -x` sees that
      name.
    - perl resets SIGINT for this case, because a caller that runs the suite in the background passes
      SIGINT on as ignored.
  - W04 injects a `build-for-testing` failure for each scheme: the calls end at the build and its
    xcbeautify.
- `workflows.adv.sh` now has 52 cases, up from 51.
  - WF48 runs the nightly's test step with the real `sim-boot.sh` for each matrix entry. It checks
    boot, build-for-testing, `bootstatus -b`, then test-without-building (parallel NO, no worker
    count), each by UDID.
  - WF49: Check's deadline falls 1–5 min before its step's timeout.
- Cost: `check-wiring.adv.sh` takes 12 s instead of 3.5 s. The real `sim-boot.sh` runs in every case,
  and W30 and W31 wait out 1-s boot timeouts and W35 a 3-s deadline.

**Verification.**
- **a. Script tests pass.** `adversarial.test.sh` ran 235 cases in 7 suites: check-test-results 18,
  check-wiring 55, ci-post-clone 14, coverage-gate 60, release-please 16, sim-destination 20 and
  workflows 52. `coverage-gate.test.sh` ran 10 cases.
  - **Mutation checks**, one at a time:

    | Mutant | Fails |
    |---|---|
    | HEAD's `check.sh` (`ADV_CHECK_SH`) | every new case, W28–W35, and the renamed W02, W04, W06, W09, W10, W23, W25 |
    | `-parallel-testing-enabled YES` on the test runs | W29 |
    | waiting for the boot before the build | W02, W04, W09, W28, W30–W32, W34 |
    | no boot wait | W02, W04, W09, W28, W30–W32, W34 |
    | no watchdog | W35 |
    | `sim-boot.sh` without the retry | W30–W32 |
    | `sim-boot.sh` retrying without the erase | W30–W32 |
    | `sim-boot.sh` with boot errors fatal | W33, W34 |
    | HEAD's `nightly.yml` (swapped in, then restored) | WF48 |
    | HEAD's `pr.yml` (swapped in, then restored) | WF49 |

    W33 first passed against HEAD, which never boots. It now also checks the lifecycle.
- **b. Full gate** through the simulator lock, under normal local conditions (warm DerivedData, the
  existing simulators): **green in 161 s**, against 208 s before.

  | Step | Before (208 s run) | Now |
  |---|--:|--:|
  | tools, format | 0 s | 1 s |
  | lint + script tests | 29 s | 32 s |
  | iOS | 103 s | 67 s: build 27, boot 0, tests 40 |
  | watchOS | 74 s | 59 s: build 22, boot 2, tests 35 |
  | coverage | 2 s | 1 s |
  | **total** | **208 s** | **161 s** |

  - PR: 17 targets, 431 tests passed, on iPhone 17 itself, with no clones. PR-Watch: 8 targets, 422
    tests passed. Coverage: LedgerDomain at 98.78 %.
  - The log is `f01-speed-check.log` in the session scratchpad.
- **c. Runner shape**, under the lock in one go (`scratchpad/f01probe/runner-shape.sh`).
  - Setup: a freshly created, never-booted iPhone 17 (iOS 26.5) and Apple Watch Series 11 (46mm)
    (watchOS 26.5), passed as `LEDGER_IOS_DEST` and `LEDGER_WATCH_DEST` by id, with `hog.sh 8`
    running for the whole of check.sh and `CI=true`. DerivedData was warm, so the build hid less of
    the boot than the runner's cold 167 s build will.
  - The full check.sh was **green in 317 s**:

    | Step | Time |
    |---|--:|
    | tools, format | 0 s |
    | lint + script tests (235 + 10 cases, W35 included) | 53 s |
    | iOS build (boot running) | 22 s |
    | iOS boot wait | 60 s |
    | iOS tests | 85 s |
    | watchOS build (boot running) | 22 s |
    | watchOS boot wait | 11 s |
    | watchOS tests | 62 s |
    | coverage | 2 s |
    | **total** | **317 s** |

  - **Against v8** (the same shape with parallel testing, 458 s of testing): after the build, iOS took
    **145 s** (boot wait 60 s + tests 85 s).
    - The first boot took about 82 s, the 22 s build plus the 60 s wait. v9, which did not overlap
      the boot with a build, took 109 s.
    - The bundle's own test time was 61 s.
  - PR: 17 targets, 431 tests passed, on `f01-runner-iphone17` itself. PR-Watch: 8 targets, 422
    tests passed. Coverage: 98.78 %. The log has no clone.
  - Afterwards both devices were deleted (`simctl list` shows none) and no hog was left.
    The log is `f01-runner-shape.log` in the session scratchpad.
- **d.** Everything is uncommitted. `scripts/sim-boot.sh` is new and untracked, mode 100755.

**Estimate.** The diagnosis estimates **12–17 runner-minutes per code-PR run** (billed per job, rounded
up), against 21 or more before. Confidence is **medium** until a runner run confirms it.
- The build scales as estimated (167 s for iOS on the runner), and the boot now overlaps it.
- The uncertain part is serial testing on a 3-core runner, both platforms.
- ci-cd.md's header (13–18 minutes) is left as it is. It agrees with this estimate, pending a run.

**Budget.** Changed lines outside `scripts/tests/` and `tasks/`: **634** (insertions plus deletions
against `main`), up from 529, against the 500 budget.
- This round: `sim-boot.sh` +37, `check.sh` +35/−27, `nightly.yml` +12/−10, `pr.yml` +2.
- Nothing was compressed to fit.

**Left for the orchestrator.** testing-strategy.md §7 (F00's contract, outside F01's Touches) still
shows `xcodebuild test` with parallel testing on. It should describe build-for-testing, boot and
serial testing.

## Pending (not verifiable locally)

- **Criteria 1–5 and 10** need GitHub. The first `pr.yml` run on the F01 PR covers
  criterion 1 and the cache logs. Criterion 1 now means one `Check` job.
- **The next PR run tests the second-run fix.** Its summary's build, boot and tests lines give
  the runner's boot wait and the serial test time, and so confirm or revise the 12–17 minute
  estimate.
- **Probe PRs:** the minutes budget argues for batching them into one throwaway PR with
  separate commits, pushed one at a time:
  - lint: a force unwrap;
  - test: a failing `#expect` in LedgerDomainTests;
  - coverage: the LedgerDomain threshold set to 99;
  - snapshot: after F06 lands.
- **Criterion 10**, the cheap way (N10): dispatch `nightly.yml` on a throwaway branch whose
  `.xcode-version` names a missing Xcode. Every macOS job fails within a minute, and `report`
  still opens the `nightly` issue.
- **Criteria 7 and 9 are manual** (Pete), in `docs/xcode-cloud/README.md` §6.
- **Merge F01 with `gh pr merge --squash --subject "ci: …"`.** A `feat` subject would open a
  0.2.0 release PR, and a merge commit would put the `fix(ci):` commits on `main` (0.1.1).
  release-please reads the whole message; the default squash body is safe.
- **G5 stops for Pete.** The PR edits ADR-006 and touches releases and Xcode Cloud delivery.
- **Follow-ups not done:**
  - SwiftLint analyzer (F00 #9);
  - Dependabot for the SHA pins;
  - Xcode 26 compilation caching (`COMPILATION_CACHE_ENABLE_CACHING`), to be measured once
    real run times exist;
  - testing-strategy §4 wording: the job names, `required`, and LedgerSnapshotTesting.
- **`check.sh:54`** (the EXIT trap, `check.sh:47` before the second-run fix) has a shellcheck SC2154 false positive from F00, left untouched.
