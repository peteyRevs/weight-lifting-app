# F12 — Library and Exercise history

| | |
|---|---|
| Milestone | M1 |
| Status | in progress (S1) |
| Depends on | F02, F03, F05, F06, F07 |
| Branch | `feat/F12-library-history` |
| Design refs | `design/prototype/Ledger v2.dc.html` → screen labels: `Library`, `Exercise history`; `design/prototype/Ledger.dc.html` → `Library`, `Exercise history` (behaviour, tags) |
| Spec refs | `docs/product-spec.md` §3.8, §3.9, §3.10 (Library v2, Exercise history v2), §6.8, §6.9, §7.7 rules 34, 40, 41; `docs/product-decisions.md` #3, #4, #9, #11, #12, #15, #17 |

## Goal
The lifter can find any of the ~200 catalog exercises (or create their own) and open a per-exercise history: estimated 1RM, best set, session count, an 8-week e1RM chart, and a session log tagged PR / +step / —. History is real data from finished workouts, reachable from Library and from any workout detail.

## User stories
- As a lifter, I can search and filter the library by muscle and equipment so that I find an exercise in two taps.
- As a lifter, I can see my recently logged exercises at the top with their PR so that the ones I care about are one tap away.
- As a lifter, I can open an exercise and see e1RM over the last 8 weeks and every session's sets so that I know whether I am progressing.
- As a lifter, I can create a custom exercise with equipment, muscles and pattern so that unusual movements still get logged and progressed.

## Scope
**In:** `LibraryRoot` (search, muscle + equipment pills, RECENTLY LOGGED / ALL EXERCISES, PR per row, "New exercise"); `ExerciseHistoryView(exerciseID:)` (header stats, Swift Charts e1RM bars, SESSION LOG with tags); `CreateExerciseSheet` (name, equipment, primary muscle, secondary muscles, movement pattern; edit for custom only); routes from Library rows, from F13 workout detail rows, and from F10 receipt rows.
**Out (explicitly):** deleting custom exercises (F29 data lifecycle), editing seed catalog entries, workout list/detail (F13), Today RECENT (routes to F13, decision #11), PR notifications/haptics (F10/F18), alternatives curation (F03).

## Touches
- `LedgerKit/Sources/FeatureLibrary/LibraryRoot.swift`, `LibraryStore.swift`, `LibraryRoute.swift`, `LibraryPresentation.swift`
- `LedgerKit/Sources/FeatureLibrary/Views/LibrarySearchField.swift`, `LibraryFilterPills.swift`, `LibrarySection.swift`, `ExerciseRow.swift`
- `LedgerKit/Sources/FeatureLibrary/History/ExerciseHistoryView.swift`, `ExerciseHistoryStore.swift`, `HistoryStatsRow.swift`, `E1RMChart.swift`, `SessionLogList.swift`
- `LedgerKit/Sources/FeatureLibrary/Create/CreateExerciseSheet.swift`, `CreateExerciseStore.swift`
- `LedgerKit/Sources/FeatureLibrary/Resources/Localizable.xcstrings`
- `LedgerKit/Sources/LedgerDomain/Stats/ExerciseHistory.swift` (new pure: `ExerciseHistory.make(sessions:weeks:) -> ExerciseHistoryModel`, session tags)
- `LedgerKit/Sources/LedgerDomain/Exercises/CustomExerciseDraft.swift` (new: validated draft → `Exercise`)
- `LedgerKit/Tests/LedgerDomainTests/ExerciseHistoryTests.swift`, `CustomExerciseDraftTests.swift`
- `LedgerKit/Tests/FeatureLibraryTests/LibraryStoreTests.swift`, `ExerciseHistoryStoreTests.swift`, `CreateExerciseStoreTests.swift`, `LibrarySnapshotTests.swift`
- `Apps/Ledger/Sources/Navigation/LibraryDestinations.swift` (F07-owned; register `LibraryRoute.exercise` on every tab stack)

## Domain changes
```swift
public enum LibraryRoute: Hashable, Sendable { case exercise(ExerciseID); case createExercise; case openWorkout(WorkoutID) }
public struct ExerciseHistoryModel: Equatable, Sendable {
    public let e1RM: Weight?            // Brzycki of the best set with reps ≤ 12 over all history (decision #4); nil if none
    public let bestSet: (weight: Weight, reps: Reps)?   // highest weight; ties → more reps
    public let sessions: Int
    public let weekly: [WeekPoint]       // 8 points, oldest first: (weekStart, e1RM?) — best e1RM in that week or nil
    public let delta: Weight?            // last non-nil − first non-nil; nil if < 2 points
    public let log: [SessionEntry]       // newest first: (workoutID, date, tag: .pr | .up(Weight) | .same, sets: [(Weight, Reps)])
}
public enum ExerciseHistory { public static func make(sets: [LoggedSetRecord], now: Date, weekStart: Weekday, calendar: Calendar) -> ExerciseHistoryModel }
public struct CustomExerciseDraft { name (trimmed, 2–40 chars, no control characters — Unicode `Cc`, which includes U+0000, refused by F05's `save` as `nulInText`, an error a Feature cannot match — unique case-insensitively), equipment, primaryMuscle, secondaryMuscles, movementPattern; func exercise(id:) throws(ValidationError) -> Exercise }
```
Tag rule (spec rule 41 + decision #3): `.pr` if `PersonalRecords` recorded a PR for this exercise in that workout; else `.up(Δ)` if the session's top working-set weight exceeds the previous session's; else `.same`. Working and added sets feed e1RM and best (product decision #25, the sets `PersonalRecords.detect` counts, so F05's `bestE1RM`, `bestSet` and `e1RMByWeek` already match); warm-up and drop sets show in the log but never count toward a best. The "+{step}" tag compares the sessions' top working-set weights. Weeks are `WeekCalendar` weeks (Settings `weekStart`, decision #15 — ISO-8601 when Monday), the 8 ending with the current week; empty weeks are nil points (no bar, label kept). PR value on Library rows = `bestSet.weight` in user units, "—" if none.
Uses F05 `StatsQueries.setsByExercise(id)`, `.recentlyLoggedExercises(limit: 5)`, `.bestSetPerExercise()`, `.exerciseSessionCount`; `ExerciseRepository.all()` (live), `.insert(_:)`, `.update(_:)` for custom.
Search matching is product decision #23 (Pete, 2026-09-30): a substring of the name or the short name, ignoring case, diacritics and width, with the equipment and muscle filters; aliases are not stored or searched. The rule is one public helper, `ExerciseSearch` in LedgerDomain (F05 S2): `matches(_:query:)` and the name order. `ExerciseRepository.search` takes one primary `MuscleGroup`, so the muscle pills, which are groups ("Legs", "Arms"), filter `observeAll()` in memory through `ExerciseSearch`, mapping each pill to its `MuscleGroup` set.

**Copy (exact):** title "Library"; search placeholder "Search %lld exercises" (live count); muscle pills "All", "Chest", "Back", "Legs", "Shoulders", "Arms"; equipment pills "All", "Barbell", "Dumbbell", "Cable", "Machine", "Bodyweight"; sections "RECENTLY LOGGED", "ALL EXERCISES"; row meta "%@ · %@ · %lld sessions" (recent) / "%@ · %@" (all) / custom "%@ · %@ · Custom"; empty search "Nothing matches that filter." + "Clear filters"; toolbar "New exercise". History: back "Library" (system back), eyebrow "%@ · %@" (equipment · primary muscle, sentence case), title name; stats "1RM est" / "best set" ("%@" + "×%lld") / "sessions", missing → "—"; "ESTIMATED 1RM · 8 WEEKS" + delta "+%@ lb" / "−%@ lb"; chart week labels "W1"…"W8"; no data: "Log a session to start the chart."; "SESSION LOG"; entry date "MMM d" ("Aug 12"), tags "PR" / "+%@ lb" / "—", sets "%@×%lld"; empty "No sessions yet." Create sheet: "New exercise" / "Edit exercise", "Cancel", "Save", fields "Name", "Equipment", "Primary muscle", "Secondary muscles", "Movement pattern", errors "Enter a name.", "Name must be 2–40 characters.", "An exercise with that name already exists."

## Acceptance criteria
1. Given seeded history (Bench Press sets per spec §6.9), when the Library loads, then RECENTLY LOGGED lists up to 5 exercises ordered by last logged date with meta "Barbell · chest · 34 sessions" and PR "195", and ALL EXERCISES lists every catalog + custom exercise alphabetically with PR or "—".
2. Given query "row", muscle "Back", equipment "Machine", when applied, then only Chest-Supported Row (and matching custom) remains in both sections; clearing via "Clear filters" resets all three; filters are case-insensitive substring on name and shortName.
3. Given a row tap, when handled, then `LibraryRoute.exercise(id)` pushes `ExerciseHistoryView` for that exercise (parameterised, never hard-coded).
4. Given spec §6.9's sets, when the history opens, then stats read "218" (Brzycki of 195×5, rounded), "195×5", "34"; the chart shows points 196…218 for W1–W8 with the last bar orange; the delta reads "+22 lb".
5. Given weeks 3 and 6 have no sessions, when charted, then those weeks show no bar but keep their labels; the delta uses first/last non-nil points. Given no working sets at all, then "Log a session to start the chart." replaces the chart and stats show "—".
6. Given a best set of 100×15, when computed, then e1RM ignores it (reps > 12) and uses the best set with reps ≤ 12; if none, "1RM est" shows "—" while "best set" still shows 100×15.
7. Given sessions Jul 22 (170×5 ×5), Jul 29 (175×5 ×4), Aug 5 (175×5 ×4, 175×4), Aug 12 (180×5 ×5, PR), when tagged, then the log reads Aug 12 "PR", Aug 5 "—", Jul 29 "+5 lb", Jul 22 "—" (first session, no previous) — note this corrects the spec's illustrative tags, which are inconsistent with rule 41.
8. Given units = kg, when rendered, then PR values, stats, chart, delta ("+10 kg") and log sets convert; changing units re-renders without navigation.
9. Given "New exercise", when I save "Landmine Press", Barbell, Chest, [Shoulders, Arms], horizontal push, then it appears in ALL EXERCISES with "Barbell · chest · Custom", in the F11 picker, and in F10 swap alternatives (same pattern + muscle); saving a duplicate name shows "An exercise with that name already exists."; blank shows "Enter a name.".
10. Given a custom exercise, when opened from Library, then an "Edit" toolbar button opens the sheet pre-filled; seed exercises have no Edit.
11. Given a session-log entry tap, when handled, then `LibraryRoute.openWorkout(id)` is emitted (app → F13 detail).
12. Given the history screen, when audited, then orange appears on the "1RM est" value, the delta and the last bar only; the chart has an accessibility representation (`AXChartDescriptor`) reading each week's value.

## Test plan
- Unit (LedgerDomainTests): `test_history_e1RM_brzyckiBestSetRepsLE12`, `test_history_e1RM_ignoresRepsOver12`, `test_history_bestSet_tieMoreReps`, `test_history_weekly_eightWeeksEndingNow_emptyNil`, `test_history_weekly_weekStartSunday`, `test_history_delta_firstLastNonNil`, `test_history_delta_nilUnderTwoPoints`, `test_history_tags_prUpSame_spec69Corrected`, `test_history_tags_firstSessionSame`, `test_history_workingSetsOnly`, `test_draft_nameValidation`, `test_draft_duplicateCaseInsensitive`, `test_draft_buildsCustomExercise`.
- Unit (FeatureLibraryTests): `test_store_sections_recentTop5_allAlphabetical`, `test_store_filters_combineAndClear`, `test_store_prValue_unitsAndDash`, `test_store_searchPlaceholder_liveCount`, `test_historyStore_loadsModelForID`, `test_historyStore_unitsChange_rerenders`, `test_createStore_saveInsertsAndDismisses`, `test_createStore_errorsShown`, `test_createStore_editCustomOnly`.
- Integration (LedgerPersistenceTests): `test_statsQueries_setsByExercise_20kSetsUnder50ms`, `test_exerciseRepository_insertCustom_liveObservationEmits`.
- Snapshot (FeatureLibraryTests): `LibraryRoot` × {populated, filtered, emptySearch, noHistory}; `ExerciseHistoryView` × {spec69, gaps, noData, kg}; `CreateExerciseSheet` × {empty, filled, error} — each × {light, dark} × {default, XL}.
- UI (LedgerUITests): F15 flow `onboard_start_log_finish_history` (exercise chart step).

## Non-functional
- Performance budget: Library first frame < 100 ms with 250 exercises; search filter < 10 ms/keystroke; history model for one exercise with 2 000 sets < 50 ms (query) + < 5 ms (pure).
- Accessibility: pills are radio groups; rows read "Bench Press, Barbell, chest, 34 sessions, PR 195 pounds"; chart exposes `AXChartDescriptor` and each bar's value; Dynamic Type to AX5 (stats stack vertically at AX sizes); no colour-only tag (PR also bolded).
- Offline behaviour: fully local.

## Risks / unknowns
- Spec §6.9's sample tags contradict rule 41 (Jul 29 repeats 175 yet is "—" while Aug 5 is "+5 lb"); this brief follows the rule and flags the sample.
- The task text says "last 8 ISO weeks"; decision #15 makes the week boundary a user setting — this brief follows the decision (ISO when Monday).
- Swift Charts bar width 2 pt (v2 look) may not scale with Dynamic Type; fall back to `RuleMark` if needed.

## Definition of Done
Inherits `docs/engineering-standards.md` §12, plus:
- [ ] `ExerciseHistory` and `CustomExerciseDraft` at 100 % line coverage.
- [ ] Chart verified with VoiceOver reading week values on device/simulator (note in implementation notes).
- [ ] Every string above in the String Catalog with plurals (sessions, exercises).
- [ ] Custom exercise round-trips through F11 picker and F10 swap (manual check noted).

## Inputs from F05 (2026-10-02, records follow-up)
- `StatsQueries.personalRecords(exerciseID:)` lists records that F05 detects itself, after every write (product
  decision #27): `achievedAt` is the workout's start, newest first, then workout id, the estimate first.
- **A deload sets no record, but its sets count toward the bests** (decision #25 counts working and added sets
  of every stored workout). So a record's `previous` can be a deload's set: the contract's 255 × 3 "over 250 × 5"
  beats a deload. A PR history row that shows "over …" must expect it (review R-N3).
- `PersonalRecords.Bests.bestSet(of:)` gives the best set from `StatsQueries.bests(before:for:)`.

---
_Filled in by agents during delivery:_
- `F12-library-history/implementation-notes.md`
- `F12-library-history/test-findings.md`
- `F12-library-history/review.md`

## Plan amendments (planner, 2026-10-21, against `main` @ 011ab3d)

The planner's report, recorded as given. Where it and the brief above disagree, this section and the rulings after it win.

Paths are relative to `/Users/peterarevalo/Dev/workout-app/.claude/worktrees/F08-s1`. Line numbers are as of 011ab3d.

## 1. Corrections to the brief

**Files and routing**

| # | The brief says | What is true now | Evidence |
|---|---|---|---|
| C1 | `Apps/Ledger/Sources/Navigation/LibraryDestinations.swift` (owned by F07) | It doesn't exist. `Apps/Ledger` holds only `LedgerApp.swift` and assets. Screens are cases of `AppDestination`; each feature's mapping goes in `LedgerAppKit/Routes+<Feature>.swift`; the screens are drawn in `AppTabs.screen(for:)` | `LedgerKit/Sources/LedgerAppKit/Routes.swift:14-19`, `AppTabs.swift:55-65`, `Routes+Program.swift`; architecture.md:188-205 |
| C2 | `LibraryRoute { .exercise, .createExercise, .openWorkout }` | No feature presents another feature, and a sheet that belongs to the screen is not a route (Today's off-schedule sheet is the precedent, `TodayRoot.swift:15-17`). So the route is `public nonisolated enum LibraryRoute { case exercise(ExerciseID); case openWorkout(WorkoutID) }`. The create/edit sheet is presented by the Library root and by the history root | architecture.md:188-209 |
| C3 | `ExerciseHistoryView(exerciseID:)` | The naming rule says every public entry view is `…Root` and owns its store. So it is `ExerciseHistoryRoot(exercise: ExerciseID, onRoute:)`, pushed through `AppDestination.exercise(ExerciseID)` on whichever tab's stack asked for it | architecture.md:191-195 |
| C4 | Library tab | It is still a `PlaceholderScreen`, at `AppTabs.swift:32-34`. Replacing it means a sanctioned edit of `AppTabsTests.swift:41-55`, which expects the placeholder's single "Library" heading. `Apps/LedgerUITests/TabsAdversarial.swift:11` finds the tab by `library.title`, so the new title keeps that identifier | as cited |
| C5 | A "New exercise" toolbar button on the Library | Tab roots hide the navigation bar (`AppTabs.swift:68-77`, `tabRootChrome`), so the root has no toolbar. "New exercise" has to be drawn in the screen's header. The pushed history screen does keep its bar, so its "Edit" can be a toolbar item | as cited |

**Queries and repository API**

| # | The brief says | What is true now | Evidence |
|---|---|---|---|
| C6 | `StatsQueries.setsByExercise(id)`, `.recentlyLoggedExercises(limit: 5)`, `.bestSetPerExercise()`, `.exerciseSessionCount` | Only these exist: `recentlyLogged(limit:)`, `sessionCount(exerciseID:)`, `bestSet(exerciseID:)`, `bestE1RM`, `e1RMByWeek(exerciseID:lastWeeks:calendar:)`, `personalRecords(exerciseID:)`. **Missing, and F12 adds them:** (a) a batch best set for every exercise (otherwise the Library makes 224 queries); (b) one exercise's done sets grouped by workout, which the session log needs | `LedgerKit/Sources/LedgerDomain/Protocols/Repositories.swift:162-195` |
| C7 | `ExerciseRepository.all()` (live), `.insert(_:)`, `.update(_:)` | `all()` is a one-off read. The live list is `observeAll()`. Writing is a single `save(_:)`, an upsert that refuses `nulInText`. No insert, no update | `Repositories.swift:7-22` |
| C8 | `ExerciseHistory.make(sets: [LoggedSetRecord], …)` | `LoggedSetRecord` is a Persistence type and cannot appear in the Domain. The pure function takes Domain sessions: the new query's result plus the record workout ids | standards §6 |
| C9 | `CustomExerciseDraft … throws(ValidationError)` | There is no `ValidationError`. Add `CustomExerciseError` to `LedgerDomain/Errors.swift`, as `ProgramEditError` is done (`Errors.swift:74-80`) | as cited |
| C10 | The draft builds an `Exercise` from name, equipment, muscles and pattern | `Exercise` also requires `shortName` and `defaultStartLoad`, which the form never asks for (`Exercise.swift:31-66`). The day cards show `shortName` (`ProgramPresentation+Days.swift:32`), and `DayEditing.newSlot` copies `startLoad(in:)` into a new slot (`DayEditing.swift:56-73`). The catalog's start-load policy (decision #21) is JSON data, not a function you can call (`ExerciseCatalog.swift:28-59`). This needs a decision: Q4 | as cited |

**Numbers, examples and criteria**

| # | The brief says | What is true now | Evidence |
|---|---|---|---|
| C11 | Criterion 4: "218" from 195×5 | Brzycki on 195×5 is 219.375, shown as **219**. The "218" in the prototype was only an example. The chart's 196…218 run cannot come out of real sets with 195×5 as the best set. Criterion 4 should check numbers computed from a fixture, not the spec's | `LedgerDomain/Rules/OneRepMax.swift:13-15` |
| C12 | Criterion 7: four sessions give PR / — / +5 lb / — | Against `PersonalRecords`, Jul 29 (175×5 after 170×5) **is** a record: higher weight at the same reps, and a higher e1RM. A first session never is one (the "baseline" rule). So the sequence only holds if older history already holds a best that Jul 29 doesn't beat, for example Jun 24 at 175×6. Then Jul 22 is no longer "the first session", and its "—" is the down case | `PersonalRecords.swift:5-15, 69-104` |
| C13 | Criterion 9: save "Landmine Press" … horizontal push | The catalog already has "Landmine Press" (verticalPush, shoulders), so the duplicate check would refuse it. Use a name the catalog lacks. `ExerciseRepositoryContract.swift:32` also uses "Landmine Press" as a custom fixture, which is harmless there | `exercises.json:911-916` |
| C14 | Criterion 9: it appears in F10's swap alternatives | There is no swap on `main` yet: no swap code at all in `FeatureWorkout`. Swap is F10 S8. F12 can only prove that the exercise is stored with its pattern and muscle. The swap clause becomes an input for F10 S8 | grep of `Sources/FeatureWorkout` |
| C15 | Criteria 1 and 2 say "Bench Press" | The catalog name is "Barbell Bench Press". Criterion 2's query "row" + Back + Machine leaves only Chest-Supported Row (checked against the 224 entries) | `exercises.json:366-371` |
| C16 | Muscle pills "All, Chest, Back, Legs, Shoulders, Arms" | The picker already ships "All, Chest, Back, Shoulders, Legs, Arms", from `ExerciseSearch.MuscleFilter.allCases`. Its equipment chips are a private list inside FeatureProgram. This is Q6 | `ExerciseSearch.swift:56-69`; `ExercisePickerPresentation.swift:17-20` |
| C17 | Row meta "Barbell · chest" | The picker writes "Machine · Back", capitalised, through its own copy members (`ProgramCopy+Picker.swift:72-86`). FeatureLibrary needs its own lookup per enum case either way (standards:252-258). Q6 | as cited |
| C18 | Integration test `test_exerciseRepository_insertCustom_liveObservationEmits` | The contract already covers it: "observeAll emits the exercises now, then after each change". F12 only adds the new queries' clauses | `ExerciseRepositoryContract.swift:26` |
| C19 | `test_…` test names | The convention is `subject_condition_expectation`, with no `test` prefix | docs/testing-strategy.md:440-442 |
| C20 | F12's "working only" | Decision #25 replaced it. Bests count working and added sets. Session counts count every kind of set, so a deload session counts, and so does a session of warm-ups only. Already settled, not a question | `Repositories.swift:156-161`; `GRDBStatsQueries.swift:160-166` |
| C21 | Stats stay live | No stats query is observed. The pattern is Today's: follow `observeRecent` as a change signal, and read everything again in each `run()`, which restarts when the tab comes back. An edit to an old workout (F13) shows on the next run | `TodayStore.swift:20-41, 147` |

**Shared files and components**

| # | The brief says | What is true now | Evidence |
|---|---|---|---|
| C22 | FeatureLibrary module setup | It is still a stub (`FeatureLibrary.swift`, and a placeholder test). The target has no `resources` (`Package.swift:152`). It is missing from `snapshotTestTargets` (`Package.swift:67-70`), from `required` (`scripts/coverage-thresholds.json:15`) and from `PreviewScan.registeredModules` (`LedgerTestSupport/Previews/PreviewScan.swift:9-12`). S1 adds its name to each | as cited |
| C23 | Reuse the picker | Features can't import each other. What can be shared lives in the Domain (`ExerciseSearch.filtered`, `MuscleFilter`) or in LedgerDesign. FeatureProgram's `FilterChips` (`Views/FilterChips.swift:7-18`) and `ExerciseSearchField` (`Views/ExercisePickerScreen.swift:37-69`) are generic. **Plan: move both into LedgerDesign** as string-only components, without changing a pixel of F11's references. There is no magnifier icon in `LedgerIcon` (`LedgerIcon.swift:8-16`), so the Library's search pill draws none, like the picker's | as cited |
| C24 | Receipt rows lead to history | `ReceiptLayout` is "string-only … nothing on it is a control", and a row carries no exercise id (`LedgerDesign/Components/ReceiptLayout.swift:8-10, 59-72`). To make rows tappable: an optional row action in LedgerDesign, an exercise id in the receipt presentation, a new `WorkoutAction`, a new `WorkoutRoute` case, and a mapping in `Routes+Workout.swift`. The receipt sits inside the full-screen cover. Q2 | as cited |
| C25 | History stats with the 1RM value in orange | `StatTile` has no accented value (`StatTile.swift:20-50`). It already draws the value plus a light unit ("195" + "×5") and the caption underneath, which is the v2 history tile. Add one parameter, `isValueAccented`, rather than build a new row | as cited |
| C26 | "the NameFieldLine" | There is no such component. The component is `ledgerFieldFont(_:)` (`LedgerFont.swift:147-165`); `NameField` is a FeatureProgram view (`Views/NameField.swift:35`). "NameFieldLine" is the name of test suites (`FeatureProgramTests/NameFieldLineTests.swift`). The sheet's name field is a plain one-line `TextField` with `.ledgerFieldFont(.body)` | as cited |
| C27 | Swift Charts | No module imports Charts yet. `architecture.md:27` lists Swift Charts in the stack. It is a system framework: it changes neither `Package.swift` nor `package-graph.expected.txt` (the graph script reads target dependencies only, `scripts/check-package-graph.sh`). See flag A1 | as cited |

## 2. Slices

Three sequential pull requests, each cut from `main` after the one before has merged.

- **S2 and S3 could run in parallel** once S1 is on `main`: S1 already adds `AppDestination.exercise`, and S3 doesn't need the history screen except for its "Edit" button. But both edit FeatureLibrary's single catalog, `LibraryStore` and `Library+Previews`. **I recommend running them one after the other.** If time presses, run them in parallel and let the "Edit" button land in whichever merges second.
- **How lines are counted:** non-blank, non-comment Swift under `LedgerKit/Sources` and `Apps`. String catalogs are excluded, and so is `LedgerTestSupport`, which is test-only (F11's precedent, F11 brief:925). LedgerFakes and `*+Previews.swift` are counted.
- **Calibration:** the picker's full stack measures about 500 such lines.
- **Stop rule:** each slice stops and reports past about 950 lines.

### S1: the Library tab (about 780 lines)

**Scope**
- The batch best-set query.
- The two LedgerDesign moves (C23).
- FeatureLibrary's catalog, copy, presentation, store, root and views.
- The Library tab drawing `LibraryRoot`.
- `AppDestination.exercise` drawing a `PlaceholderScreen` until S2.
- Module setup (C22).

**Criteria owned**
- **1 (restated):** RECENTLY LOGGED shows up to 5 exercises in `recentlyLogged` order, each "{equipment} · {muscle} · {n} sessions" with the PR as `bestSet.weight` in the lifter's units, or "—". ALL EXERCISES lists every live exercise in `ExerciseSearch` name order. A custom exercise reads "… · Custom". With no history the recent section isn't drawn.
- **2:** query, muscle and equipment together go through `ExerciseSearch.filtered` and apply to both sections. "Clear filters" resets all three, as the picker does (`ExercisePickerStore.swift:75-78`).
- **3:** a row emits `.exercise(id)`; the app pushes `.exercise(id)` on the selected tab's stack.
- **8, the Library part:** PR values in kg; a change of units redraws without navigating.

**New criteria**
- **N1. Live:** a custom exercise saved, or a workout finished, while the Library is up appears without navigating. The store follows `observeAll`, `settings.observe` and `observeRecent(limit: 1)`, and makes one rebuild per change, as `TodayStore` does.
- **N2. Placeholder count:** "Search %lld exercises" is a plural key, looked up with `forCountedText`. It counts every live exercise, not the filtered rows.
- **N3. Batch query:** `bestSets()` equals `bestSet(exerciseID:)` for every exercise. This is pinned as a contract clause on the in-memory stores and on GRDB.
- **N4. Budgets** (nightly `.performance` suite):
  - `bestSets` over 20,000 sets: under 50 ms at the 95th percentile.
  - The Library model over 250 exercises: under 100 ms.
  - One keystroke: under 10 ms.
- **N5. Conventions:** `FeatureLibrarySourceTests` checks the conventions listed in the F11 brief at lines 754-770, and that every lookup is in `LibraryCopy*.swift`.
- **N6. Orange:** none on the Library.
- **N7. VoiceOver:** each row is one button reading "Barbell Bench Press, Barbell, Chest, 34 sessions, PR 195 pounds". The pill rows are labelled groups whose chips are `.isSelected` (the picker's pattern).
- **N8. The tab:** the Library tab draws `LibraryRoot`, and its title keeps `library.title`.

**Files and estimates**

| File | Lines |
|---|--:|
| `LedgerDomain/Protocols/Repositories.swift`: `bestSets() -> [ExerciseID: BestSet]` and a small `BestSet` struct, under `LedgerDomain/Model` | 12 |
| `LedgerDomain/Rules/ExerciseSearch.swift`: `equipmentFilters`, moved out of `ExercisePickerPresentation` | 3 |
| `LedgerPersistence/Stats/GRDBStatsQueries+Library.swift` | 30 |
| `LedgerFakes/InMemoryStatsQueries.swift` | 10 |
| `LedgerDependencies/Unimplemented/UnimplementedStatsQueries.swift` | 3 |
| `LedgerDesign/Components/FilterChipRow.swift`, `SearchField.swift` (moved), plus their gallery entry | 55 |
| FeatureProgram: `FilterChips` and `ExerciseSearchField` replaced by the shared ones | about −45, not counted |
| `FeatureLibrary/LibraryRoute.swift` | 8 |
| `LibraryCopy.swift`: title, placeholder, pills, sections, row meta, sessions, Custom, the empty state, New exercise, spoken row; 7 equipment and 11 muscle names | 115 |
| `LibraryAction.swift`, `LibraryInput.swift`, `LibraryModel.swift` | 80 |
| `LibraryPresentation.swift` | 110 |
| `LibraryStore.swift`, `LibraryStore+Sources.swift` | 150 |
| `LibraryRoot.swift` | 40 |
| `Views/LibraryScreen.swift`, `LibraryPage.swift`, `LibraryRow.swift` | 85 |
| `Library+Previews.swift`, over `Seed.preview()` | 55 |
| `LedgerAppKit`: `Routes.swift` (+`.exercise`), `Routes+Library.swift`, `AppTabs.swift`, `MainRoot.swift` | 30 |
| `Package.swift` (resources) | 1 |
| Placeholder `FeatureLibrary.swift` and its test removed | −3 |
| **Total** | **about 790** |

**Tests**
- Contract: `StatsQueriesContract` gains the `bestSets` clauses, so they run on both the in-memory stores and GRDB.
- Unit: `LibraryPresentationTests` covering sections, filters, PR in lb and kg, "—", the custom meta, the counted placeholder; `LibraryCopyTests` with one and with several.
- Store: `LibraryStoreTests` for the first model, live custom, a finished workout, units, clear filters, a double tap giving one route, an observation that ends giving the failed state.
- Hosted: `LibraryRootTests`, `LibraryAccessibilityTests`, `LibraryLayoutTests`. Every size sweep goes through `TestSweep.sizes(…)`; bold and right-to-left go through `TestSweep.subset`.
- Snapshots: `LibrarySnapshotTests` for {populated, filtered, emptySearch, noHistory} × {light, dark} at `.large`, plus populated at `.accessibility3` in light and dark: 10 references, under the 20-reference line (testing-strategy:211-212).
- F11's own snapshot references must stay byte-identical after the component move.
- App: `LibraryRouteMappingTests`, and the edit of `AppTabsTests`.
- Nightly UI: `Library.swift` types a query, taps a chip, then a row.
- Performance: `LibraryQueriesPerformanceTests`, gated by `.enabled(if: TestLane.runsSlowTests)` as `StatsQueriesPerformanceTests.swift:16-17` is. No test-plan edit is needed.

**Needs:** nothing. Merge first.

### S2: Exercise history (about 880 lines)

**Scope**
- The sessions query.
- The pure `ExerciseHistory` fold: the model, the 8 weeks, the delta, the tags.
- `ExerciseHistoryRoot`, its store and presentation, the stats row, the chart with its chart descriptor, the session log.
- `AppDestination.exercise` drawing the root.
- `.openWorkout` mapped to the History tab until F13.

**Criteria owned**
- **4 (restated per C11).** For a fixture whose best set is 195×5: "219", "195×5", and its session count. W1–W8 are the e1RM bests of the fixture's 8 weeks; only the last bar is orange; the delta is W8 − W1.
- **5:** an empty week draws no bar but keeps its label; the delta uses the first and last points that have a value; with no working or added set, "Log a session to start the chart." and "—".
- **6:** 100×15 → "1RM est" is "—" and the best set is "100×15".
- **7 (restated per C12):** the fixture is Jun 24 175×6, then Jul 22, Jul 29, Aug 5, Aug 12. The log reads Aug 12 "PR", Aug 5 "—", Jul 29 "+5 lb", Jul 22 "—", Jun 24 "—". A first session is a baseline. A drop in weight is "—".
- **8, the history part:** stats, chart, delta, log and set chips in kg, redrawn when the units change.
- **11:** tapping a log entry emits `.openWorkout(id)`, which until F13 selects the History tab, as Today's route does (`Routes+Today.swift:16-19`).
- **12:** the chart has a chart descriptor; orange as Q3 settles.

**New criteria**
- **N9. One query, one fold:** `exerciseSessions(exerciseID:)` returns, newest first (as `recent` orders), each workout's done sets of the exercise, all kinds, rows merged in order. `ExerciseHistory.make` derives the best set, e1RM, sessions and weekly values from it. A differential contract clause pins them equal to `bestSet`, `bestE1RM`, `e1RMByWeek` and `sessionCount` over seeded histories (decision #25 kinds; decision #26 start dates; weeks from `WeekCalendar` with `settings.weekStart`). `PersonalRecords.countsTowardBests` (`PersonalRecords.swift:109`) becomes public so the Domain has one rule.
- **N10. Tags:** PR comes from `personalRecords(exerciseID:)`'s workout ids, so a deload never shows "PR". "+{Δ}" is the session's top working-set weight minus the previous session's.
- **N11. Budgets:**
  - The sessions query, for an exercise with 2,000 of 20,000 sets: under 50 ms (nightly suite).
  - The fold: under 5 ms.
- **N12. Text sizes:** at accessibility sizes the stats stack, and the chart becomes a list of week and value (one layout per size class, as `ReceiptLayout` does).
- **N13. Live:** a rename from S3, or a finished workout, updates an open history screen. The store follows `observeAll`, `settings.observe` and `observeRecent(limit: 1)`.
- **N14. Dates:** a log date reads "Aug 12" in the current year and "Aug 12, 2025" otherwise, through `Date.FormatStyle` with the injected locale, calendar and time zone, as `WorkoutPresentation+Receipt.swift:86` does.

**Files and estimates**

| File | Lines |
|---|--:|
| `Repositories.swift` (+`exerciseSessions`) and a new `LedgerDomain/Model/ExerciseSession.swift` | 20 |
| `GRDBStatsQueries+Library.swift` (+sessions) | 40 |
| InMemory stats (+20), Unimplemented (+3) | 23 |
| `LedgerDomain/Rules/ExerciseHistory.swift`: the model, `make`, the weeks, the tags | 110 |
| `FeatureLibrary/History/ExerciseHistoryRoot.swift` | 45 |
| `ExerciseHistoryStore.swift` | 120 |
| `ExerciseHistoryInput.swift`, `ExerciseHistoryModel.swift` (presentation types) | 60 |
| `ExerciseHistoryPresentation.swift` | 120 |
| `LibraryCopy+History.swift` | 75 |
| `Views/ExerciseHistoryScreen.swift`, `ExerciseHistoryPage.swift` | 45 |
| `Views/HistoryStats.swift` | 25 |
| `LedgerDesign/Components/StatTile.swift` (+`isValueAccented`) | 8 |
| `Views/E1RMChart.swift` (bars and the list at accessibility sizes) | 70 |
| `Views/E1RMChartDescriptor.swift` (`AXChartDescriptorRepresentable`) | 35 |
| `Views/SessionLog.swift` | 40 |
| `History+Previews.swift` | 50 |
| `LedgerAppKit/AppTabs.swift`, `Routes+Library.swift` | 10 |
| **Total** | **about 895** |

**Tests**
- Domain: `ExerciseHistoryTests`, every brief test renamed per C19. Add the week start on Sunday, a week boundary across daylight saving, a deload, warm-up and drop sets shown in the log but never counted, and a property test checking the fold against `HistoryModel+Stats`. 100% line coverage of the file.
- Contract: the clauses of N9.
- Store: `ExerciseHistoryStoreTests` for the model of the exercise asked for, units, a rename, a finished workout, the failed state, `.openWorkout` delivered once.
- Hosted, through `TestSweep`: `ExerciseHistoryRootTests`, `ExerciseHistoryAccessibilityTests` (the stops plus the descriptor's series values read from `makeChartDescriptor()`), `ExerciseHistoryLayoutTests`.
- Orange: `ExerciseHistoryOrangeAuditTests`, as `ProgramOrangeAuditTests`.
- Snapshots: {fixture, gaps, noData, kg} × {light, dark} at `.large`, plus the fixture at `.accessibility3` in light and dark: 10 references.
- Nightly UI: Library → row → history; the chart's accessibility element exists.
- The DoD's VoiceOver check on the simulator.

**Needs:** S1 (`AppDestination.exercise`, `LibraryCopy`, the module setup).

### S3: New and Edit exercise, and the route from the receipt (about 620 lines)

**Scope**
- `CustomExerciseDraft`.
- `CreateExerciseStore` and its sheet, with five fields: the name, single-choice chips for equipment, primary muscle and pattern, and multi-choice chips for secondary muscles.
- "New exercise" on the Library.
- "Edit" on a custom exercise's history.
- Receipt rows leading to history (if Q2 is A).

**Criteria owned**
- **9 (restated per C13 and C14):** save "{a name the catalog lacks}", Barbell, Chest, [Shoulders, Triceps], horizontal push. It appears in ALL EXERCISES as "Barbell · Chest · Custom" and in the open F11 picker (the existing test `customExerciseSavedWhileOpen_appears`). It is stored with `isCustom` and the pattern and muscle given. A duplicate shows "An exercise with that name already exists." and a blank shows "Enter a name."
- **10:** a custom exercise's history shows "Edit", which opens the sheet filled in; a catalog exercise shows none.

**New criteria**
- **N15. Name rules:** trimmed; 2–40 characters; no Unicode `Cc` characters; unique by `ExerciseSearch.key` among live exercises, the edited one excluded. The primary muscle is never among the secondaries.
- **N16. Saving:** a save calls `save` once. A second tap while it runs does nothing. A failure shows a line and keeps the sheet up. A cancelled task changes nothing.
- **N17. The fields the form doesn't ask for** follow Q4.
- **N18. From the receipt:** a row's tap closes the cover and pushes that exercise's history (Q2).

**Files and estimates**

| File | Lines |
|---|--:|
| `LedgerDomain/Exercises/CustomExerciseDraft.swift` and `CustomExerciseError` | 75 |
| `FeatureLibrary/Create/CreateExerciseStore.swift` | 100 |
| `CreateExerciseInput.swift`, `CreateExerciseModel.swift`, `CreateExercisePresentation.swift` | 110 |
| `LibraryCopy+Create.swift`: 10 patterns, fields, errors, buttons | 75 |
| `Create/CreateExerciseSheet.swift` (on `SheetChrome`) and `CreateExerciseFields.swift` | 110 |
| Library and history roots and stores: the sheet, "New exercise", "Edit" | 35 |
| `Create+Previews.swift` | 40 |
| `LedgerDesign/ReceiptLayout.swift` (optional row action) | 20 |
| `FeatureWorkout`: `WorkoutAction`, receipt presentation, `WorkoutRoute.exercise`, cover hand-off | 35 |
| `LedgerAppKit/Routes+Workout.swift` | 5 |
| **Total** | **about 605** |

S3 sits under the 700-line band by its nature. Folding it into S2 would take S2 past 1,000.

**Tests**
- Domain: `CustomExerciseDraftTests` at 100%, including a property test over random Unicode names.
- Store: `CreateExerciseStoreTests` for save, the errors, edit of a custom exercise only, a double tap, a failure, a cancellation.
- Hosted, through `TestSweep`: `CreateExerciseSheetAccessibilityTests` (one name field; chips `.isSelected`; secondary muscles as toggles), `CreateExerciseLayoutTests`.
- Snapshots: {empty, filled, error} × {light, dark} at `.large`, plus filled at `.accessibility3`: 7 references.
- FeatureWorkout: an edit of the receipt's tests for the tappable row; `ReceiptLayout` snapshots unchanged.
- Nightly UI: create an exercise, then find it in the Library and in the Day editor's picker. This is the DoD's round trip through the picker; the swap part goes to F10 S8.

**Needs:** S1 for the Library root and copy; S2 for "Edit" and the history destination.

**S3 amendments (orchestrator, 2026-10-26).** Pete merged S2 (#72) and left #72's four questions to the
orchestrator's judgement:
- **S2-Q1, the high-rep chart message:** kept as built ("No set of 12 reps or fewer in the last 8 weeks.").
- **S2-Q2, the spoken change:** kept as built ("Up {Δ} over {n} weeks", the span between the first and last weeks
  with a value); "since W5" is the axis's shorthand and reads poorly aloud.
- **S2-Q3, "+Δ" after a warm-up-only session: changed in S3 (N19).** A session's tag compares its top working
  weight with the most recent earlier session that has a working set (working or added, decision #25's rule,
  `PersonalRecords.countsTowardBests`), not merely the session before. A session with no working set still reads
  "—". A warm-up-only session between two working sessions no longer hides a step up.
- **S2-Q4, the numberless sessions caption:** deferred until the first translation is commissioned;
  `LibraryCopyTests.sessionsForms_areTheNumberThenWords` guards the shape until then.
- **F12-S2-6, carried into S3 (N20):** the Library (S1) follows every workout of the history, not only the newest,
  so a finished, edited or deleted older workout reaches RECENTLY LOGGED, the session counts and the best sets, as
  S2's history already does. Use an observation of the stats' sources (as `observeExerciseSessions` does), not a
  wider `followedWorkouts` window.
- S3's estimate rises by about 70 lines (N19 about 25, N20 about 45), to about 675.

## 3. Open questions for Pete

Each will be built to its recommended default until Pete answers.

1. **A history log entry before F13.**
   - A: tapping it selects the History tab (a placeholder for now), as Today's RECENT does.
   - B: the entries aren't tappable until F13.
   - Recommended: A. It is one line in `Routes+Library.swift`, and F13 only changes where it goes.
2. **Receipt rows lead to history** (the receipt is inside the workout's full-screen cover).
   - A: a tap closes the receipt, as "Done" does, and pushes the history on Today's stack.
   - B: the same, but on the Library tab.
   - C: no route from the live receipt; only F13's workout detail gets one.
   - Recommended: A. The lifter lands where they were, one step deeper.
3. **Orange on the history screen.** The design has three oranges: the "1RM est" value, the delta, and the last bar. Decision #17 says orange once per screen, and F11's Q4 kept the picker to one.
   - A: all three, as designed. They mean one thing, the current estimate. If the current week has no session, no bar is orange.
   - B: the "1RM est" value only.
   - Recommended: A.
4. **What a custom exercise gets for the fields the form doesn't ask for.**
   - Short name:
     - A: the name itself.
     - B: an extra "Short name" field.
     - Recommended: A.
   - Start load:
     - A: 0, so the first slot starts empty and the lifter sets it.
     - B: the catalog's compound default for the chosen equipment (decision #21's table, written into code).
     - Recommended: A. It can't be wrong for an unknown movement.
   - In both cases: no curated alternatives, and the equipment's default step.
5. **Editing a custom exercise that is already in workouts or a program.**
   - A: every field can be edited. Past workouts keep the name they were logged under; programs follow the id and show the new name.
   - B: name and equipment are locked once logged.
   - Recommended: A. Changing the equipment changes future steps only.
6. **The Library's chips and casing.**
   - A: match the picker. Pill order is "All, Chest, Back, Shoulders, Legs, Arms"; meta reads "Barbell · Chest"; the history eyebrow is the same text.
   - B: the prototype. The order is "…Legs, Shoulders…", the meta "Barbell · chest" in sentence case, and the picker would differ.
   - Recommended: A, one vocabulary in the app.
7. **The kg delta and the rounding of chart values.**
   - A: the delta is the last shown whole value minus the first, so the sums on screen agree ("+10 kg"). The "+{Δ}" tag uses `Weight.formatted(in:)`, so 5 lb shows as "+2.3 kg". No change shows "—", and the chart's delta shows "0 kg".
   - B: exact deltas rounded once.
   - Recommended: A.
8. **Empty Library.** When the catalog failed to seed (decision #28) and nothing is custom, the screen shows:
   - A: "No exercises yet." with "New exercise".
   - B: the filter's "Nothing matches that filter."
   - Recommended: A. One new key.

## 4. Architecture flags

- **A1. Swift Charts.** It is a system framework: no `Package.swift` edge, no `package-graph.expected.txt` change, and no ADR, since `architecture.md:27` already names it.
  - I recommend not using it for v2's 2-pt bars. Plain SwiftUI shapes plus `accessibilityChartDescriptor(_:)` with an `AXChartDescriptorRepresentable` draw the same thing. They give stable snapshots, no system fonts on axes, and full control at accessibility sizes.
  - Orchestrator ruling needed: plain SwiftUI, or `import Charts`. If Charts: only `E1RMChart.swift` imports it, and FeatureLibrary's source test allows that one import, as the view import rule does in `ProgramViewsSourceTests.swift:78-82`. Either way, the descriptor file may need `import Accessibility`, allowed in that file alone.
  - A 2-pt bar width is a new LedgerDesign token (for example `LedgerHairline.bar`). A raw 2 would slip past the frozen lint and fail review.
- **A2. New Domain API.** `StatsQueries` gains `bestSets()` (S1) and `exerciseSessions(exerciseID:)` (S2). `PersonalRecords.countsTowardBests` becomes public. No migration is needed: the existing indexes serve both queries (`idx_wex_exercise_workout`; every foreign key is indexed, `Migrations.swift:43`). No ADR is needed: the protocols are F05's to extend.
- **A3. LedgerDesign changes in S1–S3:** `FilterChipRow`, `SearchField` (moved from FeatureProgram), `StatTile.isValueAccented`, an optional row action on `ReceiptLayout`. Each comes with a gallery entry and its own snapshots.
- **A4. Project file and test plans:** none needed.
  - New UI tests go in `Apps/LedgerUITests`, a synchronized folder (ADR-003). The PR plan selects `Smoke` only.
  - `FeatureLibraryTests` is already in both plans (`TestPlans/PR.xctestplan:115`, `Nightly.xctestplan:115`).
  - The `.performance` suites gate themselves by trait (`StatsQueriesPerformanceTests.swift:16-17`), so the PR plan needs no `skippedTests` entry. This is unlike F11's R12.
- **A5. Shared one-line files** (S1, the module's name only): `snapshotTestTargets`, `coverage-thresholds.json` `required`, `PreviewScan.registeredModules`, the target's `resources`. `ModuleCopyTests` finds the new catalog by itself.
- **A6. Standards:** no change. Every PR description must say it is over the 500-line target, and name the split it considered (standards §10:512-515).
- **A7. Sanctioned edits of others' tests, listed in the notes:**
  - `AppTabsTests.swift:41-55` (S1).
  - The receipt's tests in FeatureWorkoutTests (S3).
  - Any FeatureProgram test that names `FilterChips` or `ExerciseSearchField` by type (S1).

## 5. Risks

- **R1. Query budgets.**
  - `bestSets` is one GROUP BY over every done set of the two counted kinds, roughly a full scan of 20k rows. Expected 5–20 ms.
  - `exerciseSessions` walks `idx_wex_exercise_workout` and then `logged_set` by its foreign-key index. Expected under 15 ms for 2,000 sets.
  - Both are measured by the nightly `.performance` suite against `PerformanceBudget.statsQuery` (`Tests/LedgerPersistenceTests/Performance/PerformanceBudget.swift`). That file already holds `exerciseSearch` (10 ms) "for F12".
  - Opening the Library also runs `recentlyLogged` and five `sessionCount` calls: seven reads, about 25 ms at worst, off the main actor.
- **R2. Search per keystroke.** `ExerciseSearch.filtered` folds about 450 strings per keystroke, the same work the picker does inside its 10 ms (F11 criterion 27, measured by hand). If the Library's model builds row text for all 224 rows on every keystroke, cache the formatted PR and meta per exercise across keystrokes and rebuild them only when the sources change. S1's performance test pins this.
- **R3. The chart descriptor in hosted tests.** The hosted reader may not expose `accessibilityChartDescriptor` through SwiftUI's elements. The fallback is to test `makeChartDescriptor()` directly (series name, eight points, the empty weeks absent), plus the DoD's manual VoiceOver note. Charts would also produce an automatic descriptor, but the 2-pt rules give it nothing useful to read.
- **R4. AX5.**
  - Eight columns on 375 pt leave about 40 pt each; "219" at AX5 doesn't fit, hence N12's list at accessibility sizes.
  - The stats tiles stack (`StatTile` already shrinks one line; the stacking comes from the history page).
  - Session-log chips wrap (`WrapLayout`).
  - In the create sheet, eleven muscle chips wrap into many lines at AX5. The sheet is pinned chrome over a scroll view, as the picker is (`ExercisePickerScreen.swift:16-24`).
- **R5. CI time.**
  - Under `TEST_RUNNER_LEDGER_SWEEP=pr`, each hosted layout or accessibility suite keeps 4 sizes, with a bold and right-to-left subset. That is about 30 renders per screen family.
  - Estimate added PR-run time, measured on a developer Mac:
    - S1: about 30–40 s.
    - S2: about 35–45 s, the chart's sizes included.
    - S3: about 25–35 s.
    - Plus about 5–10 s of snapshots per slice.
  - At the runner's 2–3× that is roughly 70–150 s per PR, and 200–400 s once all three have landed.
  - Against `docs/ci-cd.md:127-133` (tests about 1,960 s at most, deadline 3,840 s), it fits.
  - Each slice measures and writes its seconds in the notes, as F08's criterion 25 did. No sweep may read a swept list's count (`TestSweep.swift:7-12`).
- **R6. Fixture realism.** The spec's §6.9 numbers can't be produced (C11, C12). Keep the criteria fixtures in LedgerTestSupport (not counted), and keep previews on `Seed.preview()` (`InMemoryStores.swift:52-60`) so LedgerFakes grows nothing.
- **R7. Slice size.** S2 is near the top of the band; store slices have overrun before (F11 brief:941-944). Stop at about 950. The split point: the query, the fold and the presentation first (about 450, nothing on screen), then the views and the app (about 430).
- **R8. Renaming a custom exercise** while it is in an open Day editor: the day card reads `exercises[id].shortName` live, so it follows. Workouts keep their snapshot name (`WorkoutExercise.swift:15`). Q5 confirms that is intended.

### Critical Files for Implementation
- `LedgerKit/Sources/LedgerDomain/Protocols/Repositories.swift`
- `LedgerKit/Sources/LedgerPersistence/Stats/GRDBStatsQueries.swift`
- `LedgerKit/Sources/FeatureProgram/Picker/ExercisePickerPresentation.swift` (the pattern to mirror) and `LedgerKit/Sources/FeatureToday/TodayStore.swift` (the store pattern)
- `LedgerKit/Sources/LedgerAppKit/AppTabs.swift` and `LedgerKit/Sources/LedgerAppKit/Routes.swift`
- `LedgerKit/Sources/LedgerDomain/Rules/PersonalRecords.swift`

## Rulings before G1 (orchestrator, 2026-10-21)

- **R1. Corrections C1–C27 are accepted.** Criteria 1–12 are read as restated in the slices above, and N1–N18 are added.
- **R2. The chart (flag A1): plain SwiftUI shapes, no `import Charts`.**
  - The chart gets `accessibilityChartDescriptor(_:)` with an `AXChartDescriptorRepresentable`. `import Accessibility` is allowed in that one file.
  - The 2-pt bar is a new LedgerDesign token, not a literal.
  - This choice keeps the snapshots stable and gives full control at accessibility sizes, and it needs no ADR.
- **R3. Three sequential PRs: S1 → S2 → S3,** each cut from `main` after the previous one has merged. Stop and report at about 950 product lines, with R7's split point for S2. Lines are counted as the planner says: `LedgerTestSupport` and string catalogs are excluded.
- **R4. Pete's questions Q1–Q8 are built to their recommended defaults until he answers:** Q1 A, Q2 A, Q3 A, Q4 A/A, Q5 A, Q6 A, Q7 A, Q8 A. S1 depends only on Q6 and Q8. Each default lives in one place, so a different answer is cheap.
- **R5. Moving `FilterChips` and `ExerciseSearchField` into LedgerDesign (C23) is part of S1.** F11's snapshot references must stay byte-identical. Each type rename in FeatureProgram's tests is a sanctioned edit and is listed in the notes.
- **R6. Every new hosted-view suite sweeps through `TestSweep`.** Each slice measures its added PR-sweep seconds and writes them in the notes.
- **R7. Who merges.** Each F12 PR carries new wording and Pete's product defaults, so Pete merges each one.
