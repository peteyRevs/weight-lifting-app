# F13 — History tab: workout list and workout detail

| | |
|---|---|
| Milestone | M1 |
| Status | ready |
| Depends on | F07 (F10 for real data; tests use fixtures) |
| Branch | `feat/F13-workout-history` |
| Design refs | `design/prototype/Ledger.dc.html` → `Session receipt` (detail layout), `Today` RECENT rows; `Ledger v2.dc.html` visual system |
| Spec refs | `docs/product-spec.md` §3.6, §7.6 rule 30, §9 ("Workout history list"); `docs/product-decisions.md` #11, #15 |

## Goal
The History tab becomes a real log: past workouts grouped by week, a detail screen that reuses the receipt layout with editable sets and delete, and the stats that depend on it re-materialise after edits. Today's RECENT rows and the receipt's "Done" deep-link here.

## User stories
- As a lifter, I can scroll my training weeks, open any workout, fix a mistyped set, or delete a bogus workout.
- As a lifter, editing a past set updates my PRs, e1RM chart and "last performance" everywhere.

## Scope
**In:** `FeatureHistory` root (list), detail, edit sets sheet, delete with confirmation, week headers, empty state, routes from Today/receipt.
**Out:** exercise history/charts (F12), calendar picker (post-launch), notes/RPE per set (post-launch).

## Touches
- `LedgerKit/Sources/FeatureHistory/{HistoryRoot,HistoryStore,WorkoutDetailView,WorkoutDetailStore,EditSetsSheet,HistoryRoute}.swift`
- `LedgerKit/Tests/FeatureHistoryTests/**`
- `LedgerKit/Sources/LedgerAppKit/Routes.swift` (register `HistoryRoute.workout(WorkoutID)`)

## Domain changes
None. Uses `WorkoutRepository.workouts(in:)`, `.recent`, `.updateSets`, `.delete`, `.observeRecent`; `StatsQueries` for PR badges; `WeekCalendar` for grouping.

## Acceptance criteria
1. Given 12 finished workouts across 4 weeks, when History opens, then rows are grouped under week headers ("Sep 7 – 13", newest first) showing name, tag, weekday, duration "m:ss", volume "24,180 lb", and a PR count badge when > 0.
2. Given no workouts, then the empty state reads "No workouts yet" with a "Start today's session" action routing to Today.
3. Given a workout row tapped, then the detail shows the receipt layout: elapsed, sets done/total, volume, PR line, and target vs actual rows (rule 30 grouping).
4. Given "Edit sets" on a detail row, when a set's weight/reps are changed with steppers (exercise step, units from Settings) and saved, then `updateSets` is called, `e1rm_grams` is recomputed (F05), and the detail and list reflect the change without relaunch (observation).
5. Given "Delete workout", when confirmed in the destructive alert, then the workout disappears from the list and Today's stats tiles update.
6. Given a deep link `HistoryRoute.workout(id)` from Today RECENT or the receipt's "View session", then the detail opens with the History tab selected.
7. Given kg units, then all weights render in kg with kg steps.
8. Given Dynamic Type accessibility3, then rows wrap without truncating the workout name.

## Test plan
- Unit (FeatureHistoryTests): `HistoryStoreTests` (grouping by `WeekCalendar` bounds and `weekStart`, ordering, badge counts, empty state), `WorkoutDetailStoreTests` (receipt rows, edit → repository call, delete → route), `EditSetsTests` (step per units, min weight 0, min reps 1).
- Snapshot: `HistoryRoot` {populated, empty} × {light, dark} × {large, accessibility3}; `WorkoutDetailView` {with PRs, without}; `EditSetsSheet`.
- UI (LedgerUITests, nightly `History` suite): open list → detail → edit set → back → list reflects; delete flow.

## Non-functional
- List query paginates by 20 weeks; scroll stays 60 fps with 1,000 workouts (`.slow` test seeding via `Seeders`).
- Every row has an accessibility label "Upper A, Wednesday, 58 minutes, 24,180 pounds, 1 PR".

## Risks / unknowns
- Re-materialising PRs after an edit may change a later workout's PR badge — recompute PRs for the exercise from that date forward (F05 `updateSets` contract; add if missing).

## Definition of Done
Inherits `docs/engineering-standards.md` §12.

---
_Filled in by agents during delivery:_
- `F13-workout-history/implementation-notes.md`
- `F13-workout-history/test-findings.md`
- `F13-workout-history/review.md`

## Inputs from F05 (2026-10-01, slice S3)

1. **`updateSets` and `delete` keep the personal records right** (product decision #27; F05 records follow-up,
   which replaces S3's stale-records line). Inside the same write they detect the edited exercise's records
   again from that workout onward: a corrected typo (2,250 to 225) removes the false record, and a later workout
   gets the record it then deserves. `pr_count` follows. F13 does nothing for it, and criterion 4 ("editing a past
   set updates my PRs") holds through the repository. A damaged workout elsewhere in the history never fails an
   edit: the replay leaves it out and logs it (orchestrator decision on R-Q1).
   - A deload sets no record, but its sets count toward the bests, so a later record's "previous" can be a
     deload's set (contract clause `personalRecords`: 255 × 3 "over 250 × 5", the deload's). If the session log
     shows "over …", expect it (review R-N3).
2. **No query returns a workout's records, or their count, for the list badge** (criterion 1). `pr_count` is
   stored (and now always right) but nothing reads it, and `StatsQueries.personalRecords(exerciseID:)` is per
   exercise. Either call it for each exercise of a workout and filter by `workoutID`, or add
   `personalRecords(workoutID:)` (`idx_pr_workout` already serves it); the records follow-up did not.
3. **An unreadable workout is left out of the lists and is not counted.** `recent`, `workouts(in:)` and
   `observeRecent` log a workout this app version cannot read (damage, or a case a later version added) and
   return the rest; `workout(id:)` throws for it. It still takes a place of `recent`'s limit, so a page can be
   short. No call says how many were left out.
4. **Lists are newest first by when a workout started, then by id** (product decision #26); a limit below 1
   gives none; a range excludes its upper bound. A workout that crosses midnight belongs to the day and week it
   started in. A record's `achievedAt` is its workout's start, so it falls on the same day.
5. **A history read resets the live-only fields**: no `cursor`, `rest` or `programUpdates`, and `autoRest` true.
6. **Delete is a soft delete that a later materialisation reverses.** While a finished log is not compacted, a
   late envelope makes the host materialise again, which brings a deleted workout back and overwrites an
   `updateSets` edit with the log's state (F05 test-findings S3-Q4). History may edit or delete a workout only
   once its log is compacted (F17 "Inputs from F05").
7. `delete` keeps the misses the workout recorded and its `workout_health` row.
