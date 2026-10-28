# F13 — implementation notes

## S1 — as built (G1 implementer, 2026-10-28)

Branch `feat/F13-workout-history`, from `main` at `98b340d` plus the plan (`911b4b6`) and the rulings (`34aa260`).
The specification is the brief's "Plan amendments (planner, 2026-10-28)" (slice S1: criteria 1, 2, 6 (route part), 7
and 8 (list parts) as restated, N1–N7 and N10's list part) and "Rulings before G1". Pete's questions are built to the
planner's recommended defaults (Q1 A, Q6 A, Q7 A for this slice); each default's code says "F13 question N, built to
A", so a search finds every place.

### Commits

- `ff536cd` feat(history): the History list's query, its observation, its weeks and spoken weights.
- `093a4ec` feat(history): the History tab lists past workouts by week, and a past workout opens where it was tapped.
- this notes commit (docs only).

### What landed

Paths under `LedgerKit/`.

- **Domain.**
  - `Model/HistoryEntry.swift`: id, name, tag, deload flag, start, elapsed, volume, done and total sets, `prCount`;
    `init(_ workout:prCount:)` computes the totals from the sets (what a stored row says).
  - `WorkoutRepository.historyEntries()` and `observeHistoryEntries()` (N1, N2), documented in `Repositories.swift`,
    with A5's narrower rule: a workout whose own row can't be read is left out; one whose sets are damaged is listed.
  - `Rules/HistoryWeeks.swift` (N3): pure grouping under `WeekCalendar.week(containing:)` for `weekStart`; each week
    carries `lastDay`, the start of its seventh day found by counting civil days (R7), for the header.
  - `Units/SpokenWeight.swift` (A6): `Weight.spoken(in:locale:)` and `Volume.spoken(in:locale:)` through
    `Measurement<UnitMass>.FormatStyle(width: .wide)` in the caller's locale: "1 pound", "1.5 pounds", "24,180
    pounds", Arabic digits under `ar_EG`. The number is the one the screen draws (`formatted(in:)`), rounded first;
    `Double` is touched only to hand it to the formatter.
- **Persistence.** `Repositories/GRDBWorkoutRepository+History.swift`: one `SELECT * FROM workout` (live, finished,
  ended) ordered `started_at DESC, id`, read through `WorkoutRecord` plus the stored `volume_e7g_reps`, `done_sets`,
  `total_sets` and `pr_count`; a row that can't be read is logged and left out (`readable`). The observation tracks
  the `workout` table alone, with `removeDuplicates`, so `workout_event` writes never wake it. Two visibility changes:
  `GRDBWorkoutRepository.queue` and `WorkoutRows.requireTextID` from `private` to internal (as F12 did for the stats'
  queue).
- **Fakes and stub.** `InMemoryHistory.historyEntries` (records counted per workout); `InMemoryWorkoutRepository`'s
  two methods; `UnimplementedWorkoutRepository`'s two.
- **Contract.** `LedgerTestSupport/Persistence/WorkoutRepositoryContract+History.swift`, `historyClauses` (3), run on
  GRDB (`WorkoutRepositoryTests`, in an extension) and in memory (`InMemoryContractTests`): order with a tie on start;
  each entry equal to `HistoryEntry(workout(id:), prCount:)` with the records the stats list; a deleted workout absent;
  an edit's new volume and a later workout's record taken away; the observation after a finish, a newer finish, an
  edit and a delete of the oldest (each value equal to the read then), and nothing within 200 ms after a log append.
- **FeatureHistory**, new: `HistoryRoute` (`.workout(id)`, `.today`), `HistoryCopy` (11 keys, 2 with plural forms),
  `HistoryInput`, `HistoryModel`, `HistoryPresentation`, `HistoryStore`, `HistoryStore+Sources`, `HistoryRoot`;
  `Views/HistoryScreen`, `HistoryPage`, `HistoryWeek` (with `HistoryRow`), `History+Previews` (3 states over
  `Fixtures.history(weeks: 4)`, the preview seed's history, with records detected honestly);
  `Resources/Localizable.xcstrings`. The placeholder `FeatureHistory.swift` and its test are removed.
- **LedgerAppKit.** `AppDestination.workout(WorkoutID)` draws `PlaceholderScreen(AppCopy.title(of: .history),
  identifier: "history.workout.title")` until S2. `Routes+History.swift`: a row pushes `.workout(id)` on the selected
  tab; "Go to Today" selects Today. `Routes+Today.swift`: `.openWorkout(id)` pushes on Today's stack.
  `Routes+Library.swift`: a session pushes on the selected tab, over the exercise history (Q1 A). The History tab
  draws `HistoryRoot`; `MainRoot` passes `onHistoryRoute`.
- **Module setup (C4).** `Package.swift` (resources; `snapshotTestTargets`), `coverage-thresholds.json` `required`,
  `PreviewScan.registeredModules` (FeatureHistory on its own line). Each edit is line-local for F14's merge (A10).
- **Tests.** `FeatureHistoryTests`: 10 suites plus support (fixtures, parts, a copy of `ViewStop`).
  `LedgerDomainTests`: `HistoryWeeksTests`, `SpokenWeightTests`. `LedgerAppKitTests/HistoryRouteMappingTests`.
  Nightly: `LedgerPersistenceTests/Performance/HistoryQueriesPerformanceTests` and the UI test
  `Apps/LedgerUITests/WorkoutHistory.swift`.

No change to the project file, a test plan or `.github/`.

### Decisions and deviations

1. **No `HistoryAction`.** The list's only intents are routes, so the views send `HistoryRoute` and the store keeps
   one pending, as `ExerciseHistoryStore` does. The plan's `HistoryAction.swift` would have been a one-case enum.
2. **No new AppCopy key for the detail placeholder.** It reuses the History tab's title, so `AppCopy`, its catalog,
   `ModuleCopyTests`' count and `AppCopyAdversarialTests.shellStrings` stay as they are; F14 removes the Settings
   placeholder from those same lines, and S2 removes this placeholder.
3. **Today's `.openWorkout` pushes on `.today` explicitly** (as `.settings` does); the Library's and History's push on
   the selected tab, which is the one that asked.
4. **The badge counts `pr_count`**, every live record of the workout: an estimated 1RM and a weight at reps on the
   same exercise are two. The preview's seed workouts read "4 PRs" to "8 PRs" (open question 1).
5. **A week's header** is `Date.IntervalFormatStyle` month-abbreviated and day, from the first day to `lastDay`; the
   year is added when either end is outside the current year ("Dec 29, 2025 – Jan 4, 2026", "Sep 8 – 14, 2025").
   en_US writes thin spaces (U+2009) around the en dash; the tests spell that (`String.thinSpaced`). The eyebrow
   draws it in capitals; VoiceOver reads the header as written.
6. **The row has no tag and no "Today · 24:22" form**: always "Wed · 58 min · 24,180 lb" (Q6 A). A workout's tag and
   deload flag are in `HistoryEntry` for S2.
7. **The model is built off the main actor** (`@concurrent`, as `ExerciseHistoryStore`). The counted texts (minutes,
   badge) are looked up once per number per model (`CountedTexts`): each counted lookup costs about 12 µs (the
   catalog read plus `forCountedText`), and three per row put 1,000 rows at 47 ms on the host; with the cache it is
   14.5 ms (N4's budget is 30 ms).
8. **The failed state's wording is new** (open question 2).
9. **`ProbedWorkouts` (FeatureTodayTests) got its two methods in a new file**, `ProbedWorkouts+History.swift`, with
   `base` made internal: in `TodayScene.swift` they would have taken the file past the lint's 300 lines.

### New wording for Pete

All in `HistoryCopy.swift`: "History", "58 min" / "1 min", spoken "58 minutes" / "1 minute", "24,180 lb" / "kg",
"1 PR" / "3 PRs", "No workouts yet.", "Finish a workout and it shows up here.", "Go to Today" (Q7 A, the planner's).
**Not in the brief or plan:** "Can't show your history right now" / "Your workouts are still on this iPhone. Open the
app again to try once more." (failed state, modelled on the Library's). Spoken weights use Foundation's unit words
("pounds", "kilograms").

### Criteria → tests

Suites: `HistoryPresentationTests` (P), `HistoryStoreTests` (S), `HistoryCopyTests` (C), `FeatureHistorySourceTests`
(SRC), `HistoryAccessibilityTests` (AX), `HistoryLayoutTests` (L), `HistoryRootTests` (R), `HistorySnapshotTests`
(SN), `PreviewTests`, `HistoryPerformanceTests` (PERF, nightly); `HistoryRouteMappingTests` (RM),
`WorkoutRepositoryContract.historyClauses` (K), `HistoryWeeksTests` (W), `SpokenWeightTests` (SW), UI
`WorkoutHistory` (nightly).

| Criterion | Tests |
|---|---|
| 1. Weeks and rows | P `twelveWorkouts_fourWeeksNewestFirst`, `row_readsWeekdayMinutesAndVolume`, `badge_countsTheRecords`, `headers_acrossAMonthAndAYear`, `weekStart_sunday_regroups`. S `run_firstModel_showsTheWeeks`. SN populated. UI |
| 2. Empty | P `noWorkouts_isTheEmptyState`. S `noWorkouts_showsTheEmptyState_andRoutesToToday`. RM `today_selectsTodayAndPushesNothing`. AX tree. SN empty. UI ("Go to Today") |
| 6. Routes | S `rowTapped_twice_isOneRoute`. R `root_runsTheStore_andHandsARouteOnce`. RM `workout_pushesItsDetailOnTheHistorysStack`; `TodayRouteMappingTests.openWorkout_pushesItsDetailOnToday`; `LibraryRouteMappingTests.openWorkout_pushesItsDetailOverTheHistory`. UI |
| 7. kg (list) | P `kilograms_convertTheVolumes`. S `unitsChanged_redrawsTheVolumes` |
| 8. AX3 (list) | L `longName_wrapsWhole`, `parts_layOutSanely`. SN populated at `.accessibility3` |
| N1 | K clauses 1 and 2 (GRDB, in memory). W `entry_fromAWorkout_computesItsTotals` |
| N2 | K clause 3. S `olderWorkoutEdited_redrawsItsRowAndALaterOnes`, `workoutDeleted_leavesTheList`, `workoutFinished_appears`, `unitsChanged_…`, `weekStartChanged_regroups`, `newRun_keepsTheModelOnScreen` |
| N3 | W, all six (Sunday start, 169-hour DST week, 23:30 on the last day, none) |
| N4 | `HistoryQueriesPerformanceTests` (`historyEntries` and the observation's fetch, 1,000 workouts, < 20 ms p95). PERF (< 30 ms) |
| N5 | SRC, seven tests, and `ModuleCopyTests` with no exemption |
| N6 | SRC `views_wearNoAccent` |
| N7 | AX `tree_isExactlyTheTable`, `rows_readTheirWords`, `targets_areAtLeast44Points`, `controls_sendTheirModelsRoutes`. P `spokenVolume_isPluralCorrect`. SW |
| N10 (list) | The GRDB read's `readable` and A5's rule, in `historyEntries()`' contract text |
| Failed | S `observationEnds_showsFailed`, `workoutsObservationEnds_showsFailed`. R `root_drawsTheFailedMessage` |

### References (6 new, I looked at each)

`populated` light and dark at `.large` and `.accessibility3`, `empty` light and dark at `.large`. Weeks newest first
under capitalised headers, the oldest week's rows (baselines) with no badge, the badge bold ink at the trailing edge
and under the name at AX3, every name whole. No existing reference changed.

### Sanctioned edits of others' tests

| File | Edit | Why |
|---|---|---|
| `LedgerAppKitTests/AppTabsTests.swift` | `(.history, "History")` → `(.history, nil)`; `selectingATab_swapsTheScreen` opens Settings on Program instead of reading History's heading; doc paragraph | C3 |
| `LedgerAppKitTests/TodayRouteMappingTests.swift` | `openWorkout_selectsHistory` → `openWorkout_pushesItsDetailOnToday` | C3, Q1 A |
| `LedgerAppKitTests/LibraryRouteMappingTests.swift` | `openWorkout_selectsTheHistoryTab` → `openWorkout_pushesItsDetailOverTheHistory` | C3, Q1 A |
| `LedgerAppKitTests/Adversarial/AppTabsAdversarialTests.swift` | `rootHeaders(of:)` includes `.history`; the pop-to-root check reads `rootHeaders(of: .history)` | C3 (History's root has no heading in a scene-less window, as Library's) |
| `LedgerAppKitTests/Adversarial/AppRootResetAdversarialTests.swift` | `titles[.history]` is `[]` | Same |
| `LedgerAppKitTests/Adversarial/TodayWiringAdversarialTests.swift` | `.openWorkout`: Today selected, Today's stack one deeper | Q1 A (found by the targeted run) |
| `Apps/LedgerUITests/HistoryVoiceOverAdversarial.swift` | `test_history_sessionTap_selectsTheHistoryTab` → `…_pushesTheWorkoutOnTheLibrary` | Q1 A (nightly) |
| `WorkoutRepository` conformers: `ProbedStores`, `LinkedSaveLogAdversarialTests.OldWrapper`, `HistoryModel+Repositories`, `ScriptedWorkouts`, `ProbedWorkouts` (new `ProbedWorkouts+History.swift`, `base` internal), `S13LoggedWorkouts`, `SabotagedWorkoutRepository`, `SiegeWorkoutRepository`, `SeparateWorkoutRepository`, `BriefWorkoutRepository` | the two new methods: forwards, or a stub | A protocol requirement (N1, N2) |
| `LedgerDependenciesTests/UnimplementedStubTests.swift` | the workout stub list gains `historyEntries()` and `observeHistoryEntries()` | Same |
| `LedgerPersistenceTests/WorkoutRepositoryTests.swift`, `InMemoryContractTests.swift` | one parameterised test each for `historyClauses` | K |
| `LedgerPersistenceTests/Performance/PerformanceBudget.swift` | `historyList = 20 ms` | N4 |

### Product lines

Non-blank, non-comment Swift in `LedgerKit/Sources` and `Apps`, excluding `LedgerTestSupport` and the UI tests,
against `98b340d`: **703 added, 10 removed, net 693** (planned about 840).

| File | Net |
|---|--:|
| `FeatureHistory/HistoryPresentation.swift` | 117 |
| `FeatureHistory/HistoryCopy.swift` | 85 |
| `FeatureHistory/HistoryStore+Sources.swift` | 63 |
| `FeatureHistory/HistoryStore.swift` | 52 |
| `FeatureHistory/Views/History+Previews.swift` | 50 |
| `LedgerDomain/Model/HistoryEntry.swift` | 50 |
| `LedgerPersistence/…/GRDBWorkoutRepository+History.swift` | 44 |
| `FeatureHistory/HistoryRoot.swift` | 39 |
| `FeatureHistory/Views/HistoryWeek.swift` | 30 |
| `FeatureHistory/HistoryModel.swift` | 29 |
| `LedgerDomain/Units/SpokenWeight.swift` | 27 |
| `FeatureHistory/Views/HistoryPage.swift` | 25 |
| `LedgerDomain/Rules/HistoryWeeks.swift` | 23 |
| `FeatureHistory/Views/HistoryScreen.swift` | 13 |
| `LedgerAppKit/Routes+History.swift` | 11 |
| `FeatureHistory/HistoryInput.swift` | 10 |
| `LedgerFakes` (in-memory, 6 + 3), `LedgerDependencies` stub (6) | 15 |
| `FeatureHistory/HistoryRoute.swift` | 5 |
| `LedgerAppKit` (`AppTabs` 4, `MainRoot` 1, `Routes` 1, `Routes+Today`/`+Library` 0) | 6 |
| `LedgerDomain/…/Repositories.swift` | 2 |
| placeholder `FeatureHistory.swift` | −3 |

Under the 500-line target? No: the PR is over it. The split considered is R8's: the query, weeks, spoken weights and
presentation first (about 380), then the store, views and app (about 310); the two commits follow it.

### Runs

- Host, `swift test`: LedgerDomainTests and LedgerPersistenceTests green (575 + 1,418 tests, one known issue already
  there); FeatureHistoryTests green with the nightly lane on (37 tests).
- Simulator, targeted through the lock on the PR plan (`TEST_RUNNER_LEDGER_SWEEP=pr`): `FeatureHistoryTests` and
  `LedgerAppKitTests`, 415 tests: the 6 references recorded on that run, and `TodayWiringAdversarialTests` failing on
  the old route, edited (above). Everything else green.
- The gate: below.

### Open questions, each with a recommendation

1. **The badge counts every record kind.** A progressing day reads "6 PRs". *Recommendation:* keep it (it is what the
   records list in S2 will show), or count exercises with a record instead, a presentation change only.
2. **The failed state's wording** (above). *Recommendation:* accept, as Pete accepted the Library's.

### Inputs for S2 and S3

- Replace `.workout`'s placeholder in `AppTabs.screen(for:)` with the detail root (`.id(destination)`); the UI tests
  `WorkoutHistory` and `HistoryVoiceOverAdversarial` find it by `history.workout.title`, so keep that identifier on
  the detail's heading or change both tests.
- `HistoryFixtures`, `HistoryScene`, `EndedHistory` and `ViewStop` in the test target are reusable.
- `WorkoutRepository` gained requirements: a new conformer needs `historyEntries()` and `observeHistoryEntries()`.

### The gate

- **Full gate on `093a4ec`: exit 0, "check.sh OK", 2,163 s.** Format 1 s, lint 80 s, iOS build 19 s, string catalogs
  1 s (7 checked; FeatureHistory 11 keys), iOS tests 1,707 s (17 test targets passed, PR plan), watchOS build 53 s,
  watchOS tests 299 s, coverage 2 s: FeatureHistory 402 / 402 lines (100 %), LedgerDomain 99.41 %, overall 98.56 %.
- The only commit after `093a4ec` is these notes. The nightly suites (`HistoryQueriesPerformanceTests`,
  `HistoryPerformanceTests`, UI `WorkoutHistory` and the edited `HistoryVoiceOverAdversarial`) were not run on the
  simulator; both performance suites passed on the host with the nightly lane on.

### S1 fix round 1 (G1, 2026-10-28): G2's F13-S1-1 to -3, as the orchestrator ruled

Commit `0bbf19e` fix(history): one language per spoken row, and "<1 min" for a workout under a minute.

- **F13-S1-1, fixed.** The spoken volume is now spoken in the locale the module's catalog answers in
  (`forCountedText`), with the lifter's region and digits. `HistoryPresentation.CountedTexts` works that locale out
  once per model, and every counted text and the spoken volume use it. `SpokenWeight.swift`'s doc now says a caller
  passes its catalog's `forCountedText(in:)` locale; the Domain API is unchanged. de_DE reads "58 minutes, 24.180
  pounds". G2's `spokenValue_speaksOneLanguage` (de_DE, ja_JP, ar_EG, fr_FR) passes as a plain test. The new
  `HistoryPresentationTests.spokenVolume_inGerman_speaksTheCatalogsLanguage` pins the German row.
- **F13-S1-2, fixed in History only.** A workout under 60 s, or one clamped to 0 s, reads "<1 min" on screen and
  "Under a minute" when spoken; 60 s still reads "1 min". There are two new keys, `HistoryCopy.underAMinute` and
  `spokenUnderAMinute`, so FeatureHistory now has 13 keys. **New wording for Pete:** "<1 min" and "Under a
  minute". G2's `underAMinute_doesNotReadZero` passes as a plain test, now with the exact texts.
  `HistoryCopyTests.underAMinute_drawnAndSpoken` is new.
  - **Today is separate code:** `TodayPresentation.recentRow` formats through FeatureToday's own
    `TodayCopy.duration(minutes:)`, so it is not shared with History. A workout from an earlier day that lasted
    under a minute still reads "0 min" in Today's RECENT; one from today reads its clock time. **Follow-up:** Today's
    RECENT takes the same "<1 min" rule.
- **F13-S1-3, left as built.** The test stays under `withKnownIssue`. Its comment names the follow-up "one numbering
  system per row (app-wide localisation chore)".
- **F13-S1-6** is noted for S2 (above, "Inputs for S2 and S3"). Neither `ProgramUpdateCancelAdversarialTests` nor any
  other file outside these was touched.
- **Net product lines:** 22 added, 5 removed, **net 17** in this round. The slice's total against `98b340d` is now 720
  added, 10 removed, **net 710**.
- **Host:** `FeatureHistoryTests` and `SpokenWeightTests` are green (51 + 4 tests, with the one known issue, F13-S1-3).
- **Full gate on `0bbf19e`: exit 0, "check.sh OK", 2,187 s.**

  | Step | Time |
  |---|--:|
  | lint | 90 s |
  | iOS build | 25 s |
  | string catalogs (FeatureHistory: 13 keys) | 1 s |
  | iOS tests (17 targets passed) | 1,748 s |
  | watchOS build | 28 s |
  | watchOS tests (8 targets passed) | 293 s |
  | coverage | 2 s |

  Coverage: FeatureHistory 420/420 (100 %), overall 98.58 %.
