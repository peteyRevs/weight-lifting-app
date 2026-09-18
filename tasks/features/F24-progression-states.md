# F24 — Progression states: held, failed, deload, block view, off-schedule, next block

| | |
|---|---|
| Milestone | M3 |
| Status | proposed |
| Depends on | F10, F11 |
| Branch | `feat/F24-progression-states` |
| Design refs | v1 " · HELD" label, deload week strip; v2 NEXT STEPS (3); v1 NEXT STEPS (5) |
| Spec refs | `docs/product-spec.md` §7.2 rules 9–13, §9; `docs/product-decisions.md` #5, #18 |

## Goal
Make the progression engine visible and controllable: show when a load is held after a miss, mark a set as failed during a workout, present deload weeks distinctly, give a block-level table of every week's prescription per lift, allow training an unscheduled day, and close a block with "Start next block".

## Scope
**In:** held badge on Today/Active workout target lines; failed-set marking (reps short → set row state `.failed`, counts toward misses per decision #5); deload styling (eyebrow "DELOAD", muted accent); `BlockOverviewView` (grid: lifts × weeks, prescriptions, misses highlighted); off-schedule picker on Today's rest-day card; end-of-block sheet ("Repeat block with progression" copies loads forward as new start loads; "Edit program"; "Start over").
**Out:** per-set schemes like 5/3/1 (post-launch), auto-deload suggestions.

## Touches
- `LedgerKit/Sources/FeatureToday/{OffScheduleSheet,EndOfBlockSheet}.swift`, `FeatureWorkout/SetRow+Failed.swift`, `FeatureProgram/BlockOverviewView.swift`, `FeatureProgram/BlockOverviewStore.swift`
- `LedgerKit/Sources/LedgerDomain/Rules/{ProgressionRules+Block,NextBlock}.swift` (pure helpers)
- Tests in the matching test targets

## Domain changes
```swift
public enum NextBlock { public static func rollForward(_ program: Program, exercises: [ExerciseID: Exercise], units: Units, startDate: Date) -> Program }  // new startDate, misses cleared, startLoad = last prescribed non-deload load
public enum ProgressionRules { public static func table(program: Program, exercises: [ExerciseID: Exercise], units: Units) -> [SlotID: [Prescription]] }
```
`LoggedSet` gains no fields: "failed" = done with `reps < targetReps` (derived).

## Acceptance criteria
1. Given a slot with `misses == {2}` viewed in week 3, then Today's preview and the Active workout target line show "185 lb · HELD" and a tooltip explains "A missed set last week holds the load."
2. Given a set logged with fewer reps than target, then its row renders in the failed state (muted with a small "–1" chip) and the receipt's actual column shows it plainly; on Finish, the slot gains the week in `misses` (F02 rule).
3. Given a deload week, then Today's UP NEXT eyebrow reads "WEEK 4 OF 8 · DELOAD", the week strip dot is hollow, and the workout header carries a "Deload" pill; no PRs are detected (F02).
4. Given the Program tab "Block overview", then a horizontally scrolling grid shows each lift's load × reps per week with held cells outlined and deload columns tinted; values equal `ProgressionRules.table`.
5. Given a rest day, when "Train off-schedule" is chosen and a day picked, then a workout for that template starts with the current week's prescription and, on finish, does not mark any scheduled day as done.
6. Given `weekIndex >= weeks.count`, when Today opens, then the end-of-block sheet appears; "Repeat block with progression" creates a new active program via `NextBlock.rollForward` with today as the new `startDate`.

## Test plan
- Unit: `NextBlockTests` (loads roll forward, deload weeks ignored, misses cleared, dates), `ProgressionTableTests`, `FailedSetDerivationTests`, `OffScheduleStoreTests`, `EndOfBlockStoreTests`.
- Snapshot: held target line, failed row, deload header, block overview (8 weeks × 5 lifts), both sheets.
- UI (nightly): fail a set → finish → next week's Today shows HELD.

## Non-functional
- Block overview renders 12 weeks × 30 lifts without jank (lazy grid).

## Definition of Done
Inherits `docs/engineering-standards.md` §12.

---
_Filled in by agents during delivery:_ `F24-progression-states/{implementation-notes,test-findings,review}.md`
