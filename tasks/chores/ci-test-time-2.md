# PR CI test time, part 2 (2026-10-21)

Branch `chore/ci-test-time-2`, from `main` at `011ab3d`. Goal: give a cold first run real margin under `Check`'s
3,840 s deadline (CI-TT-3 of `tasks/chores/ci-test-time.md`), with no coverage lost.

## Plan

- [x] 1. Measure: the whole iOS PR plan under `TEST_RUNNER_LEDGER_SWEEP=pr` and 40 seeds, arguments included.
- [x] 2. Route the four suites CI-TT-3 named through `TestSweep`, keeping each bound case with `also:`.
- [x] 3. `PixelBuffer.init`: draw into the pixels' storage; a probe compares every image with the old path.
- [x] 4. Look for other large, cheap cuts (report only).
- [x] 5. `docs/ci-cd.md` and `pr.yml`'s deadline comment.
- [ ] Verify: the full gate. **Not run**: free disk fell to 3.4 GB (the stop line is 6 GB), mostly
  other worktrees' builds.

## Method

`ct2/all.sh` (scratchpad) builds the PR plan, then runs the whole iOS plan serially, as `Check` does, with
`TEST_RUNNER_LEDGER_PROPERTY_SEED_COUNT=40` and, for `pr`, `TEST_RUNNER_LEDGER_SWEEP=pr`. `rank.py` sums each
parameterized test's arguments (xcresult's "Test Case" duration leaves them out).

## 1. Ranking, before (main at 011ab3d; a developer Mac)

4,788 tests, 22,450 cases, **931 s of cases** (996 s wall), exit 0.

| # | Suite | s | Cases |
|--:|---|--:|--:|
| 1 | NameFieldLine (adversarial) | 120.4 | 43 |
| 2 | UI smoke | 96.5 | 4 |
| 3 | FieldFont (adversarial) | 35.6 | 36 |
| 4 | Name field line | 27.4 | 16 |
| 5 | Day editor layout | 27.3 | 27 |
| 6 | Workout save (adversarial) | 27.0 | 106 |
| 7 | Rest panel (adversarial) | 22.4 | 42 |
| 8 | Workout announcements (adversarial) | 21.7 | 53 |
| 9 | F11 S10 · the name field, drawn and hidden | 21.2 | 44 |
| 10 | F11 S9 · words cut inside a frame | 18.6 | 111 |
| 11 | F11 S10 · trees and actions | 17.7 | 30 |
| 12 | F11 S9 · frames at every size and width | 17.6 | 105 |
| 13 | Workout rest (adversarial) | 14.6 | 150 |
| 14 | Receipt layout | 12.5 | 14 |
| 15 | F11 S9 · the strip's equal cells | 11.7 | 144 |
| 16 | F11 S10 · the orange audit, whole pages | 11.6 | 10 |
| 17 | F07 S1 · history fakes against GRDB | 11.0 | 80 |
| 18 | F11 S10 · frames, pills and broken words | 10.6 | 52 |
| 19 | Program views layout | 9.7 | 109 |
| 20 | S3 · history against a model | 9.4 | 41 |

The four suites CI-TT-3 named are small here, except one test: `NameFieldLineTests.focus_keepsTheTails`
25.8 s (12 sizes). The rest panel's room 5.0 s, the Day editor's room 2.7 s, the two strip tests 2.1 s. No other
top-ranked test sweeps every size or setting without `TestSweep` (the grep for `DynamicTypeSize.allCases` and
`everySetting` finds only whole-list checks: LedgerFont sizing and rendering, the rest panel's compact switch,
the strip's "which sizes fall short", and the onboarding matrix, which is fixed). Most of the top 20 is
drawing: the name-field, FieldFont and Day editor suites read 1–2 million pixels a case at 3×.

## 2. The four suites

A probe (not committed) printed each test's measure at every size in full mode, and chose what each keeps on
the runner besides `TestSweep.representativeSizes` (`.xSmall`, `.large`, `.xxxLarge`, `.accessibility5`):

| Test | Measure, nearest its bound | Kept on the PR runner |
|---|---|---|
| Name field: tails | height equal at all sizes; the move with the focus 0.33 pt at `.large` to 1.67 of 2 pt at `.accessibility5` | the representatives |
| Week chip's room | a third of a point over at `.medium`, `.accessibility2`–`4`; 1 pt at `.xSmall`, `.large` | + `.medium`, `.accessibility3` |
| Long tag's strip | 104 hundredths at `.xSmall`–`.medium` on 375 pt (band 95–105); 98 at `.xLarge`, `.accessibility1` | + `.xLarge`, `.accessibility1` |
| Pinned bar | 60 pt to `.accessibility2`, 70.3 of 72 pt at `.accessibility5`; never squeezed | the representatives |
| Rows under the bar | small phone 2.26 rows at `.accessibility3`, 1.99 at `.accessibility4` (known issue from there) | + `.accessibility3`, `.accessibility4` |
| Rest panel's room | page least at `.accessibility4` on every phone (173 pt; 182 at `.accessibility5`) | + `.accessibility4` |

Each is in the test's comment. Full mode is unchanged: every list goes through `TestSweep.sizes`, which returns
the list whole when `LEDGER_SWEEP` is unset.

**Case counts, full mode** (the probe run, before, at 40 seeds): tails 12, week chip 12, long tag 24, bar 24,
rows 24; the rest panel's room 2 (its sizes are an inner loop, all 12 in full mode). After: the same lists by
construction; see Verification for the gate's count. **PR mode:** tails 12 → 4, week chip 12 → 6, long tag
24 → 12, bar 24 → 8, rows 24 → 12, rest room 2 (12 → 5 sizes inside).

## 3. PixelBuffer

`PixelBuffer.init` drew the image into a `[UInt8]` with a `CGContext`, then mapped every four bytes to a `Pixel`.
In the unoptimized test build that map was the cost. A `Pixel` is four `UInt8`s in RGBA order (now checked once
by `MemoryLayout`, a `precondition`), so the context now draws into `[Pixel](unsafeUninitializedCapacity:)`
itself, zeroed first as before.

**Probe** (not committed): the init ran the old path beside the new on every image, in a full-mode run of the
whole PR plan (every sweep whole, 40 seeds; green, 1,497 s wall with the probe's overhead):

- 8,323 images, 2,410 million pixels, two source formats (BGRA premultiplied-first little-endian 5,350; RGBA
  premultiplied-last 2,973): **8,323 equal, 0 different**.
- The conversion: **166.5 s → 10.1 s** in all. Images of 1.5 million pixels or more (729): median 129 → 7 ms.

The render (`layer.render` at 3×, about 130 ms in #68's probe) is left: lowering a suite's scale changes what
its 0.34 pt and 1 pt bounds can see, and each would need its own justification. The walks over the buffer
(`Shown.box`, FieldFont's `ink`) were benchmarked at -Onone on macOS: FieldFont's index-and-filter walk 96 ms
against a row walk's 81 ms for 1.1 million pixels, so not changed.

## 4. Other large and cheap

- **UI smoke**: 96.5 s, 4 tests, the largest after the name field. No sweep; it launches the app.
- **Sleeps**: none large. Run-loop turns of 20–50 ms in two hosted helpers; `eventually`'s 1 ms polls.
- **Seeds**: every seeded property already runs 40 on the runner; none runs more.
- **Further levers, not done** (each needs its own review): render the name-field and FieldFont drawings
  with a smaller window, or at 2× where a check's bound allows; compile `LedgerSnapshotTesting` optimized; run
  the UI smoke apart from the unit tests.

## After (both commits; a developer Mac)

4,788 tests, 22,396 cases, **801 s of cases** (844 s wall), exit 0. The host was loaded during part of this
run (load average near 15, other worktrees compiling): suites with no drawing and no change grew, e.g. the
announcements walk 10.7 → 23.6 s and the receipt's cut check 7.3 → 16.2 s. Summed, suites that got faster
saved 196.7 s and suites that got slower added 68.0 s. The net 129 s is a floor.

| Suite | Before s (cases) | After s (cases) |
|---|--:|--:|
| NameFieldLine (adversarial) | 120.4 (43) | 58.1 (43) |
| Name field line | 27.4 (16) | 5.1 (8) |
| FieldFont (adversarial) | 35.6 (36) | 21.5 (36) |
| F11 S10 · the name field, drawn and hidden | 21.2 (44) | 10.7 (44) |
| Day editor layout | 27.3 (27) | 17.3 (27) |
| F11 S10 · trees and actions | 17.7 (30) | 13.5 (30) |
| F11 S10 · the orange audit, whole pages | 11.6 (10) | 7.4 (10) |
| LedgerFont native line height (adversarial) | 8.7 (168) | 4.4 (168) |
| F11 S10 · the room under the pinned header | 2.7 (52) | 1.1 (24) |
| Rest panel: the page's room | 5.1 (3) | 4.1 (3) |
| F11 S9 · the strip's equal cells | 11.7 (144) | 23.5 (126); load, see above |
| **All** | **931** | **801** |

## Projection for the runner

#67's warm run tested for 2,407 s against this Mac's 931 s for the same set (2.4–2.6×). Saved here: 129 to 197 s
on the Mac, so about 310–510 s on the runner, and the tests there about **1,900–2,100 s**. A cold first run:
about 150 + 1,450 + 2,100 = 3,700 s at worst (140 s inside 3,840), 3,500 s at best (340 s). Warm: about
150 + 760 + 2,100 = 3,010 s. **That is not enough margin for F12's 200–400 s on a cold run**; the levers above
are next. The deadline is unchanged.

## Verification

- Before and after: above (both green). Probe: above (green, every image equal).
- Lint: `swiftformat --lint` and `swiftlint --strict` clean on the changed files.
- **Full gate: not run** (disk). To run on this branch's head once there is room:
  `rm -rf .derivedData/Results && { /usr/bin/python3 <sim-lock.py> scripts/check.sh > <scratchpad>/ci-chore2-gate.log 2>&1; echo GATE_EXIT=$? >> <scratchpad>/ci-chore2-gate.log; }`.
  Its iOS bundle also gives the full-mode case counts after (expect the per-test counts above; seeded tests
  differ only by the plan's 200 seeds against the probe's 40).

## Files

`LedgerKit/Sources/LedgerSnapshotTesting/RenderedImage.swift`;
`LedgerKit/Tests/FeatureProgramTests/Adversarial/ProgramViewsRoomAdversarialTests.swift`,
`…/Adversarial/DayEditorViewsRoomAdversarialTests.swift`, `…/NameFieldLineTests.swift`;
`LedgerKit/Tests/FeatureWorkoutTests/RestPanelRoomTests.swift`; `docs/ci-cd.md`; `.github/workflows/pr.yml`
(comment only); this file. None names `FilterChips` or `ExerciseSearchField` (F12 S1).
