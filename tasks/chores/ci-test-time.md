# PR CI in one try, in about 30 minutes (2026-10-20)

Branch `chore/ci-test-time`, cut from `origin/main` at `685314c`. Goal: a PR's `Check` run finishes on its
first try, in about 30 minutes, with no test coverage lost.

## Plan

- [x] 1. Cold first run: verify the hypothesis (nothing saves a cache on `main`), then fix it.
- [x] 2. Route the six suites added 2026-10-18/19 through `TestSweep`.
- [x] 3. NameFieldLine: host once per (place, weight) — measured, not the cost; the measuring was sped up instead.
- [x] 4. Flake: `eventually(...)` waits on the condition with a bound in seconds, not a yield count.
- [x] 5. `docs/ci-cd.md` and `pr.yml`'s comments: the cache story and the deadline re-derived.
- [x] Verify: the six suites under `TEST_RUNNER_LEDGER_SWEEP=pr`, before and after; the full gate (below).

## 1. Cold first run

**Hypothesis confirmed.** `pr.yml` runs on `pull_request` and `workflow_dispatch` only, so no run ever saves
in `main`'s scope; GitHub lets a PR's run read its own ref's caches and its base branch's, nothing else.
`gh cache list` on 2026-10-20: every `compilation-…` and `spm-…` entry is on a `refs/pull/<n>/merge` ref (#57
to #66), none on `refs/heads/main`; 8.9 GB of the repository's 10 GB in use. The SwiftPM checkout cache has
the same gap, and worse: its key is the same on every PR (`spm-90b6e60…`), so each PR resolved packages cold
and saved its own 411 MB copy of an identical entry.

**Fix: the unmerged commit of 2026-10-17** (`646c66f`, branch `worktree-agent-a92dc1ccb90626738`,
`tasks/chores/2026-10-17-main-cache.md`), held back then only for its cost on paid minutes. The repository is
public now, so it is cherry-picked here: `.github/workflows/main-cache.yml` runs on each code push to `main`
and runs the new `scripts/check.sh --build-only` (step 0 and step 3's iOS `build-for-testing`, through the
same `test_platform` code, so every compile's arguments, and with them every cache entry's key, are Check's;
no boot, catalogs, tests or coverage). It saves the compilation cache under Check's key scheme and the package
checkouts under their exact key, both in `main`'s scope, after a green build only. A PR whose lockfiles match
`main`'s then hits the package cache exactly (and saves no copy of it), and its compilation restore-keys find
`main`'s newest entry.

Conflicts resolved against `main`: `ARCHS=arm64` (the arm64 chore, 2026-10-18) stays on the build's
arguments; check-wiring's `--build-only` cases are W77 and W78, since that chore took W76.

## The runner, 2026-10-19 and -20 (`gh run view --log`)

| Run | Restored | Script tests | iOS build | iOS tests | Total |
|---|---|--:|--:|--:|--:|
| #65 first (39328111254/1) | nothing | 96 s | 865 s | stopped at the deadline | 3,126 s, exit 75 |
| #65 re-run | its own commit's | 87 s | 441 s | 2,099 s | 2,635 s |
| #66 first (39366534685/1) | nothing | 150 s | 1,424 s | stopped at the deadline | 3,129 s, exit 75 |
| #66 re-run | its own commit's | 144 s | 758 s | 2,210 s | 3,124 s |

Every one logged `Cache not found` for the package checkouts too, re-runs included: `actions/cache` saves only after
a green job, and a first run stopped by the deadline is red. #66's re-run ended 4 s past the old deadline's value
(its tests just inside). So even warm the tests were near 2,100–2,210 s: the main cache alone does not make one
try enough; the tests must fall too.

From #66's first-run bundle (`results-39366534685-1`), the runner's time for the suites here: NameFieldLine 314 s
for the 46 of its 57 cases it reached, FieldFont 158 s, the S10 name field 81 s: 2.0 to 3.0 times the Mac's.

## 2. and 3. The suites

Measured on a developer Mac, `six.sh` (scratchpad): the PR plan built, then the suites alone, serial, with
`TEST_RUNNER_LEDGER_SWEEP=pr` and 40 seeds, every argument's duration summed (`rank.py`; xcresult's "Test Case"
duration leaves the arguments out). FieldFont was measured from `HEAD`'s file separately (the first run's
identifier missed its `RenderingSuites` parent).

| Suite | Before (cases) | After (cases) |
|---|--:|--:|
| NameFieldLine (+ Room, Round 2) | 194.9 s (57) | 107.7 s (43) |
| FieldFont (adversarial) | 52.5 s (36) | 35.6 s (36) |
| Receipt LOGGED cut | 22.8 s (6) | 5.7 s (6) |
| Receipt layout | 12.8 s (14) | 12.3 s (14) |
| End workout? sheet (adversarial) | 8.8 s (32) | 4.0 s (14) |
| End workout? sheet layout | 5.0 s (13) | 5.1 s (13) |
| **Total** | **296.8 s** | **170.4 s** |

FinishSheet layout already went through `TestSweep` (its sizes are `WorkoutPageLayoutTests.sizes`, its settings
`LayoutSetting.sweep`); nothing in it changed. Receipt layout's one unswept test, the stacking switch, holds its
four sizes (they straddle the boundary, which `isAccessibilitySize` alone moves) and now sweeps its settings. Also
routed: `DayEditorViewsNameAdversarialTests.seedNames_areDrawnWhole` (every size; 81 s for its suite on #66's
runner), which keeps `.xLarge`, its finding's size.

Kept on every runner, by `also:` or by not being reduced: `.accessibility3` for "a name stays where it is" (the
field stands 1 pt higher there, nearest the 1.34 pt bound), the receipt's four stacking sizes, both directions and
the 375 pt phone in the LOGGED cut (the reduced `LayoutSetting.sweep` has both), `.accessibility5` wherever a
measure was on its bound (FieldFont's `.display`, the caret's room). No assertion was dropped; the full gate and
the nightly set no `LEDGER_SWEEP` and run every list whole.

**Item 3, hosting once per (place, weight): the hypothesis does not hold.** A probe (not committed) timed one
case's parts: the first window of the process 0.6 s and its first focus 0.36 s, every later window 5–13 ms and
focus 3–7 ms; but each measure of a drawing was 110–280 ms (`layer.render` at 3x, 130 ms, then a box over 1.9
million pixels in an unoptimized build, about 150 ms). Sharing windows would save about 1% and couple cases
through one field's state, so each case keeps its own. Instead `Shown.box` and `columns(of:)` walk the buffer row
by row through its storage (144 -> 110 ms a box; the probe checked both against the old loops, equal), and the
mixed-scripts check measures one drawing twice where it drew twice.

## 4. The flake

`eventually(_:)` in `WorkoutAdversarialWaiting.swift` looped 200,000 times over `Task.yield()`. Its callers (74,
all in FeatureWorkoutTests' adversarial suites) wait for work on other tasks: a store's actor, `RestProbeClock`'s
sleepers (a `LockIsolated` count), a double's counter. Most of that is not observable, so `Observations` (the
non-adversarial helper's way) cannot see it. It now polls the condition against `ContinuousClock` with a bound of
10 s (`limit:`): yielding for the first 1,000 turns, as fast as before, then sleeping 1 ms a turn so the late
tasks get the cores; cancellation ends it too. No caller expects "never came" (the five that read the result
`guard` on success), so the bound costs nothing on a green run.

Evidence: `flake.sh` (scratchpad) ran `WorkoutAnnouncementAdversarialTests` with 2,000 seeds (1021568 is seed 129)
beside nine busy loops on a ten-core Mac: 5 of 5 tests passed, the walk's 2,000 cases included, in 1,363 s. The
other callers run in the full gate below. Not done: the same load against the old helper (a 23-minute control).

## 5. Deadline

The tests on the runner should be about 2,210 s less 250–380 s (the Mac's 126 s saved at 2.0–3.0x): about
1,960 s at most. A warm first run is then about 150 + 758 + 1,960, near 2,870 s (48 min); a cold one (no cache
for the lockfiles) about 1,424 + 150 + 1,960 = 3,534 s. The deadline is now 3,840 s (that plus 5 min), the step
66 min, the job 71 (WF65). Standard minutes are free, so the headroom costs nothing until something hangs.

**About 30 minutes is not reached by this chore.** Of a first run's ~48 min, the tests are ~33 on the runner.
Further cuts, not made here (each sweeps every size without `TestSweep`): `ProgramViewsRoomAdversarialTests`
(two tests over `DynamicTypeSize.allCases`), `DayEditorViewsRoomAdversarialTests` (two, by phone too),
`NameFieldLineTests` (one), `RestPanelRoomTests` and the LedgerFont sizing/rendering suites (whole-list checks,
probably to keep); and the hosted drawing itself (`PixelBuffer.init` maps 1.9 million pixels one by one in a
debug build).
