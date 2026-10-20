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

## Verification

- Full gate, `scripts/check.sh` with no variables, under the simulator lock (`ci-chore-gate.log`, scratchpad):
  **exit 0, 1,993 s** (lint 79 s, iOS build 12 s, iOS tests 1,631 s, watchOS build 14 s, watchOS tests 252 s;
  coverage overall 98.66 %).
- The full gate still runs every list whole: NameFieldLine 57 cases (as before, when nothing reduced it; 153.6 s
  against 194.9 s, the faster scan), FieldFont 36, the sheet's adversarial suite 32, Receipt layout 18, LOGGED
  cut 10, the S10 name field 51.
- Script suites: check-wiring 142 passed, workflows 74, xcode27 44 (2 skipped, the opt-in cases, as before).
- Flake: above (2,000 seeds under load, green).
- Not shown until it runs on GitHub: `main-cache.yml` saving both caches in `main`'s scope, a PR's first run
  restoring them, and the runner's test time after the cuts.

## G2 round 1 (2026-10-20)

Adversarial pass over `origin/main..HEAD` (5 commits). Mutants were scratch edits, each reverted (tree clean
after); simulator runs under the lock (scratchpad `g2/run.sh`). No test committed: nothing found needs one.

**Findings**

- **CI-TT-1 (Minor): the flake's class is still in other waits.** Only `eventually(_:)` moved to a time bound.
  Waits that still count yields and then expect something to have happened: `restOver_isSaidAfterItIsFelt`
  (`WorkoutAnnouncementAdversarialTests.swift:190`, 20,000 yields, then `#expect(... == [.restOver])`), and
  `WorkoutRestPanelAdversarialTests.turning` (`+Screen.swift:147`, 20,000 turns, then an issue). Under a slow
  runner they fail the way seed 1021568 did. `RestBench.eventuallyPlayed` has no bound at all (a hang until
  the plan's 60 s allowance). One run of 9 busy loops beside 10 suites stayed green, so this is from reading
  the code, not reproduced.
- **CI-TT-2 (Minor): PR mode cut-checks LOGGED left to right only on the widest, plainest phone.**
  `LayoutSetting.sweep` keeps the iPhone 17 plain (left to right) and the 375 pt phone bold (right to left).
  `logged_isWhole` runs the cut check only left to right, so on the PR runner it never checks the 375 pt
  phone, the setting most likely to cut. The 375 pt case is checked only by the mirrored "one line,
  within 8 pt" check. The comment "Both directions on every runner" is true but suggests more coverage than
  there is. Mutants M4 (the note never wraps) and M4b (LOGGED `lineLimit(1)`, note `layoutPriority(1)`)
  passed in **full** mode too, so no loss was shown; the full gate keeps all eight settings.
- **CI-TT-3 (Note): the cold margin is about two or three feature PRs.** Recomputed from the job logs (#65:
  96/865 cold, 87/441/2,099 warm; #66: 150/1,424 cold, 144/758/2,210 warm; tools, catalogs, boot and coverage
  about 11 s): warm first run ≈ 150 + 758 + 1,960 + 11 ≈ 2,880 s (960 s inside 3,840); cold ≈ 3,545 s (295 s
  inside). The tests grew 111 s from #65's set to #66's, so the cold case runs out after about three more
  suites. WF65's pin is consistent (3,840 s, 66 min, 71 min, 120 s before the step's end). The job's 5 min
  covers what the steps around it took (about 25 s before, 50 s after on a red run).
- **CI-TT-4 (Note): `eventually` on cancellation.** A cancelled wait records "never came in 10 s" when
  10 s did not pass. A red walk costs the same as before: with product mutant M5 (the store never says it
  hears the session), `walk_saysEachRestOnce` stopped at the PR plan's 60 s allowance on its first seed, both
  with the new helper (34 "never came") and with `main`'s (26). The 10 s bound makes no red run longer.
- **CI-TT-5 (Note): `focus_doesNotMoveTheName`'s `TestSweep.sizes([.large, .accessibility3], also:
  [.accessibility3])` changes nothing:** both sizes are kept either way. `focus_doesNotMoveANameWithAnEmoji`
  (a known-issue test) drops `.accessibility3` on the PR runner; at `.large` it still notices if NF-1 goes away.
- **CI-TT-6 (Note): main-cache operations.** It has no `workflow_dispatch`. After a red or cancelled push run,
  or after 7 days without a PR (eviction), the fix is "Re-run" of the last run or another code push.
  `pr.yml`'s `workflow_dispatch` on `main` is a second writer into `main`'s scope (it saves after red runs
  too). Only people with write access can trigger it, and the cache is content-addressed, so this is benign.
  The cache entry grows across merges until a lockfile or Xcode bump (accepted in the 2026-10-17 chore).
- **CI-TT-7 (Note, not this chore):** mutant M2 (`fieldLineHeight` 1.25) is caught only by FieldFont; the
  NameFieldLine and S10 name-field suites pass it in full mode.

**Attacked and held**

- Cache keys and paths: identical strings in both workflows (hashFiles inputs, prefixes, paths); WF68–71 and
  check-wiring W77/W78 re-run green (74 and 142 passed). A PR reads the base branch's exact `spm-` key.
  Both saves are `success()`-gated, docs-only pushes are skipped, and a lockfile or `.xcode-version`
  change is not ignored. A push cancelled by a newer one saves nothing. Fork and same-repo PRs save
  only under `refs/pull/<n>/merge`, and `main-cache.yml` restores `main`'s scope alone, so a PR cannot
  poison `main`'s cache. The build-only build's arguments are Check's (W77), and the environment
  variables Check adds are runner variables, not build settings. Usage is 9.95 GB of 10 GB with 38
  entries. `main`'s entries are read by every PR, so LRU evicts the PR entries first.
- Coverage in full mode: every routed list goes through `TestSweep.subset`, which returns the list itself
  when `LEDGER_SWEEP` is unset, and `LayoutSetting.sweep` equals `everySetting` in full mode. Case
  counts by arithmetic: NameFieldLine 57 full, 43 PR, as claimed. No assertion is gated on the mode.
- `also:` and bounds: mutants M2 (`fieldLineHeight` 1.25) and M3 (the field's `.top` guide `.rounded()`)
  fail in full mode at `.accessibility5` for every failing role (M2 also at `.accessibility3` for numeralL and
  numeralXL; M3 at `.accessibility5` alone). So PR mode catches both. The room under the caret is least at
  `.accessibility5` (17.3, 7.3, 3.0, 2.0 pt).
- The pixel walks: `PixelBuffer`'s public init always packs `width * height` pixels (`bytesPerRow =
  width * 4`), so a row-major walk visits exactly the old `enumerated()` pixels with the same (x, y).
  Min, max and column sums don't depend on the order. Empty buffers give `.null` and `[]` as before, and
  RTL doesn't enter at pixel level. Measuring one drawing twice can only differ from two drawings by the
  caret, which both filters leave out.
- `eventually` under load: 10 FeatureWorkout adversarial suites (Announcement, Rest, Save, Store, Updates,
  Relaunch, Pump, Minimize, RootSave, RestPanel), PR mode, 40 seeds, 9 busy loops on 10 cores: 111 tests, 110
  passed, 1 expected failure, 211 s. A plain `Task.yield` loop measured 200,000 yields in 0.67 s
  (macOS, -Onone), and 1,000 1 ms sleeps in 1.98 s.

## G3 round 1 (2026-10-20)


**APPROVED.** No must-fix.

### G3: Should-fix
1. **pr.yml:127-130.** "A first run restores main's cache … 441-758 s" credits the figures to the wrong runs. They came from re-runs that restored their own exact cache. Reword it to "builds warm, as #65/#66's re-runs did (441-758 s)".
2. **docs/ci-cd.md:86-88 and :130; pr.yml:132.** Nothing says what changes if the repo goes private again. Add one clause: main-cache.yml would then cost about 10–14 billed macOS minutes per code merge, and a hang would cost about 12 minutes more at the 3,840 s deadline. Say to revisit both.
3. **main-cache.yml:6.** "(WF68 compares them)" should read WF69.

### G3: Nits
4. **FinishSheetAdversarialTests.swift:18.** Reword to "the largest of each kind (standard and accessibility)".
5. **NameFieldLineAdversarialTests.swift:87.** `TestSweep.sizes([.large, .accessibility3], also: [.accessibility3])` is a no-op wrapper. Optional.
6. **pr.yml:108.** "This job never saves on main" isn't strictly true. Write "Only main-cache.yml saves on main (a PR run cannot)".
7. **WorkoutAdversarialWaiting.swift:28-29.** When the wait was cancelled, give it its own message.
8. **The hashFiles triple** is duplicated across both workflows. WF69 guards it, so no change.
9. **docs/ci-cd.md:26-27** has an odd wrap. **:325** "GitHub Free, private" is stale.
10. **persist-credentials: false.** Optional; it would have to change in both workflows to keep WF69 green.

### G3: Checked and correct
- the trigger and paths-ignore;
- concurrency, and that a cancelled run saves nothing;
- permissions `contents: read`;
- the SHAs, which match pr.yml;
- supply chain: fork and PR runs can't write main's scope;
- the --build-only mode, with W77 and W78;
- the pixel walk's index math;
- `eventually`, which is structured;
- the TestSweep idiom, and that the full-mode case sets are unchanged;
- the deadline math (3,840 is justified, because a lockfile or Xcode bump always builds cold);
- the scope: DayEditorViewsName is justified.

## Fix round 1 (2026-10-20)

Taken from G3: SF1 (`pr.yml` credits 441–758 s to #65's and #66's re-runs), SF2 (`docs/ci-cd.md` and `pr.yml`
say what to revisit if the repository goes private: `main-cache.yml` about 10–14 billed macOS minutes per code
merge; the deadline's headroom bills only on a hang, about 12 minutes more than at 3,120 s), SF3
(`main-cache.yml` cites WF69), nits 4 (FinishSheet's comment), 5 (the no-op `TestSweep.sizes(…, also:)` is the
literal list again), 6 ("Only main-cache.yml saves on main"), 7 (a cancelled `eventually` says "cancelled while
waiting for …") and 9 (the §1 wrap; §4 says public). Nits 8 and 10: no change.

Taken from G2:
- **CI-TT-1.** `eventually`'s condition may now be `async` (it can ask an actor), and every wait in
  FeatureWorkoutTests that waits for something to happen goes through it, so all have the same 10 s
  wall-clock bound:
  - `WorkoutAnnouncementAdversarialTests.restOver_isSaidAfterItIsFelt` (was 20,000 yields, then an expect);
  - `WorkoutRestAdversarialTests+Edges` (the logged set's haptic, 20,000 yields, then a `#require`);
  - `WorkoutRestPanelAdversarialTests.turning` (20,000 turns): now `eventually` turning the run loop each
    check, with a `sourceLocation`; its callers in `+Screen` and `WorkoutRootSaveAdversarialTests` unchanged;
  - `+Screen`'s "Rest over felt with the cover up" (200 turns, then an expect): `turning` until two haptics;
  - `RestBench.eventuallyPlayed` and `RestBench.settled` (unbounded `while`): `eventually`;
  - `WorkoutStoreRestTests.haptics_notAgainAfterARestart` (unbounded `while !isHearingTheSession`);
  - `SaveCover.settle` (400 rounds of `rest()`, then its issue): `eventually`, the same issue after it.

  Left on purpose, each a "nothing more happened" give or an interleaving, not a wait for something:
  `giveWay()` (2,000 yields), `SaveCover.rest()` (400) and `settle`'s first release loop (bounded by
  `waiting`), `WorkoutSaveAdversarialTests+RoundTwo` (5,000 turns, then "at most 8 drains"), LedgerPersistence's
  10-yield rooms and random yields (races by design). Also left: `WorkoutReceiptAdversarialSession.answer()`,
  a double's handshake that waits for a continuation the store parks; it has no expectation after it, and
  a hang there ends at the 60 s allowance.
- **CI-TT-2.** `LayoutSetting.sweep(_:also:)` takes extra settings; `logged_isWhole` adds the 375 pt phone,
  bold, left to right, so the narrow phone is cut-checked on every runner (three settings under `pr`).
- **CI-TT-6.** `main-cache.yml` has `workflow_dispatch` (WF68 pins `push,workflow_dispatch`).

Recorded, not fixed:
- **CI-TT-3, follow-up.** The cold-run margin is about 295 s, two or three feature PRs of tests. Next: route
  `ProgramViewsRoomAdversarialTests`, `DayEditorViewsRoomAdversarialTests`, `NameFieldLineTests` and
  `RestPanelRoomTests` through `TestSweep`, and look at `PixelBuffer.init`'s per-pixel conversion.
- **CI-TT-7.** The `fieldLineHeight` mutant (1.25) is caught only by FieldFont.

Load run (`flake.sh fw200`, scratchpad): all of FeatureWorkoutTests at the PR plan's 200 seeds, every sweep
whole, beside nine busy loops on ten cores: 568 tests, 567 passed and 1 expected failure, none failed, 1,169 s.
Under `pr`, the LOGGED cut suite with the narrow phone added: green, 8.8 s (5.7 s before it).
