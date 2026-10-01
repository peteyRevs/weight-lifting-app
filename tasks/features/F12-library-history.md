# F12 — Library and Exercise history

| | |
|---|---|
| Milestone | M1 |
| Status | ready |
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
public struct CustomExerciseDraft { name (trimmed, 2–40 chars, unique case-insensitively), equipment, primaryMuscle, secondaryMuscles, movementPattern; func exercise(id:) throws(ValidationError) -> Exercise }
```
Tag rule (spec rule 41 + decision #3): `.pr` if `PersonalRecords` recorded a PR for this exercise in that workout; else `.up(Δ)` if the session's top working-set weight exceeds the previous session's; else `.same`. Only `kind == .working` sets feed e1RM/best/tags; drop/added/warmup sets show in the log but are not tagged. Weeks are `WeekCalendar` weeks (Settings `weekStart`, decision #15 — ISO-8601 when Monday), the 8 ending with the current week; empty weeks are nil points (no bar, label kept). PR value on Library rows = `bestSet.weight` in user units, "—" if none.
Uses F05 `StatsQueries.setsByExercise(id)`, `.recentlyLoggedExercises(limit: 5)`, `.bestSetPerExercise()`, `.exerciseSessionCount`; `ExerciseRepository.all()` (live), `.insert(_:)`, `.update(_:)` for custom.
Search matching is product decision #23 (Pete, 2026-09-30): a substring of the name or the short name, ignoring case and diacritics, with the equipment and muscle filters; aliases are not stored or searched. The rule is one public helper, `ExerciseSearch` in LedgerDomain (F05 S2): `matches(_:query:)` and the name order. `ExerciseRepository.search` takes one primary `MuscleGroup`, so the muscle pills, which are groups ("Legs", "Arms"), filter `observeAll()` in memory through `ExerciseSearch`, mapping each pill to its `MuscleGroup` set.

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

---
_Filled in by agents during delivery:_
- `F12-library-history/implementation-notes.md`
- `F12-library-history/test-findings.md`
- `F12-library-history/review.md`
