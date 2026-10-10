# The PR lane's time on the hosted runner (2026-10-09)

Branch `ci/pr-lane-time`, cut from `main` at `0d4a156`. Two first runs of new branches were interrupted by
`LEDGER_XCODEBUILD_DEADLINE` (2,400 s) on 2026-10-09 with no test failing, and each needed a second paid run.
This file says where the time goes, what was changed, what was not, and what the first CI run should show.

## What changed

| File | Change |
|---|---|
| `.github/workflows/pr.yml` | `Check` sets `TEST_RUNNER_LEDGER_PROPERTY_SEED_COUNT: 40`; `LEDGER_XCODEBUILD_DEADLINE` 2,400 → 2,520; the step's timeout 42 → 44 min, the job's 47 → 49 |
| `scripts/tests/adversarial/workflows.adv.sh` | WF65 pins 2,520 and 44; new WF66 pins the 40, that it is below the PR plan's count, and that no other job and no nightly step sets one |
| `docs/ci-cd.md`, `docs/testing-strategy.md` | the two entries "Seeds on the runner" and "Deadline"; a control must pass on 40 seeds |

No test, no test plan, no project file and no tester's file was edited. Edits to files named `Adversarial`: none.

## Measured: the test step

Sources: the result bundles of the two interrupted runs (37966313599 attempt 1, PR #49; 37967995869
attempt 1, PR #50), the logs of all four attempts, five earlier green runs, and a run of the same step on
a developer Mac from this branch before the change. A green run uploads no bundle, so the per-test figures
are from the interrupted attempts: #50's had run every target when it was stopped; #49's stopped inside
`FeatureProgramTests`.

| Run | Compiled output | iOS build | iOS tests | Outcome |
|---|---|--:|--:|---|
| #49 attempt 1 | none to restore | 1,145 s | 1,125 s, then stopped | exit 75 |
| #49 attempt 2 | restored | 568 s | 1,497 s | green, 2,191 s |
| #50 attempt 1 | none to restore | 1,140 s | 1,131 s, then stopped | exit 75 |
| #50 attempt 2 | restored | 594 s | 855 s | green, 1,575 s |
| five green runs, 2026-10-08 and -09 | one restored (750 s), four not (956–1,221 s) | 750–1,221 s | 773–1,151 s | green |
| developer Mac, `main` | — | 117 s | 419 s | green |

The same commit (#50) took 855 s and more than 1,131 s: the runner's speed varies by a third between
runs. The runner takes 2.0 to 3.2 times the Mac's time for the step.

**Tests run one at a time.** With `-parallel-testing-enabled NO` each target's wall time is the sum of
its cases' times, on the runner and on the Mac (`LedgerPersistenceTests`: 326 s of wall, 315 s of cases). So
a case removed is its time saved. The step is 37,912 cases long on `main` (38,066 on #50's branch).

Per target (seconds; "cases" counts each argument of a parameterised test):

| Target | Cases | #49 a1 | #50 a1 | Mac | Cases at 40 seeds | #50 a1, estimated at 40 |
|---|--:|--:|--:|--:|--:|--:|
| LedgerDomainTests | 22,413 | 209 | 171 | 49 | 6,643 | 61 |
| LedgerPersistenceTests | 4,938 | 315 | 245 | 92 | 2,747 | 179 |
| LedgerDesignTests | 2,140 | 119 | 139 | 44 | 2,138 | 139 |
| FeatureProgramTests | 3,671 (#49: with S9's suites) | 251, stopped | 114 | 40 | 1,571 | 78 |
| FeatureTodayTests | 1,252 | 95 | 104 | 31 | 1,026 on `main` | 103 |
| LedgerAppKitTests | 1,301 | not reached | 71 | 15 | unchanged | 71 |
| LedgerUITests (Smoke, 3 tests) | 3 | not reached | 69 (81 with launches) | 62 | 3 | 69 |
| LedgerSyncTests | 1,771 | 56 | 46 | 17 | 1,451 | 44 |
| FeatureWorkoutTests | 485 | not reached | 28 | 8 | 485 | 28 |
| LedgerTests (hosted in the app) | 2 | not reached | 0 (25 with the launch) | 0 (9) | 2 | 0 |
| the other seven targets | 97 | 7 | 7 | 1 | 97 | 7 |
| **All** | **38,066** | 1,052, stopped | **994** | **358** | **17,372** | **777** |

The slowest suites on the runner (#50 attempt 1; #49 attempt 1 where it ran them):

| Suite | #50 | #49 | Mac | Cases, 200 seeds → 40 |
|---|--:|--:|--:|--:|
| FeatureProgramTests · Adversarial F11 S9 · words cut inside a frame (on #49's branch only) | — | 124 | — | 101 text-size and width cells; no seeds |
| LedgerUITests · Smoke | 69 | — | 62 | 3 → 3 |
| LedgerDomainTests · WorkoutEngine · HLC convergence (adversarial, round 2) | 41 | 45 | 13 | 204 → 44 |
| LedgerPersistenceTests · Adversarial F07 S1 · history fakes against GRDB | 37 | 48 | 15 | 120 → 80 |
| LedgerAppKitTests · Adversarial F09 S1 · the tab shell, hosted | 34 | — | 6 | 53 → 53 |
| LedgerPersistenceTests · Adversarial S3 · history against a model | 30 | 45 | 13 | 61 → 41 |
| LedgerDesignTests · LedgerFont native line height (adversarial, round 4) | 23 | 21 | 8 | 168 → 168 |
| FeatureTodayTests · Adversarial F09 S4 · layout, the timer, loading and failed | 21 | 22 | 6 | 57 → 57 |
| FeatureProgramTests · ProgramPresentation properties | 20 | 18 | 7 | 600 → 120 |
| FeatureProgramTests · Adversarial F11 S5 · every action applied | 18 | 16 | 6 | 189 → 189 |
| LedgerDomainTests · WorkoutEngine · literal host loop (adversarial, round 3) | 17 | 20 | 6 | 205 → 45 |

The slowest tests on the runner (#50 attempt 1):

| Test | Runner | Cases | Mac |
|---|--:|--:|--:|
| Smoke · `test_sampleWorkout_anotherDay_cancelResumeAndReplace` | 55.9 | 1 | 33.1 |
| history fakes against GRDB · Random materialisations, edits and deletes | 32.8 | 60 | 13.5 |
| the tab shell, hosted · Random selections, opens, pops and returns | 31.4 | 40 | 5.5 |
| history against a model · Random materialisations, edits and deletes | 30.4 | 60 | 13.2 |
| LedgerFont sizing · `font(role, dynamicTypeSize:legibilityWeight:)` draws what `.ledgerFont` draws | 13.8 | 21 | 4.8 |
| every action applied · A walk of forty actions | 13.4 | 60 | 4.3 |
| Smoke · `test_launchesToToday` | 12.7 | 1 | 5.8 |
| program and exercise fakes against GRDB · Seeds, upgrades and saves | 12.4 | 60 | 4.8 |
| literal host loop · Property: hosts that follow ADR-004's loop literally | 12.3 | 200 | 3.9 |
| layout, the timer, loading and failed · At every text size no stop is empty | 12.3 | 13 | 3.8 |

By how many cases a test has (#50 attempt 1, seconds): 200 cases (one per seed) 189; 20 to 99 cases 310;
2 to 19 cases 238; one case 253, of which the UI tests are 69. After the first two suites the list is
flat: the 75 slowest tests are 592 s of 994, and no test past the twelfth takes 10 s.

## Measured: the build

- **Cold (1,140–1,145 s; #49 attempt 1's build log).** 251 s pass before the build operation starts
  (`-quiet` shows nothing of them: starting `xcodebuild` and resolving packages; the package cache was
  not found in any of the four attempts). The operation takes 890 s: 40 s to its build description, 122 s
  on two SDK stat caches (iPhone and Watch simulator), compiling from second 183 to second 868 (908
  compile batches, 1,617 s of compiler time on the runner's cores, the test targets from about 430 s), and
  linking, signing and asset catalogs in the last 90 s.
- **Warm (568 s and 594 s).** No build log exists: a green run uploads no bundle. Cold less warm is 550
  to 577 s, about the compile window less the time to replay it. So the compilation cache saves the
  compiles, and does not save the 251 s before the build, the build description, the stat caches, or the
  linking and signing. That split is inferred, not read.
- **Why a first run has nothing to restore.** `Check` saves caches under the PR's own ref, which other
  PRs cannot read, and nothing saves on `main` (ci-cd.md, "No `main` warm-up job"). A failed job also skips
  the package cache's save, so #49's and #50's second attempts resolved packages cold as well.
- **The package cache is not the 251 s.** A run of 2026-10-08 with both caches restored (37859418999)
  still built in 750 s. What the fixed 570–750 s are is not known from these logs.

## The change, and why this one

Seeded property tests read `LEDGER_PROPERTY_SEED_COUNT` (PR plans 200, nightly plans 2,000). `xcodebuild`
passes any `TEST_RUNNER_<NAME>` variable to the test runner as `<NAME>`; measured here, it replaces the
plan's value (`LedgerDomainTests`: 22,413 cases at the plan's 200, 6,643 with the variable at 40). So one
line in `pr.yml` gives the hosted runner the first 40 seeds of every seeded test, and nothing else moves:

- every test still runs on the runner, on the same seeds a longer run starts with;
- the full local gate, green before every merge, still runs the plan's 200 seeds, and the nightly its 2,000;
- the PR plan, the project and every tester's file are as they were.

**Why 40.** At 20 one control fails: `HLCConvergenceAdversarialTests.rawClocks_loseActions` ("the property
has no teeth: 147 early stamps, 0 lost actions"); it looks for a lost action among the first hundred of the
seeds it is given. At 30, 40 and 50 every Domain test passes; at 40 the whole PR plan passes. 40 leaves ten
seeds past the lowest count known to pass. 30 would save about 35 s more on the runner.

**Estimate.** Each test's runner time in #50 attempt 1, times its new case count over its old one: 147
tests change count (123 of them 200 → 40, 21 from 50, 60 or 100 → 40), 305 s → 115 s. Tests that loop over
the seeds inside one case add about 26 s. Total 994 s → 777 s of cases, 216 s saved; on #49 attempt 1's
slower runner the same sum saves 273 s of the part it ran.

| Run | iOS tests before | Expected at 40 seeds |
|---|--:|--:|
| #50 attempt 2 (fast runner) | 855 s | about 670 s |
| #50 attempt 1 (slow runner) | over 1,131 s (about 1,155 s had it finished) | about 940 s |
| #49 attempt 2 (slow runner, with S9's suites) | 1,497 s | about 1,220 s |

**The target of about 900 s is met on `main` on a fast runner and missed on a slow one, and missed by
#49.** The seed count is the only matrix that is one number. What is left is listed under "Not done".

## The deadline

A first run: about 125 s of script tests, a cold build of 1,140–1,221 s, 10 s of catalogs and boot, then
the tests. With 940 s of tests that is 2,215–2,300 s. At 2,400 s the margin was 100–185 s; at 2,520 s it
is 220–305 s, about 5 minutes on a build of 1,150 s. The step's timeout stays 120 s after the deadline
(44 min), and the job's 5 minutes after the step's (49 min). A run that hangs costs 2 more paid minutes.
#49 as it is (about 1,220 s of tests) would end a cold run at about 2,500 s: inside the deadline by
seconds, so its branch should cut its own suite (below) before it relies on a first run.

## Verified on a developer Mac

| Check | Result |
|---|---|
| `scripts/check.sh --lint-only` (format, lint, graph, pins, all 12 adversarial script suites, 4 lint-rule suites) | green; `workflows.adv.sh` 67 passed |
| `scripts/check.sh --ios-only --skip-lint`, before, plan's 200 seeds | green; iOS tests 419 s; 3,520 tests, 37,912 cases |
| the same with `TEST_RUNNER_LEDGER_PROPERTY_SEED_COUNT=40` | green, coverage gate too; 3,520 tests, 17,372 cases; iOS tests 441 s (see below) |
| the PR plan less the UI tests at 20 seeds | one failure, the control above |
| `LedgerDomainTests` at 30, 40 and 50 seeds | green |
| three seeded suites in each lane (below) | the nightly plan runs 2,000 seeds, the PR plan 200, the PR plan with the variable 40 |

**The Mac's before and after are not comparable as wall time.** The second run shared the machine with
another agent's host tests (load average 7): suites with no seeded test took 20 to 60 % longer than in
the first run (`LedgerDesignTests` 44 → 54 s, `FeatureTodayTests` 31 → 51 s). The targets the change
reaches fell all the same: `LedgerDomainTests` 49 → 19 s. A run of the plan less the UI tests at 20 seeds
on a quieter machine took 283 s against 322 s for the same targets before. The estimate above uses case
counts and the runner's own times, not the Mac's wall time.

The host (`swift test`) is untouched: no test file changed, and it reads no `TEST_RUNNER_` variable.

Three seeded suites in each lane, on the simulator (`HLCConvergenceAdversarialTests`,
`HistoryModelAdversarialTests`, `ProgramPresentationPropertyTests`; 10 tests, all green each time):

| Run | HLC convergence, seeded property | History against a model | ProgramPresentation, each of 3 |
|---|--:|--:|--:|
| `Nightly` plan, no variable | 2,000 cases | 2,000 | 2,000 |
| `PR` plan, no variable (the local gate) | 200 | 60 (its own PR-lane cut) | 200 |
| `PR` plan with `TEST_RUNNER_LEDGER_PROPERTY_SEED_COUNT=40` (as `Check`) | 40 | 40 | 40 |

## Not done, with the cost of each

1. **#49's own suite.** "Adversarial F11 S9 · words cut inside a frame" took 124 s on the runner (101
   cells: 60 + 17 + 12 + 12 states by text size and width). It is on that branch, not on `main`, and is a
   tester's file. Its tester can cut it by lane as F10 S3 did (a few text sizes in the PR lane, all in the
   nightly). Without that, #49's test step stays near 1,220 s on a slow runner.
2. **Text-size and hosted-view matrices on `main`** (`LedgerDesignTests` 139 s, `FeatureTodayTests` 104 s,
   the tab shell's 40 hosted walks 31 s, the day editor's suites). They are cells, not seeds, in testers'
   files: every text size is a check, and cutting them in the PR lane moves checks to a nightly that runs
   only when someone starts it. Worth about 150–200 s on the runner. Needs Pete's ruling and the testers.
3. **20 or 30 seeds.** 30 saves about 35 s more and passes today, with no seed to spare for the control.
   20 saves about 75 s more and needs the control to stop depending on the count (a tester's file).
4. **Tests in parallel inside one runner process.** The runner has several cores and runs one case at a
   time. Turning Swift Testing's parallelism on without simulator clones would cut the pure targets
   (Domain, Persistence, Sync: about 280 s after this change) by perhaps half. It changes how every
   suite runs on the simulator, the timing tests and the hosted ones included, and can only be judged on
   the runner. A change of its own.
5. **The build.** A first run's 1,140–1,221 s is larger than its tests. A cache saved on `main` would give
   every PR's first run the warm 570–750 s, for one macOS job per merge (ci-cd.md argued against it when
   most PRs had one run; on 2026-10-09 both PRs needed two). Uploading the build bundle from one green warm
   run would show what the fixed 570 s are.

## What the first CI run should show

- In `Check`'s step log, the `env:` group lists `TEST_RUNNER_LEDGER_PROPERTY_SEED_COUNT: 40` and
  `LEDGER_XCODEBUILD_DEADLINE: 2520`.
- `iOS tests` in the summary: 670–940 s for a branch that is `main` plus little. Not seen yet: that the
  variable replaces the plan's value on the runner's Xcode 27.0 as it does here. If it does not, the step
  takes what it took before (855–1,150 s) and nothing fails; the count of cases in the result tells
  (a failed run uploads the bundle; `LedgerDomainTests` has 6,643 cases at 40 seeds and 22,413 at 200).
- A first run of a new branch ends green in about 2,000–2,300 s of `check.sh`, where it was stopped at
  2,400 s.
- The coverage gate: green here at 40 seeds, with every module's line counts the same as at 200.
- A test that passes on 200 seeds and fails on 40 can only be one that asks what its seeds reach. Run it
  locally with `TEST_RUNNER_LEDGER_PROPERTY_SEED_COUNT=40 scripts/check.sh --ios-only`.
