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

### S1 fix round 2 (G1, 2026-10-28): G3's R1-1 to R1-4, as the orchestrator ruled

Commit `2154cfb` fix(history): pin equal writes, guard every line of a row, lower-case "under a minute".

- **R1-1.** `WorkoutRepositoryContract.historyClauses` has a fourth clause, "observeHistoryEntries emits nothing for a
  write to a workout that leaves every entry as it was". It runs on GRDB and in memory through the existing tests.
  - First, the workout is stored again in other units. That rewrites its `workout` row, so a table observation wakes,
    but no field of the entry changes.
  - Then a set that is not done gets another weight, which counts toward no total.
  - Neither write may emit within `StatsQueriesContract.quiet`. A delete afterwards must still emit.
  - **Mutant, run in a scratchpad copy only** (rsync of `LedgerKit`, since deleted): with `removeDuplicates { _, _ in
    false }` in `GRDBWorkoutRepository.historyObservation`, `historyClause_holds` fails. The output was: "a value after
    a write in other units: got Optional("a value"), expected nil". The mutant is killed. The product code was never
    edited for it.
- **R1-2.** `HistoryLayoutTests.longName_wrapsWhole` now requires the row to hold all of its text: the name's height
  plus the meta's (each measured as its own `Text` at the text column's width), plus `xs` and twice `l` of padding.
  - The row has no badge, so the column is the row's whole width at every size.
  - The control `longName_cutToOneLine_failsTheGuard` draws the same row under `.lineLimit(1)`. It fails the guard
    at `.large` and at `.accessibility5`, both in the PR sweep.
  - Targeted simulator run (PR plan, PR sweep): `HistoryLayoutTests` and `AppTabsTests` all passed, 9 of 9, the
    controls included.
- **R1-3.**
  - `AppTabsTests.selectingATab_swapsTheScreen` now pushes `.workout(id)` on Program and reads F13's own placeholder
    title ("History"), instead of F14's Settings placeholder.
  - **For whichever lane merges second (A10):**
    1. F14 adds `SettingsRepository.seedIfAbsent(_:)` with no default. **Done here already** (coordinator's
       addendum): FeatureHistoryTests' `EndedSettings` declares `func seedIfAbsent(_: Settings) async throws {}`, F14's
       signature from `a374175`, so F13 compiles whichever lane merges first.
    2. `LedgerKit/Package.swift` conflicts in its adjacent `FeatureHistory` and `FeatureSettings` target lines; keep
       both targets, each with `resources: [.process("Resources")]`.
    3. `scripts/coverage-thresholds.json`'s `required` is one line; keep both module names in it.
    4. Re-check `snapshotTestTargets`, `PreviewScan.registeredModules`, `AppTabs` and `MainRoot.tabs`, which are
       line-local but adjacent.
- **R1-4.** The spoken key is now **"under a minute"**, lower case like the words around it ("Wednesday, under a
  minute, 24,180 pounds, 1 PR"). The drawn key stays "<1 min". The catalog holds the lower-case key only, still 13
  keys.
- **R1-5, R1-6 and R1-7 go to S2:**
  - R1-5: `Weight.spoken` round-trips through `formatted(in:)`'s text, and `Volume.spoken` re-derives the value by
    hand. Expose the rounded `Decimal` instead. Its first product caller is S3.
  - R1-6: `HistoryFixtures.entries` should call `HistoryPreviewData.entries`.
  - R1-7: the detail root needs `.id(destination)` in `AppTabs.screen(for:)`.
- **Net product lines this round:** 1 added, 1 removed, **net 0**: the key's spelling. The rest is tests,
  `LedgerTestSupport` and notes. The slice total against `98b340d` stays **net 710**.
- **Full gate on `57ec63a` (final code): exit 0, "check.sh OK", 1,968 s.**

  | Step | Time |
  |---|--:|
  | lint | 71 s |
  | iOS build | 16 s |
  | string catalogs (FeatureHistory: 13 keys) | 1 s |
  | iOS tests (17 targets passed) | 1,585 s |
  | watchOS build | 17 s |
  | watchOS tests (8 targets passed) | 275 s |
  | coverage | 1 s |

  - Coverage: FeatureHistory 418/420 (99.52 %; the two lines differ from run to run with task timing), overall
    98.57 %.
  - An earlier gate on `2154cfb`, without the `seedIfAbsent` addendum, also exited 0, in 1,994 s.
  - The only commit after `57ec63a` is this paragraph.

## S2 — as built (G1 implementer, 2026-10-29)

Branch `feat/F13-history-detail`, from `main` at `e10cbe0` (F13 S1 #77 and F14 S1a #78 in). The specification is the
plan amendments' S2 (criteria 3, 5, 6 (screen part), 7 and 8 (detail parts) as restated, N8–N10, N13, N14, N6's detail
part), the rulings before G1, and the carried items F13-S1-6, R1-5, R1-6 and R1-7. Pete's questions are built to the
planner's defaults (Q1 A, Q5 A, Q8 A for this slice), each in one place.

### Commits

- `fac1f94` feat(history): one workout observed with its records, and spoken weights read from their number.
- `cfb9bd5` feat(history): a past workout's detail with its receipt, rows that open their history, and delete.
- this notes commit (docs only).

### What landed

Paths under `LedgerKit/`.

- **Domain.** `Model/RecordedWorkout.swift` (a `WorkoutState` with its `[PersonalRecord]`).
  `WorkoutRepository.observeWorkout(id:) -> AsyncStream<RecordedWorkout?>` (N8, A1): the workout as `workout(id:)`
  reads it with its records, now and after every change to either (an earlier workout's edit that moves its records
  included), `nil` while it is not stored, and a workout that can't be read ends the stream. Records are ordered by
  exercise id text, then the estimated 1RM first, on both implementations.
- **Persistence.** `GRDBWorkoutRepository+History.swift`: `observeWorkout(id:)` is a `ValueObservation` with
  `removeDuplicates` over `WorkoutRows.fetch(.one(id), strict: true)` plus `personal_record WHERE workout_id = ?`
  (`idx_pr_workout`), read strictly so damage ends the stream (N10).
- **Fakes and stub.** `InMemoryHistory.recorded(_:)`, `InMemoryWorkoutRepository.observeWorkout(id:)`,
  `UnimplementedWorkoutRepository.observeWorkout(id:)` (an empty stream).
- **Contract.** `LedgerTestSupport/Persistence/WorkoutRepositoryContract+Detail.swift`, `detailClauses` (3), run on
  GRDB (`WorkoutRepositoryTests.detailClause_holds`) and in memory (`InMemoryContractTests`): nil before the
  workout is stored and nothing for another workout's save; the value after its own edit, after an earlier workout's
  edit takes its records away, and nil after its delete, each equal to `workout(id:)` plus the stats' records read
  then; nothing within `StatsQueriesContract.quiet` for another workout's save or delete or a log append.
- **R1-5.** `Weight.shownValue(in:)` is the `Decimal` `formatted(in:)` prints (public, for S3's steppers);
  `Weight.spoken` reads it instead of parsing the text back, and `Volume.spoken` reads `value(in:)` (no longer
  private).
- **FeatureHistory**, new: `HistoryCopy+Detail.swift` (the receipt's 13 keys again, A3; delete, its alert, the
  failure alert, the unreadable state: 23 keys, the catalog now 36), `WorkoutDetailModel` (with `Deletion` and
  `Unreadable`), `WorkoutDetailPresentation` (with `WorkoutDetailInput`), `WorkoutDetailStore`, `WorkoutDetailRoot`;
  `Views/WorkoutDetailScreen.swift` (`WorkoutDetailScreen`, `UnreadableWorkout`), `Views/WorkoutDetailPage.swift`
  (`WorkoutDetailPage`, `UnreadableWorkoutPage`, `DeleteWorkoutButton`), `Views/Detail+Previews.swift` (4 states).
  `HistoryRoute` gains `.exercise(id)` and `.closeWorkout(id)`. `HistoryPreviewData.recorded(_:)` is the one builder
  of a history with its records; `entries(_:)` folds it.
- **LedgerAppKit.** `AppTabs.screen(for:in:)` draws `WorkoutDetailRoot(workout:)` with `.id(destination)` (R1-7).
  **F13-S1-6:** `onLibraryRoute` and `onHistoryRoute` carry the tab whose stack drew the screen
  (`(Route, AppTab) -> Void`), and `resolve(_:from:)` pushes there; `.closeWorkout(id)` pops only a `.workout(id)` on
  top of that tab's stack, as `.closeDay` does. `MainRoot` passes `$1` through.
- **Tests.** FeatureHistoryTests: `WorkoutDetailPresentationTests`, `WorkoutDetailStoreTests`, `WorkoutDetailRootTests`,
  `WorkoutDetailAccessibilityTests`, `WorkoutDetailLayoutTests`, `WorkoutDetailOrangeAuditTests`,
  `WorkoutDetailSnapshotTests`, `Support/DetailTesting.swift` (`DetailScene`, `DetailFixtures`, `DetailWorkouts`),
  `DetailParts` in `Support/HistoryParts.swift`; `HistoryCopyTests`, `PreviewTests`, `FeatureHistorySourceTests`
  extended. LedgerAppKitTests: `ReceiptParityTests` (N13), `HistoryRouteMappingTests` rewritten. LedgerDomainTests:
  `SpokenWeightTests.shownValue_isTheDrawnNumber`. Nightly UI: `Apps/LedgerUITests/WorkoutHistory.swift`.

No change to the project file, a test plan, `Package.swift` or `.github/`.

### Criteria → tests

Suites: `WorkoutDetailPresentationTests` (P), `WorkoutDetailStoreTests` (S), `WorkoutDetailRootTests` (R),
`WorkoutDetailAccessibilityTests` (AX), `WorkoutDetailLayoutTests` (L), `WorkoutDetailOrangeAuditTests` (O),
`WorkoutDetailSnapshotTests` (SN), `HistoryCopyTests` (C), `ReceiptParityTests` (PAR), `HistoryRouteMappingTests` (RM),
`WorkoutRepositoryContract.detailClauses` (K), UI `WorkoutHistory` (nightly).

| Criterion | Tests |
|---|---|
| 3. Receipt, header, rows | P `newest_inPounds_isTheReceipt`, `rows_areTheDomains_andRouteToTheirExercise`, `records_noneAndOne`, `skippedExercise_andPastAnHour`. S `run_firstModel_isThePresentations`, `rowTapped_twice_isOneRoute`. R `root_runsTheStore_andHandsARouteOnce`. AX tree, controls. RM `exercise_pushesTheHistoryOverTheDetail`. SN. UI |
| 5. Delete | S `delete_confirmedTwice_deletesOnce`, `delete_failed_keepsTheScreen`, `delete_notConfirmed_deletesNothing`, `deletedElsewhere_closes`. R `root_deletesOnce_andCloses`, `root_failedDelete_keepsTheDetail`. RM `closeWorkout_popsOnlyTheDetailOnTop`. UI (from History, and from Today: R4) |
| 6. Screen part | RM `workout_pushesItsDetailOnTheHistorysStack`, `lateRoute_landsOnItsOwnTab` (F13-S1-6) |
| 7. kg (detail) | P `kilograms_drawEveryWeightInKilograms`. S `unitsChanged_redrawsTheWeights`. AX `tree_readsTheLiftersUnits`. SN kilograms |
| 8. AX3 (detail) | L `accessibilitySizes_stackTheTiles`, `longName_wrapsWhole`, `parts_layOutSanely`. SN with records at `.accessibility3` |
| N8 | K (3 clauses, GRDB and in memory). S `workoutEdited_redraws`, `earlierWorkoutEdited_takesTheRecordsAway` |
| N9 | S and R as for 5; `runAgain_onAGoneWorkout_closesAgain` |
| N10 | S `unreadable_saysSo_andDeletes`. AX and L `unreadable` state. O `delete_wearsNone` |
| N13 | PAR `detail_isTheReceipt` over F10's three receipt previews and History's two, `workouts_coverWhatTheReceiptShows` |
| N14 | P `date_isInTheCalendarsTimeZone` |
| N6 (detail) | O `orange_isTheReceiptsOwn`, `delete_wearsNone`; source test: no file names the accent |

### Decisions and deviations

1. **The model is built on the main actor**, at each change, without the list's channel and `@concurrent` builder:
   a detail is a few dozen rows. The two sources are followed in one task group as the list's are.
2. **The detail draws its own heading** (the day in caption ink over the name in `.title`, `history.workout.title`),
   as an exercise's history does, under the pushed screen's bar with its back button; there is no "Done" (F10's
   header is the cover's). It scrolls whole: no pinned part.
3. **`.gone` draws the ground** while the app pops the detail. If the detail is not on top (an exercise's history was
   pushed over it), the close pops nothing; when that screen comes off, the detail's task runs again, finds the
   workout gone, and asks to close again (`runAgain_onAGoneWorkout_closesAgain`).
4. **Any source that ends shows the unreadable state**, the settings' too, as the list shows its failed state for
   either. A settings failure is then worded as the workout's; it was judged too rare for its own state.
5. **A delete's close replaces a waiting row route** (the row's history has nothing to open over).
6. **F13-S1-6 is fixed in the shell**, not in the stores: the route closure each stack builds carries its tab, so a
   route delivered late still lands where it came from. The resolve then also selects that tab (`open(_:in:)`).
7. **`AppTabsTests.selectingATab_swapsTheScreen` is re-pointed at Settings' placeholder**: the detail's root, like
   every feature root in a scene-less window, draws nothing there. F14 S1b, which replaces that placeholder, must
   re-point it again (A10).
8. **Line count under the band.** The slice is 649 net against the 700–900 aim (plan: about 790); the copy (161) and
   the store (130) came in as planned, the views and the presentation smaller. Nothing was compressed; S3 stays as
   planned.

### New wording for Pete

All in `HistoryCopy+Detail.swift`. From the plan (Q8 A): "Delete workout", "Delete this workout?", "It's removed from
your history, records and stats. This can't be undone.", "Delete", "Cancel"; "This workout can't be read." (N10).
**Not in the brief or plan:** the failed delete's alert, "Couldn't delete this workout" / "It's still in your history.
Try again in a moment." / "OK"; the unreadable state's line, "It stays in your history. You can still delete it." The
receipt's words are F10's, unchanged.

### Sanctioned edits outside the slice

| File | Edit | Why |
|---|---|---|
| `LedgerAppKitTests/AppTabsTests.swift` | `selectingATab_swapsTheScreen` pushes `.settings` on Program; doc paragraph | `.workout` draws the detail's root (no element in a scene-less window) |
| `LedgerAppKitTests/LibraryRouteMappingTests.swift` | each `resolve` passes `from:` the tab that asked; doc and one test name | F13-S1-6 |
| `WorkoutRepository` conformers: `ProbedWorkoutRepository`, `LinkedSaveLogAdversarialTests.OldWrapper` (in an extension, the suite is at the lint's 150 lines), `HistoryModel+Repositories`, `S13LoggedWorkouts`, `ScriptedWorkouts`, `ProbedWorkouts+History`, `SabotagedWorkoutRepository`, `SiegeWorkoutRepository`, `SeparateWorkoutRepository`, `BriefWorkoutRepository`, `EndedHistory`, `FailingOnceHistory` | `observeWorkout(id:)`: forwards, or an ended stream | A protocol requirement (N8) |
| `LedgerDependenciesTests/UnimplementedStubTests.swift` | the workout stub's `observeWorkout` ends at once | Same |
| `LedgerPersistenceTests/WorkoutRepositoryTests.swift`, `InMemoryContractTests.swift` | one parameterised test each for `detailClauses` | K |
| `LedgerDomainTests/Units/SpokenWeightTests.swift` | one test | R1-5 |

F13's own tests changed: `HistoryRouteMappingTests` (rewritten for `from:`, plus late route, exercise, close),
`FeatureHistorySourceTests` (the detail's store and root under the store rules, two screens may scroll, the views may
not name the presentation, `WorkoutEngine` or `ReceiptRow(`), `PreviewTests`, `HistoryCopyTests`, `HistoryTesting`
(R1-6: `HistoryFixtures.entries` calls `HistoryPreviewData.entries`).

### Product lines

Non-blank, non-comment Swift in `LedgerKit/Sources` and `Apps`, excluding `LedgerTestSupport` and the UI tests, against
`e10cbe0`: **net 649**.

| File | Net |
|---|--:|
| `FeatureHistory/HistoryCopy+Detail.swift` | 161 |
| `FeatureHistory/WorkoutDetailStore.swift` | 130 |
| `FeatureHistory/WorkoutDetailPresentation.swift` | 99 |
| `FeatureHistory/Views/WorkoutDetailPage.swift` | 58 |
| `FeatureHistory/Views/Detail+Previews.swift` | 49 |
| `FeatureHistory/WorkoutDetailRoot.swift` | 45 |
| `FeatureHistory/Views/WorkoutDetailScreen.swift` | 25 |
| `FeatureHistory/WorkoutDetailModel.swift` | 22 |
| `LedgerPersistence/…/GRDBWorkoutRepository+History.swift` | 18 |
| `LedgerFakes` (in-memory history 11, repository 3), `LedgerDependencies` stub (3) | 17 |
| `LedgerDomain` (`RecordedWorkout` 9, `Weight` 3, `Repositories` 1, `SpokenWeight`/`Volume` 0) | 13 |
| `LedgerAppKit` (`Routes+History` 6, `AppTabs` 1, `MainRoot`/`Routes+Library` 0) | 7 |
| `FeatureHistory/Views/History+Previews.swift` | 3 |
| `FeatureHistory/HistoryRoute.swift` | 2 |

Under the 500-line target? No: the PR is over it. The split considered is the two commits: the observation, its
contract and R1-5 first (about 50 product lines, nothing on screen), then the detail (about 600); the first alone
would ship an API with no caller.

### Runs

- Host, `swift test`: `FeatureHistoryTests` (76 tests in 12 suites, the one known issue F13-S1-3), the persistence
  history and detail clauses (GRDB and in memory), `SpokenWeightTests`, `UnimplementedStubTests`, the route mapping
  suites and `ReceiptParityTests`: all green.
- Simulator, targeted through the lock on the PR plan (`TEST_RUNNER_LEDGER_SWEEP=pr`, record missing):
  `FeatureHistoryTests` and `LedgerAppKitTests`, 478 tests: 473 passed, 1 skipped, and the snapshot tests failed only
  as they recorded the 8 references.

### References (8 new, I looked at each)

With records, without and in kilograms, light and dark at `.large`; with records at `.accessibility3` in light and
dark. The day over the name, TIME's orange label and the orange records line ("8 new PRs this session") as F10's
receipt draws them, the rows with their targets on the right and their chips, "Delete workout" in muted ink at the
foot. In kilograms every target, chip and the tile read kg ("5 × 90.7×5", "6,282"). At `.accessibility3` the tiles
stand one per row, each target under its name, and the name wraps whole. No existing reference changed.

### The gate and the nightly UI tests

- **Full gate on `cfb9bd5`: exit 0, "check.sh OK", 2,276 s.**

  | Step | Time |
  |---|--:|
  | format | 5 s |
  | lint | 102 s |
  | iOS build | 9 s |
  | string catalogs (FeatureHistory: 36 keys) | 1 s |
  | iOS tests (17 targets passed, PR plan) | 1,817 s |
  | watchOS build | 50 s |
  | watchOS tests (8 targets passed) | 287 s |
  | coverage | 2 s |

  Coverage: FeatureHistory 941 / 955 (98.53 %), LedgerDomain 99.44 %, overall 98.58 %.
- **Nightly UI, targeted through the lock on the Nightly plan:** `LedgerUITests/WorkoutHistory` (3 tests: list →
  detail → a row's exercise history → back → back; delete from History empties the list; delete from a detail pushed
  on Today from "View session" leaves RECENT with "No sessions yet", risk R4) and `HistoryVoiceOverAdversarial` (3,
  its session tap still finds `history.workout.title`): 6 of 6 passed.
- The only commit after `cfb9bd5` is these notes.

### Questions for Pete

Built to the planner's defaults; each can change in one place.

1. **Q1, where a past workout opens:** built to A, on the tab you tapped it from; back returns there.
2. **Q5, units on old workouts:** built to A, the detail draws every weight in your current units (a pound workout
   read in kilograms shows "5 × 90.7×5").
3. **Q8, deleting:** built to A, one alert, "Delete this workout?" / "It's removed from your history, records and stats.
   This can't be undone.", "Delete" and "Cancel".
4. **New wording** (above): the failed delete's alert, "Couldn't delete this workout" / "It's still in your history.
   Try again in a moment."; the unreadable workout's line, "It stays in your history. You can still delete it."
   *Recommendation:* accept.
5. **The records line counts every record kind**, as the receipt and the list's badge do (S1's question 1): a
   progressing day reads "8 new PRs this session". *Recommendation:* keep the three in step, whichever way you rule.
6. Q2–Q4 belong to S3 (the edit sheet) and are unchanged.

### Inputs for S3

- `WorkoutDetailStore`/`WorkoutDetailRoot` take the toolbar's "Edit" and the sheet; `DetailScene`, `DetailWorkouts`
  and `DetailFixtures` in FeatureHistoryTests are reusable.
- `Weight.shownValue(in:)` is public for the steppers' spoken values.
- `WorkoutRepository` gained `observeWorkout(id:)`: a new conformer needs it.
- F14 S1b replaces Settings' placeholder, on which `AppTabsTests.selectingATab_swapsTheScreen` now leans again.

### S2 fix round 1 (G1, 2026-10-29): G2's F13-S2-1 to -6, as the orchestrator ruled

Commit `3d7694a` fix(history): settings that end never blame the workout, a gone workout always closes, a confirmed
delete is never lost. All in `WorkoutDetailStore.swift`, plus tests.

- **F13-S2-1, fixed.** `follow` takes an `ended:` step per source. The settings' end keeps the last settings seen,
  or `Settings.default` when none came (`GRDBSettingsRepository.observe()`'s contract). Only the workout's own end
  (`workoutHasEnded`) shows "This workout can't be read." This replaces decision 4 above.
  `WorkoutDetailSettingsAdversarialTests.settingsEndAtOnce_doesNotBlameTheWorkout` and
  `.settingsEndAfterFirstValue_doesNotBlameTheWorkout` are plain tests now.
- **F13-S2-2, fixed.** `rebuild()` looks at the workout's nil first, so a delete made elsewhere closes the detail
  whatever else has ended. `settingsEnded_thenDeletedElsewhere_closes` is a plain test.
- **F13-S2-3, fixed.** The delete is one state, `Deleting`: `idle`, `confirmed`, `running`, `done`.
  - "Delete" is accepted only from `idle`.
  - `delete()` runs only from `confirmed`.
  - A run cancelled before its write goes back to `confirmed` with no reset, so the root's `.task(id: deletion)`
    performs it when the view comes back.
  - A run while another is in flight returns.
  - A failure goes back to `idle`, said in the alert, and may be tried again.
  - `deleteCancelled_isNotLostSilently` (which now also checks the workout is gone) and
    `deleteRunTwice_whileInFlight_deletesOnce` are plain tests.
- **F13-S2-4 and F13-S2-5, accepted as built.**
  - A late route also selects the tab it lands on (`open(_:in:)`).
  - One delete can hand the app two closes; the second pops nothing.
- **F13-S2-6.**
  - A covered detail, once its run sees the nil, is `.gone`, and `confirmDelete()` ignores a `.gone` detail. So a
    Delete on the frame before the pop is a no-op once the nil has arrived. Confirmed before the nil arrives, it
    deletes a gone workout, which does nothing, and then closes.
  - New nightly UI test `WorkoutHistory.test_coveredDetail_deletedElsewhere_popsOnReturn`:
    1. Open the detail on History and push its row's exercise history.
    2. Delete the same workout from Today's "View session".
    3. Return to History and go back.
    4. The detail has popped itself, and the list is empty.
- **Net product lines:** 18 this round (`WorkoutDetailStore.swift`), so the slice is **net 667** against `e10cbe0`.
- **Runs.**
  - Host: `FeatureHistoryTests` 87 tests in 14 suites, run three times. All green, with the one known issue
    (F13-S1-3).
  - Simulator, targeted through the lock:
    - PR plan: `FeatureHistoryTests`, 110 tests, 108 passed, 1 skipped, 1 expected failure (F13-S1-3), 0 failed.
    - Nightly plan: `LedgerUITests/WorkoutHistory`, 4 of 4 passed, the new test included.
  - The full gate was not run, as ruled.

### S2 fix round 2 (G1, 2026-10-29): G3's S2-R1-1 to -5, as the orchestrator ruled

Commit `1180741` fix(history): a delete cancelled behind a busy writer is run again, and the route origin is pinned.

**S2-R1-1, fixed.** In `delete()`, a run cancelled before its write sets `.confirmed` and makes the next `deletion`.
The root's `.task(id:)` therefore runs the delete once the screen is up. That holds even when the screen came back
while the cancelled run still waited for GRDB's writer and its own re-run had returned.
- `GatedWorkouts` (G2's support) gains `.busyWriter`. It waits for `open()` while ignoring cancellation, then checks
  cancellation, as GRDB's writer queue does.
- New test: `WorkoutDetailStoreTests.delete_cancelledBehindABusyWriter_runsAgain`.

**S2-R1-2, fixed.**
- `HistoryRouteMappingTests.workout_fromAnUnselectedTab_landsOnItsOwnStack` covers r1.
- `LibraryRouteMappingTests.exercise_fromAnUnselectedTab_landsOnItsOwnStack` covers r4.
- s2 was cheap to pin with a hosted test: the new `AppTabsRouteOriginTests.detailOnToday_sendsFromToday` (iOS) hosts
  the shell with the scene told it is active and a detail pushed on Today, over empty stores. The detail finds no
  workout and closes, and the close must arrive from `.today`.

**S2-R1-3, fixed.**
- `Deleting` is `idle`, `confirmed`, `running`. A successful delete returns to `.idle`, and the detail is `.gone`,
  which already refuses "Delete". If the workout came back (F17's late envelope), Delete would work again.
- New test: `runCancelled_keepsTheReceipt` (m12).
- The two new store tests sit in an extension of the suite, which keeps the struct under the lint's 150 lines.

**S2-R1-4, deferred to S3.** Move `spokenElapsed` and `startDay`, both catalog-free, beside `ClockText` and share
them with F10's receipt.

**S2-R1-5, fixed (tests only).**
- `WorkoutDetailDamageAdversarialTests.recordChangedAlone_emits` (GRDB): a record's `previous` is changed alone, with
  the count, workout, exercise and set rows unchanged. The stream must emit the new record.
- An edit through the repository could not kill g2, because every replay that moves a record also writes rows of
  tables the observation reads. So the change is written directly.
- `ownDamage_endsTheStream` now deletes with `try` and expects the list to lose the workout, in all four damage
  cases.

**Kills, proved in scratchpad copies.** LedgerKit was rsynced for the host mutants, and the whole worktree for s2.
Each mutant was rebuilt and run, then restored and checked with `diff -q`. Both copies, `.build` and `.derivedData`
included, were deleted afterwards.

| Mutant | Killed by |
|---|---|
| k1: no `deletion` bump on cancellation | `delete_cancelledBehindABusyWriter_runsAgain` ("deletion == 2") |
| m12: `follow`'s end runs when cancelled | `runCancelled_keepsTheReceipt` |
| r1: `Routes+History` `.workout` on `selectedTab` | `workout_fromAnUnselectedTab_landsOnItsOwnStack` |
| r4: `Routes+Library` `.exercise` on `selectedTab` | `exercise_fromAnUnselectedTab_landsOnItsOwnStack` |
| g2: GRDB region without `personal_record` | `recordChangedAlone_emits` (also G2's record-damage case) |
| s2: `AppTabs` hands the detail `.history` (simulator, through the lock) | `detailOnToday_sendsFromToday` ("tab: .history") |

**Net product lines.** 2 this round (`WorkoutDetailStore.swift`), so the slice is **net 669** against `e10cbe0`.

**Runs.**
- Host: FeatureHistoryTests (89 tests, the one known issue F13-S1-3), the persistence detail suites and clauses, and
  the History and Library route mapping suites. All green.
- Simulator, PR plan, through the lock, run twice, the second after a format-only edit of the new test:
  FeatureHistoryTests, `AppTabsRouteOriginTests`, `HistoryRouteMappingTests` and `LibraryRouteMappingTests` gave 124
  tests, 122 passed, 1 skipped, 1 expected failure (F13-S1-3), 0 failed. The first run also included `AppTabsTests`:
  130 tests, 0 failed.
- The full gate was not run, as ruled.

## S3 — as built (G1 implementer, 2026-11-02)

**Branch, a deviation:** the brief for this round named worktree `F13-s3` on `feat/F13-s3-edit-sets`. This agent is
isolated in its own worktree, and the harness refused git there, so the work is on `worktree-agent-aac5de9c23090001b`,
from the same `33048c5`. `feat/F13-s3-edit-sets` was left where it was, and can be fast-forwarded to this branch.

The specification is the plan amendments' S3 (criteria 4, 7 and 8 (sheet parts) as restated, N6's sheet part, N11, N12,
N15), the rulings before G1 (A4; A6 ruled into S3) and the deferred S2-R1-4.

### Commits

- `14e3c15` feat(history): fix a past workout's sets in a sheet, saved as one write, with spoken weights shared.
- `6693b60` test(history): the edit sheet hosted.
- this notes commit (docs only).

### Pete's questions, built to their recommended defaults (unanswered)

- **Q2 A:** "Edit" in the detail's bar opens every logged set in one sheet; a row still opens its exercise's history.
- **Q3 A:** only the weight and reps of logged sets. No removing a set, no logging a skipped one.
- **Q4 A:** a fix moves records, charts and stats, not the program's hold or advance. `SetEditing` reads no program.
- **Q5 A:** everything in the lifter's current units; a pound workout read in kg steps to the next kg multiple.

### What landed

Paths under `LedgerKit/`.

- **Domain.** `Rules/SetEditing.swift` (N11). `Weight.nextMultiple(of:_:)`, moved from `DayEditing+Fields.swift`, which
  now calls it. `WorkoutRepository.updateSets(_:of:)` (A4). `ClockText.spokenElapsed` and `ClockText.startDay`
  (S2-R1-4); F10's receipt and the detail share them.
- **Persistence and fakes.** `GRDBWorkoutRepository+History.swift`: `updateSets(_:of:)` and `replace`, which both
  `updateSets` calls write through. `RecordReplay.Scope(editing:of:)` takes several exercises, each once, in one order.
  In-memory and stub methods. `GRDBWorkoutRepository.now` went from `private` to internal for the extension.
- **FeatureHistory.** `EditSetsModel`, `EditSetsPresentation`, `EditSetsStore`, `EditSetsSheet`, `HistoryCopy+Edit`,
  `Views/EditSetsScreen`, `Views/EditSetsPage`, `Views/Edit+Previews` (4 states). The detail gets `edit` on its model,
  `edit()` and `editClosed(workoutGone:)` on its store, and the sheet on its root. The catalog holds 44 keys.
- **A6.** FeatureLibrary speaks weights through `Weight.spoken`: keys `PR %@`, `Up %@ over %lld weeks`, `Down %@ over
  %lld weeks` replace six fixed "pounds"/"kilograms" keys, so "Up 1 pound" reads right.

No change to the project file, a test plan, `Package.swift` or `.github/`.

### Decisions and deviations

1. **`updateSets(workoutExerciseID:sets:)` stays a protocol requirement, not a one-entry default** (plan A4 said
   default). It names no workout and `updateSets(_:of:)` needs one, so a default can't be written. Both go through one
   body on GRDB; a contract clause pins that the two give the same result.
2. **File names:** `EditSetsSheet` is the root (as `CreateExerciseSheet`), `Views/EditSetsScreen` the scroll view.
3. **The sheet takes the workout as the detail last read it**, and follows nothing while up. An edit arriving from
   elsewhere during the sheet is overwritten for the exercises saved (last write wins). Nothing writes that way on one
   device today; for F17/F28 to weigh.
4. **A workout deleted under the sheet waits:** the detail keeps its state and closes when the sheet comes down, so it
   is never popped from under a sheet. A save that hits `missingRow` raises an alert whose "OK" closes both.
5. **A cancelled save returns to editing silently** (as `CreateExerciseStore`), with no automatic re-run as the detail's
   delete has: the sheet's store goes with the sheet, and if the view lives, Save is on again.
6. **A set's number is among the exercise's logged sets.** An exercise with none shows "Nothing logged".
7. **A step and its way back restore the original only from a whole multiple of the step** (corrected in S3 fix
   round 1, F13-S3-7; this first said it always holds in the workout's own units). Off a multiple, in the workout's
   own units, there is no way back: 187 lb on 5 lb steps goes up to 190 and down to 185. A kg step on a pound workout
   never returns either: 225 lb goes up and back down to 101.25 kg on 1.25 kg steps. In both cases Save stays on, the
   sheet shows the new number, and only Cancel restores the original. No untouched set moves, and every result is a
   whole 10⁻⁷ g (ADR-007). Follows from Q5 A.
8. **Swiping away a changed sheet discards it, unasked:** N12 disables the swipe only while saving. Built as specified.
9. **Eight references, not the plan's seven:** `assertLedgerSnapshot` draws both themes at `.accessibility3`.
10. **Line count under the band:** 608 net against the 700–900 aim (plan about 685). A6 and S2-R1-4 removed code (FeatureLibrary
    −18, FeatureWorkout −15, the detail's presentation −13). Nothing was compressed.
11. **"One replay" is pinned indirectly:** one emission per observer and the right records on both exercises. No test
    counts replays.
12. **No S2 review nits rode along:** S2-R1-1, -2, -3 and -5 were already fixed in S2; only S2-R1-4 was left.

### New wording for Pete

All in `HistoryCopy+Edit.swift`: "Edit", "Edit sets", "Save", "Set 2 weight", "Set 2 reps". **Not in the brief or plan:**
"Couldn't save your changes. Try again in a moment."; "This workout was deleted" / "Your changes weren't saved."
*Recommendation:* accept.

### Sanctioned edits outside the slice

| File | Edit | Why |
|---|---|---|
| `WorkoutRepository` conformers in tests and `ProbedStores` | `updateSets(_:of:)`: forwards, a stub or (`HistoryModel+Repositories`) a model of it | A protocol requirement |
| `UnimplementedStubTests`, `InMemoryContractTests`, `WorkoutRepositoryTests` | one line or one parameterised test each | Same; the contract |
| `LibraryCopyTests` | `spokenRecord` takes a spoken weight; a new test for the change's singular | A6 |
| `WorkoutPresentationReceiptTests` | calls `ClockText.spokenElapsed` | S2-R1-4 |
| `WorkoutDetailOrangeAuditTests`, `WorkoutDetailLayoutTests`, `FeatureHistorySourceTests`, `PreviewTests`, `DetailTesting`, `HistoryParts`, `HistoryCopyTests` | the model's `edit`; the sheet under the same rules; `DetailWorkouts` counts saves | S3 |
| `Apps/LedgerUITests/WorkoutHistory.swift` | two helpers no longer `private`, for `WorkoutHistory+Edit.swift` | The class is at the lint's 150 lines |

### Product lines

Non-blank, non-comment Swift in `LedgerKit/Sources` and `Apps`, excluding `LedgerTestSupport` and the UI tests, against
`33048c5`: **net 608**. Over the 500-line target. The split considered: the Domain rule, the batched write and the shared
helpers first (about 130, nothing on screen), then the sheet; the first alone would ship an API with no caller.

### Runs

- **PR-sweep seconds:** the S3 suites plus `PreviewTests`, on the simulator through the lock with `TEST_RUNNER_LEDGER_SWEEP=pr`:
  34 tests in 5.6 s (plan 4–7 s). `FeatureHistoryTests` whole: 139 tests in about 10 s, before the 3 hosted sheet tests.
- **Nightly UI, through the lock:** `LedgerUITests/WorkoutHistory`, 5 of 5, including the new
  `test_editASet_showsInTheDetailAndTheList`. Run on `14e3c15`'s code, before `6693b60`, which only adds tests.
- **Host, nightly lane:** `RecordReplayPerformanceTests` passed with the new batched edit under the 250 ms budget, as did
  `LibraryPerformanceTests` and `HistoryPerformanceTests`, after A6.
- **Wall clock:** no new wall-clock assertion in a PR-plan test; the one budget is in the nightly suite.
- **References:** 8 new. I opened four (changed light and dark AX3, failed dark, unchanged light), not all eight. Save is the
  one orange, off in grey when unchanged, the failed line stands over it, and at AX3 the buttons stack under each field.
  No existing reference changed.

### The gate

**Full gate on `6693b60`: exit 0, "check.sh OK", 2,003 s.**

| Step | Time |
|---|--:|
| lint | 70 s |
| iOS build | 17 s |
| string catalogs (FeatureHistory: 44 keys) | 1 s |
| iOS tests | 1,595 s |
| watchOS build | 17 s |
| watchOS tests | 302 s |
| coverage | 1 s |

Coverage: FeatureHistory 1,416 / 1,465 (96.65 %), LedgerDomain 99.43 %, overall 98.47 %.

**Coverage fell for FeatureHistory**, from S2's 98.53 %. `SetEditing.swift` shows no uncovered line. What stays uncovered on the
PR plan includes the sheet's public init, its "Cancel" closure, the alert's "OK", and the root's sheet closure and
binding: a scene-less window presents no sheet. The nightly UI test exercises opening, stepping and saving, but neither
"Cancel" nor the alert's "OK".

**Not tested end to end:** the alert after a workout deleted under the sheet. The store and hosted tests stop at `.workoutGone`, and
`editClosed(workoutGone:)` is tested separately. Not run: this slice on a device, and the app by hand.

### Inputs for G2 and G3

- `WorkoutRepository` gained `updateSets(_:of:)`: a new conformer needs it.
- `EditScene`, `EditFixtures` and `EditParts` in FeatureHistoryTests are reusable.
- `WorkoutDetailEditTests.deletedUnderTheSheet_closesAfterIt` shows the nil waits by a `Task.yield`, a weak negative check.

### S3 fix round 1 (G1, 2026-11-02): G2's F13-S3-1 to -9, as the orchestrator ruled

Commit `f0fcbbc` fix(history): Edit after a save opens on what was saved, reps in the receipt's digits, and the sheet's
wiring tested. Then this notes commit.

**F13-S3-3, fixed.** The sheet now says how it came down: `EditSetsClosing` is `.cancelled`, `.saved(draft)` or
`.workoutGone`. It replaces `onClose(workoutGone: Bool)` and `editClosed(workoutGone:)`.
- **The rule.** On `.saved`, the detail keeps the draft and the workout its observation showed at that moment.
  "Edit" opens on that draft for as long as the observation still shows the same workout. Once any other value
  arrives (the save's own, or an edit from elsewhere), "Edit" opens on what is shown.
- **Why this rule.** The order of the save's value and the sheet's close doesn't matter. If the value lands first,
  the draft and the shown workout carry the same sets until the next value. Two saves in a row before any value
  lands chain correctly, because each compares against the value shown, not the request the sheet opened on.
- **Tests.** `EditSetsAdversarialTests.reopenedBeforeTheNextValue_opensStale` is now the plain
  `reopenedBeforeTheNextValue_opensTheSave`: the second sheet opens on the first's draft, the first fix stands, and a
  third "Edit" opens on the second draft. The new `afterTheNextValue_opensWhatIsShown` covers the other half. Once the
  stored value is shown, "Edit" opens on it, and an edit made elsewhere is what opens after that.

**F13-S3-5, fixed.** `EditSetsPresentation.row` writes reps with `String(_:)`, as `WorkoutSummary`'s chips do and
`WorkoutPresentation+Card` already did. In `ar_EG` the sheet shows "12", the same as the chip "187.5×12".
`digits_matchTheReceipt` is a plain test over all six locales. No reference changed (en_US digits are the same).

**F13-S3-1, fixed: FeatureHistory 99.31 % (1,459 / 1,469)** on the four targets' PR-plan run. The target was S2's
merge-gate 99.09 %. G2's run measured 98.50 % (1,443 / 1,465). The full gate's figure is below.
- **The sheet's item binding** is now `WorkoutDetailStore.editSheet`. Its get is `editing`, and its set of nil closes
  as "Cancel" does. The root binds `$store.editSheet` with no closures of its own. `sheetItem_nilClosesIt` sets the
  value and then nil. G2's `goneFlow_bothSignals_leaveOneClose` (F13-S3-9) now sends `editSheet = nil`.
- **The sheet's content** is `WorkoutDetailRoot.editSheet(_:over:)`. `rootsSheet_cancelReachesTheDetail` builds it
  over a running detail and activates "Cancel", and the detail's `editing` goes to nil.
- **Other lines now covered.**
  - The sheet's default `announce`: `appsAnnouncement_saysAFailure` hosts the sheet without an announce and lays it
    out after a failed save.
  - `EditSetsStore`'s log interpolation: `EditScene` takes a `logger`, enabled in that test.
  - `EditSetsPage`'s step-down closure: `adjustableDown_stepsTheWeightDown`.
- **Still uncovered from S3:**
  - The root's one-line `.sheet` content closure, since a scene-less window presents no sheet.
  - The sheet alert's "OK" closure, since no alert is presented without a scene.
  - The nightly UI tests reach neither.

**F13-S3-7, notes fixed.** Decision 7 above now says what G2 measured. Product behaviour is unchanged.

**Accepted as built (orchestrator).**
- **F13-S3-4: a stale snapshot overwrites a concurrent edit to the same exercise.** This is decision 3. Hand-off for
  F17/F28: `SetEditing.changes` hands over whole exercises. A sibling set edited by another writer after the sheet
  opened is reverted to the exact old `Decimal`. Exercises the sheet didn't change survive, because `replace`
  re-reads inside the write. A merge needs per-set changes or a version check.
- **F13-S3-6: "This workout was deleted" is said for a missing exercise.** That is unreachable today. It is an input
  for F17.
- **F13-S3-8: a swipe discards a changed draft without asking.** This is decision 8. **Question for Pete:** should
  a swipe on a changed sheet ask before discarding? *Recommendation:* keep it as is. Cancel discards without asking
  too, and only the unsaved draft is lost.
- **F13-S3-9: `editSheet = nil` after `.workoutGone` rebuilds over `.gone`.** SwiftUI doesn't send it after the
  store cleared the item, and one close still waits.

**Sanctioned edits of G2's tests:**
- These moved to `EditSetsClosing`: `EditSetsGoneAdversarialTests`, `EditSetsHostedAdversarialTests` (`closes` and
  `LockIsolatedCloses`) and `EditSetsOnDiskAdversarialTests`. The on-disk save closes with `.saved(sheet.draft)`.
- The two pinned tests are plain tests now, as ruled.
- The F13-S3-9 test's doc said "F13-S3-8". It is corrected.

**Net product lines.** 18 this round, so the slice is **net 626** against `33048c5` (S3 was 608). Nothing was
compressed.

**Runs.**
- **Host:** `swift test` on FeatureHistoryTests and `EditSetsOnDisk` passed: 123 tests, with the one known issue
  (F13-S1-3).
- **Simulator, PR plan, through the lock:** FeatureHistory, LedgerAppKit, LedgerPersistence and LedgerDomain tests,
  `TEST_RUNNER_LEDGER_SWEEP=pr`, run twice. Both exited 0. The second run (with the root's sheet test) gave
  1,424 + 614 + 166 + 400 tests, with the known issues only.
- **Lint:** `swiftformat --lint` and `swiftlint --strict` are clean on the 12 changed files.
- **Full gate on `f0fcbbc`, clean build products** (`.derivedData/Build` and `Results` removed first), through the
  lock: **exit 0, "check.sh OK", 2,213 s.**

  | Step | Time |
  |---|--:|
  | lint (and format) | 77 s |
  | iOS build | 110 s |
  | string catalogs | 1 s |
  | iOS tests | 1,662 s |
  | watchOS build | 50 s |
  | watchOS tests | 311 s |
  | coverage | 2 s |

  Coverage:
  - **FeatureHistory 1,457 / 1,469 (99.18 %).** That is at or above S2's 99.09 %, and up from G1's 96.65 % and
    G2's 98.50 %.
  - The two lines fewer than the targeted run are `HistoryStore+Sources` (S1 code: `follow` and `rebuild`). They
    depend on timing from run to run. S3's own uncovered lines are the same two in both runs.
  - FeatureLibrary 97.03 %, LedgerDomain 99.43 %, overall 98.62 %.
  - No FeatureWorkoutTests timeouts appeared in this run.

### S3 fix round 2 (G1, 2026-11-02): G3's S3-R1-1 to -4, as the orchestrator ruled

One fix commit, then this notes commit.

**S3-R1-1, fixed.** `Apps/LedgerUITests/WorkoutHistory+Edit.swift`.
- Before "Edit", the test reads the detail's moved tile (the element whose label ends in " lb moved").
- After Save, it waits with `XCTNSPredicateExpectation` for Save to stop existing, then for the tile's label to
  differ, all on the detail without navigating. Back on the list, it waits for the row's value to differ from the
  value read before.
- The two single reads right after the stepper's tap (the weight's value, Save enabled) are waits too. No value is
  read once after a wait that returns at once. One private helper, `expect(_:_:_:timeout:)`, builds each wait.
- Not mutation-checked: no run was made with the detail kept from updating.

**S3-R1-3, fixed in code.** `WorkoutDetailStore`.
- The last save's draft is now `Sources.lastSave`. The workout follower's value closure sets it to nil with each
  value. `editClosed(.saved)` sets it, and `edit()` opens on `sources.lastSave ?? recorded.workout`. The equality
  check against the shown workout is gone. The doc says "until the observation's next value arrives", and that is
  now exactly what happens.
- **Why it lives in `Sources`.** The follower's `keep` closure is formed in the task group's nonisolated child task,
  so it can't write a main-actor property of the store. It can write the `inout Sources` it is handed. A re-run
  resets `Sources`, and with it the draft. That changes nothing: `edit()` refuses until the run's first value, and
  that value would clear the draft anyway.
- **Orders checked:**
  - **The close before the save's value.** The close sets the draft, and the value clears it. "Edit" opens on the
    draft, then on what is shown (`reopenedBeforeTheNextValue_opensTheSave`, `afterTheNextValue_opensWhatIsShown`,
    both unchanged).
  - **The value before the close.** The value clears nothing, and the close then sets the draft, which equals what
    is shown. The next value clears it. Covered by the new `valueBeforeTheClose_opensTheSaveThenWhatIsShown`.
  - **Two saves before any value, merged by GRDB.** The second close replaces the draft, and the one merged value
    clears it. "Edit" then opens on the stored workout, which equals the second draft. This is the new end of
    `reopenedBeforeTheNextValue_opensTheSave`.
  - **Two saves whose values are not merged.** The first save's late value clears the second's draft, so "Edit"
    opens on S1 until S2 lands. The old rule did the same (S1 ≠ S0), so nothing changed. It is unlikely in practice,
    because a human reopening, stepping and saving takes far longer than GRDB's fetch.
- **A→B→A, tested without a second writer.** `backToTheShownValue_opensWhatIsShown` uses the scripted observation to
  yield the stored workout, then the original again. "Edit" opens on the original, not the old draft. Against
  `HEAD`'s store this test fails (`editing?.workout == Self.newest`), and it is the only one that does. All 10 in the suite pass on
  the new code.

**S3-R1-2, fixed.** These doc comments are re-flowed to 120 columns: `SetEditing.swift` (the type's doc and
`step(of:loggedIn:readIn:)`), `WorkoutDetailScreen.swift` and `EditSetsSnapshotTests.swift`. In SetEditing, "below 1."
is kept off a line's start, so it doesn't read as a Markdown list.

**S3-R1-4, accepted (orchestrator), no change.** `Weight.nextMultiple`'s `step > 0` guard can't be reached from
either caller. It is harmless, and its doc states the behaviour.

**Net product lines:** −3 this round (the store), so the slice is **net 623** against `33048c5`. Nothing was
compressed.

**Runs.**
- **Host:** `swift test --filter "EditSetsAdversarialTests|WorkoutDetailEdit"` exited 0, 15 tests. The mutation run
  against `HEAD`'s store had 1 failure, as expected.
- **Nightly UI, `-only-testing:LedgerUITests/WorkoutHistory`, through the lock:**
  - Runs 1 and 2 exited **65**. They were build failures: `CVarArg...` needs `any` under ExistentialAny. I fixed it
    to `String...`.
  - Runs 3 and 4 exited **0**, 6 of 6 tests each. `test_editASet_showsInTheDetailAndTheList` took 34.2 s and 33.5 s.
  - A comma's spacing was fixed after run 3 had started building. It is whitespace only.
- **PR plan, `-only-testing:FeatureHistoryTests`, `TEST_RUNNER_LEDGER_SWEEP=pr`, through the lock:** exited **0**, 168
  tests in 31 suites, with the one known issue (F13-S1-3).
- **Lint:** `swiftformat --lint` and `swiftlint --strict` are clean on the 6 changed Swift files.
- **Not run:** the full gate, which the orchestrator runs after merging main.
