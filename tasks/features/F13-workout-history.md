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

## Plan amendments (planner, 2026-10-28, against `main` @ 98b340d)

The planner's report, recorded as given. Where it and the brief above disagree, this section and the rulings after it win.

Paths are relative to `/Users/peterarevalo/Dev/workout-app/.claude/worktrees/F10-s7`. Line numbers are as of 98b340d.

## 1. Corrections to the brief

**Files, routes and design**

| # | The brief says | What is true now | Evidence |
|---|---|---|---|
| C1 | `HistoryRoot, HistoryStore, WorkoutDetailView, WorkoutDetailStore, EditSetsSheet, HistoryRoute`; register `HistoryRoute.workout(WorkoutID)` in `Routes.swift` | Every public entry view is a `…Root` that owns its store, so the detail is `WorkoutDetailRoot(workout:onRoute:)`. Screens are cases of `AppDestination`, so the new case is `AppDestination.workout(WorkoutID)`; `HistoryRoute` is the feature's route enum, mapped in a new `LedgerAppKit/Routes+History.swift` | `LedgerAppKit/Routes.swift:14-23`; `AppTabs.swift:46-71`; architecture.md:188-209; F12 C1–C3 |
| C2 | The receipt's "Done" and "View session" deep-link here | The receipt's "Done" routes `.saved`, which selects **Today** (F10 criterion 10), and F13 leaves it there. "View session" is Today's logged card, not the receipt. The routes that wait for F13 are three: Today's RECENT rows and "View session" (`TodayRoute.openWorkout`), and an exercise history's session-log entry (`LibraryRoute.openWorkout`). All three select the History tab today | `Routes+Workout.swift:12-14`; `TodayPresentation+Card.swift:187`; `TodayPresentation+Recent.swift:39`; `Routes+Today.swift:16-19`; `Routes+Library.swift:11-14` |
| C3 | History tab | Still a `PlaceholderScreen` (`AppTabs.swift:38-39`). Replacing it needs sanctioned edits of `AppTabsTests.swift:50` (the "History" heading), `TodayRouteMappingTests.swift:59-67` and `LibraryRouteMappingTests.swift:39-47`. `Apps/LedgerUITests/TabsAdversarial.swift:11` finds the tab by `history.title`, so the list's title keeps that identifier | as cited |
| C4 | Module setup | `FeatureHistory` is a stub (`FeatureHistory.swift` plus a placeholder test). The target has no `resources` (`Package.swift:158`). It is missing from `snapshotTestTargets` (`Package.swift:67-70`), from `required` (`scripts/coverage-thresholds.json:15`) and from `PreviewScan.registeredModules` (`LedgerTestSupport/Previews/PreviewScan.swift:9-12`). It **is** already in both test plans (`TestPlans/PR.xctestplan:122`, `Nightly.xctestplan:122`). S1 adds the rest | as cited |
| C5 | Design refs: `Session receipt` (detail) and `Today` RECENT rows | Neither prototype has a workout list or a workout detail. The "History" screen in both is the exercise history (`Ledger.dc.html:688`, `Ledger v2.dc.html:292`), which F12 built. Spec §9 lists "Workout history list" as not designed; decision #11 gives only the structure. So the list borrows Today's RECENT row and the detail borrows the receipt. Q6 and Q7 settle what the brief guessed | spec §2.1, §9; decision #11 |
| C6 | (implied) a navigation bar on the list | Tab roots hide the navigation bar (`AppTabs.swift:50, 74-83`, `tabRootChrome`), so the list draws its own title, as Library does. The pushed detail keeps its bar, so "Edit" is a toolbar item, as on F12's exercise history | `ExerciseHistoryRoot.swift` toolbar |

**Queries and repository API**

| # | The brief says | What is true now | Evidence |
|---|---|---|---|
| C7 | The list uses `workouts(in:)`, `.recent` and `.observeRecent` | All three load whole workouts with every set. `observeRecent(limit:)` emits only when the newest `limit` change, so an edit or delete of an older workout is never reported. The `workout` row already stores the totals "for queries that do not load the sets" (`volume_e7g_reps`, `done_sets`, `total_sets`, `pr_count`), and `idx_workout_started` orders them. **F13 adds a list query over the `workout` row alone, with an observation of every workout (N1, N2)** | `Repositories.swift:121-136`; `WorkoutRecords.swift:23-24`; `Migrations.swift:126-146`, `:17` |
| C8 | `StatsQueries` for PR badges | No query returns a workout's records or their count (the brief's own "Inputs from F05", item 2). `pr_count` is kept right by `RecordReplay` and read by nothing. The list reads `pr_count` (C7). The detail needs the workout's records, live: a new observation (N8) | `RecordReplay.swift:194-213`; `Repositories.swift:185-188` |
| C9 | The detail reflects an edit "without relaunch (observation)" | `workout(id:)` is a one-off read; nothing observes one workout | `Repositories.swift:118-120` |
| C10 | Criterion 4: "`e1rm_grams` is recomputed (F05)"; risk: "recompute PRs … add if missing" | The column is `e1rm_e7g`. `updateSets` recomputes it, the totals and the records from that workout onward, in one transaction (decision #27). Nothing to add, and the risk is closed | `Migrations.swift:175`; `GRDBWorkoutRepository.swift:105-139` |
| C11 | `updateSets` | It replaces the sets of **one** exercise. A sheet that edits several exercises would be several transactions, each replaying records. Flag A4 | `Repositories.swift:126-130` |
| C12 | Inputs item 6: a late materialisation can undo a delete or an edit, so History may edit only compacted workouts | On `main` the host drops the log inside the save's own transaction, and never saves a log holding rows it cannot read (`incompleteLog`). So a stored workout has no log on this device, and F13 needs no guard. The exposure left is F17's: a watch envelope arriving after a History edit or delete. That is R1, an input for F17 | `LedgerSync/LocalWorkoutSessionActor+Recovery.swift:150-180` |
| C13 | Grouping with `WeekCalendar` | `WeekCalendar.week(containing:)` gives the stats week for `settings.weekStart`. The initializer also needs a `startDate`, which a stats week does not use (Today passes the program start, or today: `TodayHistory.swift:31-41`) | `WeekCalendar.swift:36, 82` |

**Numbers, wording and criteria**

| # | The brief says | What is true now | Evidence |
|---|---|---|---|
| C14 | Criterion 4: steppers "(exercise step, units from Settings)" | `WorkoutExercise.step` is a mass in the units the workout was logged in. Five pounds read in kilograms steps 83.9 to 86.2. F11's start-load stepper already solves this: the next multiple of the step in the lifter's units, on the side tapped. Q5 | `WorkoutExercise.swift:17`; `DayEditing+Fields.swift:59-75` |
| C15 | Criterion 3: the detail "shows the receipt layout" | `ReceiptLayout` is shared (LedgerDesign), but the model that fills it and its ten strings live in FeatureWorkout, which FeatureHistory cannot import. The rows' text is the Domain's (`ReceiptRow(exercise:units:)`, public). Flag A3 | `FeatureWorkout/WorkoutPresentation+Receipt.swift`; `WorkoutCopy+Receipt.swift`; `LedgerDomain/Model/WorkoutSummary.swift:47-70` |
| C16 | Criterion 4: "Edit sets" on a detail row | Since F12 S3 a receipt row is a button that opens the exercise's history (N18). The same row cannot also open an editor. Q2 | `ReceiptLayout.swift:8-12`; `WorkoutPresentation+Receipt.swift` `rowActions` |
| C17 | Criterion 1: duration "m:ss" | Today's RECENT row reads "Mon · 58 min · 24,180 lb", and the receipt's tile "24:22". Q6 | `TodayPresentation+Recent.swift:18-35` |
| C18 | Criterion 2: "Start today's session" routing to Today | On a rest day, or after today's session, there is no session to start. Q7 | `TodayPresentation+Card.swift` |
| C19 | Criterion 5: "Today's stats tiles update" | No observation reports an older workout's delete, but Today re-reads everything at each `run()`, which restarts when the tab comes back. Its session stream also restarts with no workout, so a deleted workout can't come back through `withFinishedSession` (R4). Nothing in FeatureToday changes. The Library (`observeLibraryStats`, N20) and the exercise history (`observeExerciseSessions`) already follow every workout | `TodayStore.swift:97-102`; `TodayPresentation.swift:163-170`; `Repositories.swift:198-208` |
| C20 | Non-functional: the list "paginates by 20 weeks" | With C7's row-only query, 1,000 workouts are one indexed read of about 1,000 short rows. Paging would add a cursor, a "load more" state and their tests for no measured need. Flag A2 | — |
| C21 | Test names; the nightly "History" UI suite | The convention is `subject_condition_expectation`. `HistoryVoiceOverAdversarial` is taken (F12's exercise history), so the new suite is `WorkoutHistory.swift` | testing-strategy.md:440-442; `Apps/LedgerUITests/` |

## 2. Slices

Three sequential pull requests, each cut from `main` after the previous one has merged.
- S2 needs S1's module, copy and destination. S3 needs S2's detail root and store.
- **How lines are counted:** as in F12. Non-blank, non-comment Swift under `LedgerKit/Sources` and `Apps`; string catalogs, `LedgerTestSupport` and the UI-test targets are excluded; LedgerFakes and `*+Previews.swift` are counted.
- **Calibration:** F12's three slices measured 933, 826 and 702 net. Their stores came in 150–220 lines, presentations 120–195, copy 75–185, previews 60–110.
- **Stop rule:** each slice stops and reports past about 950 lines.
- **Every PR description says it is over the 500-line target**, and names the split it considered (standards §10:512-515).

### S1: the History tab, the list of workouts (about 840 lines)

**Scope**
- The list query and its observation (Domain, GRDB, in memory, stub).
- The pure week grouping.
- A spoken-weight helper that gets the unit's plural right (A6).
- FeatureHistory: module setup, copy, presentation, store, root and views of the list.
- The History tab draws `HistoryRoot`.
- `AppDestination.workout(WorkoutID)` draws a `PlaceholderScreen` until S2.
- The three waiting routes go to `.workout(id)` as Q1 settles.

**Criteria owned**
- **1 (restated per C17 and Q6):** rows are grouped under stats weeks of `settings.weekStart`, newest first. A header reads "Sep 7 – 13", or "Aug 31 – Sep 6" across a month, with the year added for a week outside the current year. Each row is the workout's name and "Wed · 58 min · 24,180 lb" (weekday of the start, whole minutes, volume in the lifter's units), plus a "1 PR" badge when `prCount > 0`. The fixture is 12 workouts over 4 weeks.
- **2 (restated per Q7):** with no workout, the empty state with its action. The action emits `HistoryRoute.today`, which selects the Today tab.
- **6, the route part (restated per Q1):** a row emits `.workout(id)`. Today's RECENT, "View session" and a session-log entry open `.workout(id)` as Q1 says.
- **7, the list part:** volume in kg; a change of units redraws without navigating.
- **8, the list part:** at accessibility3 a row wraps and never truncates the name.

**New criteria**
- **N1. One list query.**
  - `WorkoutRepository.historyEntries()` returns one `HistoryEntry` per stored workout, read from the `workout` row alone: id, name, tag, deload flag, start, elapsed, volume, done and total sets, and `prCount`.
  - Order is newest start first, then id (decision #26).
  - Contract clauses on in-memory and GRDB: each entry equals the same fields computed from `workout(id:)`'s state; `prCount` equals the stored records of that workout; a deleted workout is absent; an edit's new volume and `prCount` show, including a later workout whose record the edit gave or took away.
- **N2. Live list.**
  - `observeHistoryEntries()` emits after a finish, an edit or a delete of any workout, the oldest included. It does not emit for a live set tap, which writes `workout_event` only (contract clause).
  - The store follows it and `settings.observe()` (units; a week-start change regroups the list, F14 criterion 7), with one rebuild per change, as `TodayStore` does.
- **N3. Weeks.** `HistoryWeeks.group(_:weekStart:calendar:)` is pure and lives in the Domain. Tests cover a Sunday start, a week across daylight saving, and a workout started at 11:30 pm on the week's last day (it stays in that week).
- **N4. Budgets** (nightly `.performance`):
  - `historyEntries()` over 1,000 workouts: under 20 ms at the 95th percentile.
  - The list model for 1,000 entries: under 30 ms.
- **N5. Conventions:** `FeatureHistorySourceTests` checks the F11/F12 conventions, and that every lookup is in `HistoryCopy*.swift`.
- **N6. Orange:** none on the list (Q6's badge is ink).
- **N7. VoiceOver:**
  - Each row is one button reading "Upper A, Wednesday, 58 minutes, 24,180 pounds, 1 PR". Units are plural-correct through A6, never "1 pounds".
  - A week header is a heading.
- **N10, the list part:** a workout whose own row this version cannot read is logged and left out. One whose exercises or sets are damaged is listed (its row reads), and its detail says so (S2). Flag A5.

**Files and estimates**

| File | Lines |
|---|--:|
| `LedgerDomain/Model/HistoryEntry.swift` | 25 |
| `LedgerDomain/Protocols/Repositories.swift`: `historyEntries()`, `observeHistoryEntries()` | 6 |
| `LedgerDomain/Rules/HistoryWeeks.swift` | 35 |
| `LedgerDomain/Units/SpokenWeight.swift` (A6: `Measurement`, wide width, the injected locale) | 20 |
| `LedgerPersistence/Repositories/GRDBWorkoutRepository+History.swift`: fetch, row decoding, observation | 50 |
| `LedgerFakes/InMemoryWorkoutRepository.swift` (+25), `LedgerDependencies/…/UnimplementedStores.swift` (+6) | 31 |
| `FeatureHistory/HistoryRoute.swift` | 12 |
| `HistoryCopy.swift`: title, empty state, week-range format, row meta, counted PR badge, spoken row, failed state | 110 |
| `HistoryInput.swift`, `HistoryModel.swift`, `HistoryAction.swift` | 70 |
| `HistoryPresentation.swift` | 120 |
| `HistoryStore.swift`, `HistoryStore+Sources.swift` | 150 |
| `HistoryRoot.swift` | 45 |
| `Views/HistoryScreen.swift`, `HistoryPage.swift`, `HistoryRow.swift`, `WeekHeader.swift` | 110 |
| `Views/History+Previews.swift`, over `Seed.preview()` | 70 |
| `LedgerAppKit`: `Routes.swift` (+`.workout`), `Routes+History.swift`, `Routes+Today.swift`, `Routes+Library.swift`, `AppTabs.swift`, `MainRoot.swift` | 30 |
| `Package.swift` (resources); placeholder `FeatureHistory.swift` and its test removed | about 0 |
| **Total** | **about 840** |

**Tests**
- Contract: `WorkoutRepositoryContract+History` holds N1's and N2's clauses, on in-memory and GRDB.
- Domain: `HistoryWeeksTests` at 100%; `SpokenWeightTests` (1 pound, 1.5 pounds, 2 kilograms, `ar_EG` digits).
- Unit: `HistoryPresentationTests` (weeks, headers across a month and a year, meta, badge 0/1/n, lb and kg) and `HistoryCopyTests`.
- Store: `HistoryStoreTests` covers:
  - the first model;
  - an older workout edited;
  - a delete;
  - units;
  - the week start;
  - a double tap giving one route;
  - an ended observation giving the failed state.
- Hosted: `HistoryRootTests`, `HistoryAccessibilityTests`, `HistoryLayoutTests`. Every size sweep goes through `TestSweep.sizes(…)`; bold and right-to-left go through `TestSweep.subset`. No sweep reads a swept list's count.
- Snapshots: {populated, empty} × {light, dark} at `.large`, plus populated at `.accessibility3` in light and dark: 6 references.
- App: `HistoryRouteMappingTests`, plus the sanctioned edits in C3.
- Performance: `HistoryQueriesPerformanceTests`, gated by `.enabled(if: TestLane.runsSlowTests)`.
- Nightly UI: `WorkoutHistory.swift` saves a sample workout, opens History and finds the row.

**Needs:** nothing. Merge first. Q1, Q6 and Q7 are its product inputs.

### S2: the workout detail and delete (about 790 lines)

**Scope**
- The one-workout observation with its records.
- `WorkoutDetailRoot`, its store, presentation and views: the receipt layout in the lifter's units, under a header with the date and name.
- Rows open the exercise's history.
- "Delete workout" with its alert.
- The detail closes when its workout is gone.
- `AppDestination.workout` draws the root.

**Criteria owned**
- **3 (restated per C15 and C16):**
  - The detail shows TIME, SETS and LB MOVED (KG MOVED), the records line from the workout's stored records, and LOGGED rows by rule 30, in the lifter's units (Q5).
  - The header shows "Wednesday, September 16" over the name.
  - A row emits `HistoryRoute.exercise(id)`, which pushes the exercise's history on the same stack.
- **5:** "Delete workout" asks in a destructive alert (Q8). Confirmed, `delete(id:)` is called once and the detail closes (`HistoryRoute.closeWorkout(id)` pops it only if it is on top, as `.closeDay` does). The list loses the row through N2. Today's tiles change at its next run (C19), and the Library and exercise history through their observations.
- **6, the screen part:** the detail opens on the stack Q1 names.
- **7, the detail part:** weights in kg.
- **8, the detail part:** at accessibility3 the receipt stacks, as `ReceiptLayout` already does.

**New criteria**
- **N8. Live detail.**
  - `WorkoutRepository.observeWorkout(id:)` emits a `RecordedWorkout?` (the state and its records) now, then after every change to that workout or its records. That includes a change made by an edit of an earlier workout.
  - It emits `nil` once the workout is deleted, and the detail then closes.
  - Contract clauses cover this on in-memory and GRDB.
- **N9. Delete.**
  - A double tap deletes once.
  - A failure shows an alert and keeps the screen.
  - Cancel in the alert does nothing.
  - A delete made elsewhere closes the screen.
- **N10, the detail part:** a workout that can't be read (the stream ends, or its read throws) shows "This workout can't be read." with Delete still offered.
- **N13. Receipt parity:** for the same finished workout, records and units, the detail's `ReceiptLayout.Model` equals F10's receipt model, row for row and string for string. The test is `ReceiptParityTests` in LedgerAppKitTests, which imports both features (A3).
- **N14. Dates:** formatted through `Date.FormatStyle` with the injected locale, calendar and time zone, as `WorkoutPresentation+Receipt.swift` does.
- **N6, the detail part:** the receipt's own orange (the TIME label and the records line), as F10 shipped it. "Delete workout" is ink, not red, until the alert.

**Files and estimates**

| File | Lines |
|---|--:|
| `LedgerDomain/Model/RecordedWorkout.swift`; `Repositories.swift` (+`observeWorkout(id:)`) | 20 |
| `GRDBWorkoutRepository+History.swift` (+one workout with its records, `idx_pr_workout`) | 45 |
| In-memory (+25), stub (+3) | 28 |
| `FeatureHistory/WorkoutDetailRoot.swift` (the alert, the task, the route) | 60 |
| `WorkoutDetailStore.swift` | 170 |
| `WorkoutDetailModel.swift` | 50 |
| `WorkoutDetailPresentation.swift` (the receipt in the lifter's units, the header, the gone and unreadable states) | 120 |
| `HistoryCopy+Detail.swift`: the receipt's ten keys again (A3), delete, its alert, failure, unreadable | 110 |
| `Views/WorkoutDetailScreen.swift`, `WorkoutDetailPage.swift` | 85 |
| `Views/Detail+Previews.swift` | 60 |
| `HistoryRoute.swift` (+`exercise`, `closeWorkout`) | 5 |
| `LedgerAppKit/AppTabs.swift`, `Routes+History.swift` | 15 |
| **Total** | **about 790** |

**Tests**
- Contract: N8's clauses.
- Unit: `WorkoutDetailPresentationTests` (lb and kg, with and without records, a skipped exercise's "—", a workout over an hour "1:01:05") and `HistoryCopyTests` (+detail).
- Store: `WorkoutDetailStoreTests` covers:
  - the model;
  - an edit observed;
  - a later workout's record changed by an edit of an earlier one;
  - delete once;
  - delete failure;
  - deleted elsewhere;
  - unreadable;
  - the row route delivered once.
- Hosted, through `TestSweep`: `WorkoutDetailAccessibilityTests` and `WorkoutDetailLayoutTests`.
- Orange: `WorkoutDetailOrangeAuditTests`.
- Snapshots: {with records, without, kg} × {light, dark} at `.large`, plus "with records" at `.accessibility3` in light and dark: 8 references.
- App: N13's `ReceiptParityTests`; mapping of `.exercise` and `.closeWorkout`.
- Nightly UI: `WorkoutHistory.swift` + list → detail → row → exercise history → back; delete → the list loses the row → Today's tile changes (R4).

**Needs:** S1. Q1, Q5 and Q8 are its product inputs.

### S3: edit a past workout's sets (about 690 lines)

**Scope**
- The Domain rule for stepping a past set.
- The batched `updateSets` (A4).
- The edit sheet: its store, presentation and views.
- "Edit" in the detail's toolbar.

**Criteria owned**
- **4 (restated per C10, C11, C14, Q2–Q5):**
  - "Edit" opens a sheet with every exercise of the workout and its logged sets, each with a weight and a reps stepper.
  - "Save" writes every changed exercise in one call. The repository re-detects records (decision #27).
  - The detail and the list show the change without navigating (N2, N8). The Library, the exercise history and Today follow (C19).
- **7, the sheet part:** kg values and kg steps.
- **8, the sheet part:** at accessibility3 each `StepperField` stacks its buttons (as it already does), and the sheet scrolls under pinned chrome.

**New criteria**
- **N11. Edit rules** (`LedgerDomain/Rules/SetEditing.swift`, 100% coverage):
  - Only done sets are shown and changed. Sets not done, every set's id, kind, order and `doneAt` pass through untouched.
  - The weight steps to the next multiple of the step on the side tapped, as F11's rule 6 does (that helper moves to `Weight` and both callers use it). The step is the exercise's own when the workout's units are the lifter's units, else `equipment.defaultStep(in:)` for the lifter's units. The weight is never below 0.
  - Reps step by one through `Reps(clamping:)` and are never below 1.
- **N12. Saving.**
  - "Save" is disabled until something changed.
  - A save calls the repository once. A second tap while it runs does nothing.
  - A failure shows a line and keeps the sheet up.
  - While saving, the sheet can't be swiped away (`interactiveDismissDisabled`, as `FinishSheet` and `CreateExerciseSheet` do).
  - A workout deleted meanwhile (`missingRow`) says so and closes the sheet and the detail.
  - A cancelled task writes nothing, or all of it (the write is one transaction).
- **N15. VoiceOver:** each stepper reads "Set 2 weight, 185 pounds" and "Set 2 reps, 5", adjustable. An exercise name is a heading.
- **N6, the sheet part:** "Save" is the sheet's one orange.

**Files and estimates**

| File | Lines |
|---|--:|
| `LedgerDomain/Rules/SetEditing.swift`; `Weight` next-multiple helper (net, moved from `DayEditing+Fields.swift`) | 65 |
| `Repositories.swift`: `updateSets(_ sets: [WorkoutExerciseID: [LoggedSet]], of workout: WorkoutID)`; the per-exercise call becomes a one-entry default | 10 |
| `GRDBWorkoutRepository.swift` (the existing body generalised; one replay for every touched exercise) | 25 |
| In-memory (+20), stub (+3) | 23 |
| `FeatureHistory/EditSetsStore.swift` | 140 |
| `EditSetsModel.swift` | 50 |
| `EditSetsPresentation.swift` | 100 |
| `HistoryCopy+Edit.swift` | 80 |
| `Views/EditSetsSheet.swift`, `EditSetsPage.swift` (on `SheetChrome` and `StepperField`, both in LedgerDesign) | 110 |
| `Views/Edit+Previews.swift` | 50 |
| `WorkoutDetailRoot` and its store: the toolbar's "Edit" and the sheet | 30 |
| **Total** | **about 685** |

S3 sits under the 700-line band by its nature, as F12 S3 did. Folding it into S2 would take S2 past 1,000. If the orchestrator rules A6's Library adoption in, it lands here (about 20 lines).

**Tests**
- Domain: `SetEditingTests` at 100%. They include a pound workout edited in kg, a weight between multiples, zero, reps at 1, and a property test checking that only done sets' weight and reps change.
- Contract: the batched `updateSets` covers:
  - all or nothing (a bad id in the second entry writes nothing);
  - one replay;
  - one emission of N2 and of N8;
  - the one-entry call equals the old call.
- Store: `EditSetsStoreTests` covers:
  - the draft;
  - steps in lb and kg;
  - Save disabled with no change;
  - one save on a double tap;
  - failure;
  - `missingRow`;
  - cancellation.
- Hosted, through `TestSweep`: `EditSetsAccessibilityTests` and `EditSetsLayoutTests`.
- Snapshots: {unchanged, changed, error} × {light, dark} at `.large`, plus "changed" at `.accessibility3`: 7 references.
- Performance: the existing History-write budget (architecture §15, 250 ms) gains a batched edit of three exercises.
- Nightly UI: `WorkoutHistory.swift` + detail → Edit → step a weight → Save → the detail and list show it.

**Needs:** S2. Q2–Q5 are its product inputs.

### CI time (the PR plan)

- **F12 as measured:** its three slices added about 6.1, 4.0 and 1.1 s of PR-sweep test time (F12 notes, "PR-sweep seconds"), far under its plan's 30–40 s.
- **F13 estimates** (simulator, `TEST_RUNNER_LEDGER_SWEEP=pr`, 40 seeds):
  - S1: about 6–9 s. The list's accessibility and layout sweeps are about 90 cases, plus 6 references.
  - S2: about 5–8 s.
  - S3: about 4–7 s. A sheet of steppers sweeps more elements per case.
  - The contract clauses add about 1–2 s per slice on GRDB.
  - Performance suites are nightly only.
- **On the runner**, at 2–3×: about 15–30 s per PR, under 90 s once all three land.
- **Build:** each slice adds about 0.8k lines to compile, perhaps 10–30 s.
- **Budget:** the PR test step runs 1,900–2,400 s against the 4,500 s deadline (`docs/ci-cd.md:132-136`), so F13 fits.
- Each slice measures and writes its seconds in the notes (as F12's R6 did).

## 3. Open questions for Pete

Each will be built to its recommended default until Pete answers.

1. **Where a past workout opens.** You tap a workout on Today (RECENT, or "View session"), or a session in an exercise's history.
   - A: it opens right there, on the tab you are on. "Back" returns you to where you tapped, as exercise history already does.
   - B: the app switches to the History tab and opens it there (what the brief wrote). "Back" leads to the History list, not where you were.
   - Recommended: A. It is how exercise history already behaves, and you never lose your place.
2. **How you fix a set.**
   - A: an "Edit" button on the workout opens all of its logged sets in one sheet. Tapping an exercise still opens its history, as on the receipt.
   - B: tapping an exercise opens its sets to edit. Its history is then only reachable from the Library.
   - Recommended: A.
3. **What can be edited in a past workout.**
   - A: the weight and reps of sets you logged.
   - B: also remove a logged set, or log a set you skipped.
   - Recommended: A for now. It covers "I typed it wrong", and a bogus workout can be deleted whole. B can come later without undoing A.
4. **Does fixing a past workout change your program?** Today the program holds or raises a load based on whether you hit your sets when you saved.
   - A: no. A fix updates your records, charts and stats, but not the program's hold-or-advance. Change a load in the Program tab if you need to.
   - B: yes. Re-judge that week for the active program.
   - Recommended: A. B can change next week's loads behind your back, and it can't be judged once the program has been edited since.
5. **Units on old workouts.** Say you logged in pounds and now use kilograms.
   - A: History shows everything in your current units. The "−"/"+" buttons move to the next whole kilogram step (83.9 kg → 85 kg), as the Day editor's start load does.
   - B: each workout shows and edits in the units it was logged in.
   - Recommended: A, one unit everywhere you look.
6. **How a workout looks in the list.**
   - A: like Today's RECENT row: "Upper A" over "Wed · 58 min · 24,180 lb", with a small "1 PR" badge in the normal ink colour.
   - B: the brief's: the day's tag, the time as "58:12", and an orange badge. Several orange badges on one screen break the "orange once per screen" rule.
   - Recommended: A.
7. **The empty History tab.**
   - A: "No workouts yet." / "Finish a workout and it shows up here." with a "Go to Today" button.
   - B: the brief's "Start today's session" button. That reads wrong on a rest day, or once today's workout is done.
   - Recommended: A.
8. **Deleting a workout.**
   - A: the alert "Delete this workout?" / "It's removed from your history, records and stats. This can't be undone." with "Delete" and "Cancel".
   - B: no alert, with "Undo" for a few seconds instead.
   - Recommended: A. One alert is the app's pattern (deleting a day in the Day editor), and Undo would need new machinery. Once Apple Health is connected (F16), what a delete does there is F16's question.

## 4. Architecture flags

- **A1. New Domain API.** No migration and no ADR: the protocols are F05's to extend, and `idx_workout_started` and `idx_pr_workout` serve every read.
  - `HistoryEntry`, `historyEntries()` and `observeHistoryEntries()` (S1).
  - `RecordedWorkout` and `observeWorkout(id:)` (S2).
  - The batched `updateSets` (S3).
  - **Orchestrator ruling needed:** `observeWorkout(id:)` returns records, which today only `StatsQueries` returns. I recommend `WorkoutRepository`: a workout's records are part of the workout as stored, and its `delete` already speaks of them. One observation then covers the workout and its records, with no store-side join of two streams.
- **A2. No pagination** (C20). One read of the `workout` table, budgeted by N4 (1,000 workouts under 20 ms). The query keeps no cursor; a `limit:` can be added later without changing callers' types. **Ruling needed:** accept dropping the brief's 20-week paging.
- **A3. The receipt's model and copy in two features** (C15).
  - Recommended: FeatureHistory has its own copy of the ten receipt keys and its own model builder (about 70 lines), over the shared `ReceiptLayout` and the Domain's `WorkoutEngine.summary` and `ReceiptRow`. N13's parity test in LedgerAppKitTests pins the two equal.
  - The alternative, a shared module with its own catalog, adds a package-graph edge and a module for about 70 lines.
  - **Ruling needed.**
- **A4. One write for a multi-exercise edit** (C11).
  - Recommended: generalise `updateSets` to a map of exercises in one workout. That gives one transaction, one record replay from that workout onward, and one emission per observer. The per-exercise call stays as a one-entry default, so F05's clauses keep passing.
  - The alternative, a loop of per-exercise calls, can leave a half-saved workout, with records replayed once per exercise.
  - **Ruling needed.**
- **A5. A damaged workout in the list** (N10). `recent` and `workouts(in:)` leave out any workout this version cannot read (brief Inputs item 3). The row-only query can list one whose sets are damaged, and its detail then offers Delete. That is the lifter's only way to see and remove it. **Ruling needed:** accept this narrower rule for `historyEntries()`, written into its contract.
- **A6. Spoken weights.**
  - F12's "PR 1 pounds" and "Up 1 pounds" follow-up comes from putting a formatted `%@` into a fixed "pounds" key. F13 speaks weights in every row and stepper.
  - S1 adds `Weight`/`Volume` spoken text through Foundation's `Measurement` (wide unit, injected locale), which pluralises correctly in every language.
  - Moving FeatureLibrary's keys onto it stays the queued follow-up: about 20 lines plus sanctioned edits of `LibraryCopyTests`. I recommend not absorbing it unless the orchestrator wants it in S3.
- **A7. LedgerDesign:** no new component. `ReceiptLayout` (with `onRow`), `SheetChrome`, `StepperField`, `EmptyState`, `HairlineRow` and `PillButton` cover every screen. No new token.
- **A8. Project file and test plans:** none. `FeatureHistoryTests` is in both plans. UI tests go in `Apps/LedgerUITests` (a synchronized folder), and the PR plan selects `Smoke` only. Performance suites gate themselves by trait.
- **A9. Sanctioned edits of others' tests, listed in the notes:**
  - `AppTabsTests.swift:50` (S1).
  - `TodayRouteMappingTests.swift:59-67` (S1).
  - `LibraryRouteMappingTests.swift:39-47` (S1).
  - `TabsAdversarial.swift` only if the title's identifier changed (it shouldn't).
  - `DayEditing` tests if the next-multiple helper's move touches them (S3).
- **A10. Coordination with F14 (Settings), planned in parallel.** Not designed here; named so the second to merge expects it.
  - **Shared one-line edits:** both features turn a stub module into a real one, and so edit the same lines:
    - `Package.swift`'s target lines 158–159 (resources);
    - `snapshotTestTargets`;
    - `coverage-thresholds.json` `required`;
    - `PreviewScan.registeredModules`;
    - `AppTabs.swift` (History's tab line vs `.settings`'s destination in `screen(for:)`);
    - `MainRoot.tabs` (each adds an `on…Route`);
    - `AppTabsTests`.
    The conflicts are trivial, and whichever lands second rebases.
  - **Units and week start:** F13 follows `settings.observe()`, so F14's switches reach History live. F14's criterion 1 ("History renders kg") and criterion 7 ("History grouping changes") assert F13's screens. Whichever lands second writes that cross-feature test.
  - **"Delete all data":** it replaces the router (`MainRoot` → onboarding), so History needs nothing. An open detail whose workout vanishes closes itself anyway (N8).
  - **CSV export:** F14 reads `[WorkoutState]`. `historyEntries()` has no sets, so it is not a substitute. There's no overlap to share.

## 5. Risks

- **R1. Late envelopes after an edit or delete (F17).** On this device a stored workout has no log (C12). Once a watch syncs, an envelope arriving after a History edit or delete would rebuild and re-materialise the log's state over the edit, or bring the deleted workout back. **Input for F17:** a finished workout that History has edited or deleted must not be re-materialised from a late envelope without a rule; tombstone or edit-wins is F17's decision. F13 adds no guard.
- **R2. Apple Health.** A delete in History does not touch a Health workout (F16 is not built). Recorded for F16, with Q8's note.
- **R3. Sync of deletes and edits (F28).** Soft deletes and `updated_at` already carry them.
- **R4. A deleted workout coming back on Today.**
  - `withFinishedSession` merges the session's last finished workout into RECENT and the week. If Today's task kept running across a delete, a just-saved workout deleted in History could reappear there.
  - It doesn't today: the tab's task restarts, and a new session stream starts with no workout (`WorkoutSessionClient.finish`'s contract).
  - Q1's A pushes the detail on Today's own stack, where Today's root is hidden and its task cancelled. S2's nightly UI test pins it: delete from a detail pushed on Today → back → no row.
- **R5. Observation cost** (the `bestSets` follow-up). F13 does not make it worse.
  - While History is on screen the Library's task is not running (a hidden tab's task is cancelled; TodayStore relies on the same), so an edit pays no `observeLibraryStats` re-fetch. The about 20 ms is paid once, when the Library comes back, as today.
  - F13's own observers re-read the `workout` table (about 1,000 short rows) and one workout with its records: a few ms per write.
  - S3's performance test measures a batched edit with N2 and N8 running against the 250 ms History-write budget.
  - The `bestSets` scan stays the queued follow-up.
- **R6. Accessibility sizes.** At AX5 a 25-set workout is 50 stepped fields; each `StepperField` stacks its buttons, so the sheet is long. It is pinned chrome over a scroll view, as the picker and `CreateExerciseSheet` are. The week header's interval format can wrap; it is a heading with `fixedSize(vertical:)`.
- **R7. Week headers across locales.** Use `Date.IntervalFormatStyle` with the injected locale, calendar and time zone, and the inclusive last day (upper bound − 1 day, computed in the calendar, not by subtracting 86,400 s). Test right-to-left and `ar_EG` digits.
- **R8. Slice size.** S1 is a store slice, and F12 S1 ran 933 net against 790 planned. Stop at about 950. S1's split point: the query, the weeks, the spoken helper and the presentation first (about 400, nothing on screen), then the store, views and app (about 440).
- **R9. Records moving on other rows.** An edit can add or remove a record on a later workout. Its list badge follows through `pr_count` on the `workout` row, which N2 tracks. `RecordReplay` writes `pr_count` only where it changed, so an edit that moves nothing emits nothing new for other rows.
- **R10. Fixture realism.** Keep the criteria fixtures (12 workouts over 4 weeks; a lb workout read in kg) in LedgerTestSupport (not counted), and previews on `Seed.preview()`, so LedgerFakes grows only by the new in-memory methods.

**Follow-ups checked against F13**
- `walk_panelAndHaptics` de-flake: not touched.
- "Up 1 pounds" plural: touched in kind; F13 avoids it with A6. F12's keys stay a follow-up unless ruled into S3.
- Folding `ExerciseSearch.key`: not touched; F13 searches and names nothing.
- `bestSets` scan cost: not made worse (R5).
- The name field at accessibility sizes: not touched; F13 has no text field.

### Critical files for implementation
- `LedgerKit/Sources/LedgerDomain/Protocols/Repositories.swift` and `LedgerKit/Sources/LedgerPersistence/Repositories/GRDBWorkoutRepository.swift`
- `LedgerKit/Sources/LedgerDesign/Components/ReceiptLayout.swift` and `LedgerKit/Sources/FeatureWorkout/WorkoutPresentation+Receipt.swift` (the model to mirror)
- `LedgerKit/Sources/FeatureLibrary/ExerciseHistoryStore.swift` and `LedgerKit/Sources/FeatureToday/TodayStore.swift` (the store pattern)
- `LedgerKit/Sources/LedgerAppKit/AppTabs.swift`, `Routes.swift`, `Routes+Today.swift`, `Routes+Library.swift`
- `LedgerKit/Sources/LedgerDomain/Programs/DayEditing+Fields.swift` (the next-multiple step to share)

## Rulings before G1 (orchestrator, 2026-10-28)
- **Pete's questions Q1–Q8** are built to the planner's recommended defaults until he answers; each default lives in one place.
- **A1** `observeWorkout(id:)` on `WorkoutRepository`: yes. **A2** no paging, one read of `workout` with a nightly budget: yes.
- **A3** FeatureHistory's own copy of the receipt strings and model builder, pinned equal to F10's by a parity test: yes (a new shared module costs more than ~70 pinned lines).
- **A4** one multi-exercise `updateSets` write (one transaction, one record replay): yes. **A5** the list's narrower damaged-sets rule: yes.
- **A6** the spoken-weight helper lands in S1; moving FeatureLibrary's strings onto it (the "Up 1 pounds" follow-up) is ruled INTO S3.
- **A10 / F14 coordination:** F13 and F14 run as parallel lanes. Neither stacks on the other; whichever merges second merges `main` in and takes the other's one-line edits. F14's criteria that assert History's screens are written by whichever lands second.
