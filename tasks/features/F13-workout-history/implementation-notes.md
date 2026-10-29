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
