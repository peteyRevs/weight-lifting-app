# F09 — implementation notes

Planning pass against `main` at `a526874` (2026-10-04). Read-only: nothing below has been built or run.
Paths that start with a module name (`LedgerDomain/…`, `LedgerAppKit/…`) are under `LedgerKit/Sources/`; all
others are from the repository root. "v1" is `design/prototype/Ledger.dc.html`, "v2" is
`design/prototype/Ledger v2.dc.html`.

Documentation looked up for this plan (sosumi, context7): `Text(timerInterval:pauseTime:countsDown:showsHours:)`
(iOS 16+), `Observations` (iOS 26+), `Tab` (iOS 18+), "Localizing package resources" (`defaultLocalization`),
swift-dependencies' `@ObservationIgnored @Dependency` in an `@Observable` class.

## Slice plan (planning agent, 2026-10-04)

Product code lines are non-blank, non-comment lines outside tests, `LedgerTestSupport`, `LedgerSnapshotTesting`,
docs and string catalogs. **LedgerFakes lines: 0 in every slice** (F09 needs no new fixture or fake; see
"Brief vs main", rows 15–16).

| Slice | Contents (files and types) | Criteria covered | Est. product lines | Depends on |
|---|---|---|---|---|
| **S1** tab shell, route mapping, first string catalog — `feat/F09-s1-tab-shell` | `LedgerAppKit/Routes.swift` (new): `AppTab` (today, program, library, history), `AppDestination` (the screens any tab's stack can push; starts with placeholder cases), `AppRouter` (`@MainActor @Observable`: selected tab, one path per tab, `open(_:in:)`). `LedgerAppKit/AppTabs.swift` (new): `TabView(selection:)` of four `Tab(value:)`, each a `NavigationStack(path:)` with one `navigationDestination(for: AppDestination.self)`; the Today tab hosts the existing `TodayPlaceholder` unchanged, the other three a `PlaceholderScreen`; tint `LedgerColor.accent`. `LedgerAppKit/MainRoot.swift` (new): owns the router, draws `AppTabs`, presents the Debug menu sheet (moved from `AppRoot`); the one view F08 and F10 later edit. `LedgerAppKit/PlaceholderScreen.swift` (new). `AppRoot.swift:26-32`: `.ready` draws `MainRoot`. `LedgerAppKit/Resources/Localizable.xcstrings` (new: tab titles, placeholder titles, the two decision-#29 strings that are literals at `AppRoot.swift:45-46`). `Package.swift`: `defaultLocalization: "en"`, `resources` on `LedgerAppKit`. `AppKit+Previews.swift`: cases "Tabs" and "Placeholder". Test-only: `LedgerTestSupport/Localization/StringCatalog.swift` (reads a module's catalog from the source tree; for all three lanes), `AppRouterTests`, `AppCopyTests`, `Apps/LedgerUITests/Tabs.swift` (nightly). | None of 1–13 alone. Product decision #1 (four tabs). It is where the routes of criteria 2, 5, 8, 10 and 13 land. | ~250 | `main`. **F08's root-branch slice and F10's cover slice need it merged first.** |
| **S2** Domain additions — `feat/F09-s2-domain` | `LedgerDomain/Rules/WeekCalendar.swift`: `nextScheduledDay(after:in:) -> ScheduledDay?` and the `ScheduledDay` value. `LedgerDomain/Units/Volume.swift`: `percentChange(from:) -> Int?`, `thousands(in:) -> String`. `LedgerDomain/Model/Loadable.swift` (new; standards §5 names the type, `main` lacks it). Tests in `LedgerDomainTests`. | Supports 4 and 5 (the "Next" lines) and 9 (the delta). | ~80 | S1 (lane order only). No other lane. |
| **S3** presentation — `feat/F09-s3-presentation` | `FeatureToday`: `TodayRoute.swift`, `TodayInput.swift`, `TodayModel.swift`, `TodayPresentation.swift` with `+Card`, `+WeekStrip`, `+Stats`, `+Recent`, `+OffSchedule` extensions, `TodayCopy.swift`, `Resources/Localizable.xcstrings`; the placeholder `FeatureToday.swift` is deleted. `Package.swift:126` (`resources`), `scripts/coverage-thresholds.json:15` (`"FeatureToday"` joins `required`). Tests: `TodayPresentationTests` (several files), `TodayCopyTests`, `FeatureTodaySourceTests`. No view, no change in the app. | The logic of 1, 4, 5, 6, 7, 8, 9, 10, 11; the model half of 3 (the resume label and the flip to Logged, from a `WorkoutState?` input). DoD: `TodayPresentation` at 100 %, no `Date()` / `Calendar.current`, every string in the catalog. | ~570 (over the target; see below) | S2. Pete's decisions 1 and 2 (defaults stated there). |
| **S4** views — `feat/F09-s4-views` | `FeatureToday/Views`: `TodayScreen.swift` (a `ScrollView` around `TodayContent`), `TodayHeader.swift`, `UpNextCard.swift`, `LoggedCard.swift`, `RestDayCard.swift`, `MessageCard.swift` (No-program and Block-complete; the brief lists `NoProgramCard.swift` and `BlockCompleteCard.swift`), `OffScheduleSheet.swift`, `StatsRow.swift`, `RecentList.swift`; `Today+Previews.swift` (registry `TodayPreview`, one case per state). The resume button's ticking label, `Text(timerInterval:)`, is drawn here too (frozen with `pauseTime` in previews and tests). `LedgerDesign`: `IconPillButton(_:systemImage:action:)` and `PrimaryButton(label:icon:action:)` taking a `Text`. `Package.swift:67` (`snapshotTestTargets`), `LedgerTestSupport/Previews/PreviewScan.swift:9`. Tests: `TodaySnapshotTests` (39 PNG), `TodayAccessibilityTests`, `PreviewTests`. Drawn from a `TodayModel` only; not yet in the app (the placeholder stays). | The drawn half of 1 and 3–10; 12; 13 (the label). DoD: previews and snapshots of all eight states; the accessibility non-functionals. | ~610 (over the target; see below) | S3. Pete's decisions 3 and 4 (defaults stated there). |
| **S5** store and wiring — `feat/F09-s5-store-wiring` | `FeatureToday`: `TodayStore.swift`, `TodayRoot.swift` (`init(onRoute:onTitleLongPress:)`). `LedgerAppKit`: `Routes+Today.swift` (maps every `TodayRoute`; unbuilt screens go to placeholders), `AppTabs.swift` (Today tab draws `TodayRoot`); `TodayPlaceholder.swift`, its preview case and `LedgerAppKitTests/TodaySnapshotTests.swift` with its 2 PNG are deleted. Tests: `TodayStoreTests`, `TodayRouteMappingTests` (`LedgerAppKitTests`), `TodayQueriesPerformanceTests` (`LedgerPersistenceTests`, nightly). | 2; 5 (sheet to route); 8, 10, 13 (routes); 11 (settings observed); refresh after a finish, a program save and a settings change; the performance non-functional. | ~230 | S4, S1. Independent of F08's root branch and F10's cover (either order; see Seams). |
| **S6** live session — `feat/F09-s6-live-session` | `TodayStore`: a fifth input, `WorkoutSessionClient.updates` (the live workout, and a finished one at once). Store tests with F10's fake. No view changes. | 3 end to end; the DoD's manual check (with F10). | ~45 | S5. **F10's first slice** (the protocol, the `workoutSession` key and its fake) merged. |

Notes on the plan:

- **Sizes.** S3 is about 570 lines and S4 about 610, over the 500 target and well under 1,000. The split considered
  for S3 was "strip, stats, recent" versus "cards"; not taken, because the cards share the week and day
  resolution with the strip and a half model would need stubs. The split considered for S4 was "screen, Up next,
  No program" versus "Logged, Rest day, Block complete, sheet"; it is possible (S4 is not wired into the app), at
  the cost of one more full implement, test and review cycle. Total for F09: about 1,790 lines in six PRs.
- **S2 could fold into S3** (five PRs, S3 at about 650 lines). Kept apart because it changes `LedgerDomain`'s
  public API, which the workflow serialises, and because F08 and F10 also add files to `LedgerDomain` this week:
  a small early PR keeps those rebases trivial.
- **Nothing before S6 needs `WorkoutSessionClient`.** S3 and S4 take the live workout as a plain `WorkoutState?`
  (a `LedgerDomain` type on `main`), so the resume label and the flip are built and tested before F10 lands;
  S5 passes `nil`. Only the store's subscription waits.
- **Every slice leaves the app working.** S1 keeps the placeholder Today inside the new shell. S2–S4 change
  nothing the app shows. S5 swaps the placeholder for the real screen. Before S6, a minimised workout shows
  "Start workout"; tapping it resumes through F10's use case (same source, rule 17), and a finished workout still
  flips the card to Logged through the history observation.

## Brief vs main

| # | The brief says | `main` has | The plan does |
|---|---|---|---|
| 1 | Routes are mapped in `Apps/Ledger/Sources/Navigation/TodayDestinations.swift` (F07-owned). | `Apps/Ledger/` holds `LedgerApp.swift` (15 lines) and assets. The root is `LedgerAppKit/AppRoot.swift:7-39`. No route type exists; the only `NavigationStack` is in the Debug menu (`LedgerDesign/Gallery/DebugMenu.swift:28`). F13 and F14 already name `LedgerAppKit/Routes.swift` (F13 brief:26, F14 brief:27). | S1 creates `LedgerAppKit/Routes.swift`; S5 adds `Routes+Today.swift`. |
| 2 | The tab bar exists (decision #1; architecture §4). | No `TabView` anywhere. `.ready` draws `TodayPlaceholder` (`AppRoot.swift:27`). | S1 builds the shell. |
| 3 | `FeatureToday/Resources/Localizable.xcstrings`. | No `.xcstrings` in the repo; no `defaultLocalization` (`Package.swift:72-80`); `FeatureToday` has no resources (`Package.swift:126`), so no `Bundle.module`. The only localised lookups are `LedgerDesign`'s VoiceOver words, keyed by their English text (`WeekStrip.swift:104-116`). `AppRoot.swift:45-46` holds literals. | S1 lands the first catalog and the pattern (orchestrator decision 3). |
| 4 | Fixtures and fakes in `LedgerTestSupport`. | `LedgerFakes` (ADR-008); `withTestDependencies` and `inMemoryStores(seed:)` are in `LedgerTestSupport/WithTestDependencies.swift:17, :72`. | Uses them; adds nothing to `LedgerFakes`. |
| 5 | `LedgerDomain/Calendar/WeekCalendar.swift`; add `nextScheduledDay(after weekday:in week:)` and `firstScheduledDay(in week:)` "if absent". | The file is `LedgerDomain/Rules/WeekCalendar.swift`. Neither function exists. It has `scheduledDay(on:in:)` (:127), `isBlockComplete(_:on:)` (:132), `weekIndex(for:)` (:53), `week(containing:)` (:82), `previousCompleteWeek(before:)` (:88), `firstDayOfWeek(containing:)` (:77), `weekday(of:)` (:71), `civilDate(of:)` (:47). | S2 adds one date-based function in place of the two weekday-based ones (orchestrator decision 5). |
| 6 | `WeekCalendar.currentWeekIndex(startDate:today:weekStart)`. | `WeekCalendar(startDate:weekStart:calendar:).weekIndex(for:)` (:36, :53). `Program.startDate` is a `CivilDate` (`Program.swift:17`). | Uses it. |
| 7 | `TimeEstimate.minutes(day:prescriptions:)`. | Exactly that (`TimeEstimate.swift:16`), prescriptions keyed by `SlotID`. | Uses it. |
| 8 | `ProgressionRules.prescribe`. | `prescribe(week:weekIndex:slot:exercise:units:)` (`ProgressionRules.swift:21`) needs the `Exercise`; a `Slot` holds only `exerciseID` (`Slot.swift:16`), so the preview rows' names need exercises too. | The store also observes `ExerciseRepository.observeAll()` (`Repositories.swift:21`). |
| 9 | `StatsQueries.sessionsThisWeek`. | `sessionsCompleted(in: Range<Date>)` (`Repositories.swift:122`). | Not called: the count comes from the week's workouts (row 12; orchestrator decision 7). |
| 10 | `weeklyVolume(week:)` and the previous complete week. | `weeklyVolume(in: Range<Date>)` (:120); the ranges come from `WeekCalendar`. | Called once, for the previous complete week. |
| 11 | `StatsQueries.recentWorkouts(limit:)`. | `WorkoutRepository.recent(limit:)` (:73) and `observeRecent(limit:)` (:86), returning whole `WorkoutState`s. `WorkoutSummary` is the receipt, not a list row (`WorkoutSummary.swift:4`). | Observes `observeRecent(limit: 5)`; rows come from `WorkoutState.name`, `.volume` (:100) and `.elapsed(at:)` (:111). |
| 12 | `StatsQueries.workoutsOn(dates:)`. | `WorkoutRepository.workouts(in: Range<Date>)` (:75), by start date (decision #26). | One read per refresh feeds the strip's done marks, the Logged card, sessions done, this week's volume and the sheet's "Logged" marks. |
| 13 | `ProgramRepository.activeProgram()` and `SettingsRepository.settings()` are live sequences. | Both exist under other names and are live: `observeActive() -> AsyncStream<Program?>` (:38) and `observe() -> AsyncStream<Settings>` (:93), over GRDB's `ValueObservation` (`GRDBProgramRepository.swift:86-93`, `GRDBSettingsRepository.swift:45-49`) and over `ObservedState` in the fakes. Each yields the current value first and keeps only the newest (`ValueObservation+AsyncStream.swift:13-25`). **A stream finishes silently when its read fails.** `StatsQueries` has nothing observable. | Consumed in the store; a stream that ends before its first value becomes the failed state. See "Liveness". |
| 14 | `WorkoutSessionClient.updates`. | Absent: `LedgerDomain/Protocols/Clients.swift` declares only haptics, notifications and live activities; `LedgerDependencies/Keys/DeviceKeys.swift` has no `workoutSession`. | S6 only. |
| 15 | "The F08 default program started 2026-09-14"; criterion 1 expects "five preview rows" for Lower A. | `Fixtures.seedProgram()` (`LedgerFakes/Fixtures/Fixtures+Program.swift:139-165`) is spec §6.4: 8 weeks, four days, 16 slots, week 8 a deload of three days, proven by `FixturesTests.seedProgram_isTheSpecs` (`LedgerDependenciesTests/FixturesTests.swift:42`). It starts 2026-08-17, so `Fixtures.now` (Wed 2026-09-16) is week 5. Its slots carry the prototype's start loads; F08's generated program will carry the catalog's (F08 brief:60). **Lower A has four slots** (`Fixtures+Program.swift:85-103`; spec §6.4), and F08's `both × four` is §6.4 verbatim (F08 brief:59). | Criteria 1–6 are testable today: the tests re-date the fixture (`Program.startDate` is `public var`, `Program.swift:17`) and take expected loads from `ProgressionRules`, so the start loads do not matter. Criterion 1 asserts **four** rows for Lower A (Upper A has five). A week-1 finished workout is built in the test with `SessionBuilder.build` (`SessionBuilder.swift:16`), because `Fixtures.history(weeks:)` stamps week 5. |
| 16 | Criterion 5: "a Saturday whose schedule is empty" in week 1. | In §6.4 Saturday is Lower B in weeks 1–7. | The test clears week 1's Saturday (`Week.schedule` is `public var`, `Week.swift:40`). |
| 17 | Criterion 8: the volume tile reads "0k". | `Volume.compact(in:)` always prints one decimal, "0.0k" (`Volume.swift:26-30`), as the prototype does. | Zero reads "0" + "k" (the criterion wins); any other value keeps one decimal. |
| 18 | `TodayPresentation.make(program:settings:today:workouts:live:stats:)`. | It also needs exercises, a calendar and a locale. SwiftLint's `function_parameter_count` (more than 5) fails under `--strict`, and the DoD allows no new suppression. | `make(_ input: TodayInput) -> TodayModel`. |
| 19 | Week strip cells read "Wednesday 16, today, planned". | `WeekStrip.Mark` is one of rest, planned, today, done (`WeekStrip.swift:12-21`). VoiceOver reads the caller's `accessibilitySummary` and one state word, pinned by `LedgerDesignTests/AccessibilityTreeSlice3Tables.swift:151-157`. | The component is used as it is (orchestrator decision 11). |
| 20 | "Reduce Motion disables the resume-timer pulse." | v2's Today has no pulse (v2:102-105); v1's `pulse` keyframes are unused (spec §8.8); no component draws one. | No pulse is built, so there is nothing to disable. |
| 21 | A Settings gear in the avatar spot. | `LedgerIcon` has six icons, all polylines, and no gear (`LedgerIcon.swift:6-16`); v1's gear is a curved path (v1:100). `IconPillButton` takes a `LedgerIcon` (`IconPillButton.swift:10`). | S4 adds `IconPillButton(_:systemImage:action:)` (Pete's decision 4). |
| 22 | The CTA counts with `Text(timerInterval:)`. | `PrimaryButton` takes a `String` (`PrimaryButton.swift:17`). | S4 adds an initializer that takes a `Text`. |
| 23 | "One of five cards" (v1 draws white and ink cards). | v2's Today is flat: no card chrome (v2:87-106). F06 ships `WeekStrip`, `StatTile` / `StatTileRow`, `Eyebrow`, `HairlineList` / `HairlineRow`, `PrimaryButton`, `PillButton`, `EmptyState`, `SheetChrome`; each takes `String`s the caller has localised (architecture §11). | The cards are composed from those, flat (Pete's decision 3). |
| 24 | Block complete has an "Open Program" button. | `TodayRoute` in the brief has no case for it. | Adds `.openProgram` (selects the Program tab). |
| 25 | Test names start with `test_`. | testing-strategy §6: `subject_condition_expectation`, no prefix, a sentence as the display name. | Renamed (see "Test plan changes"). |
| 26 | Two `LedgerPersistenceTests` "if not already in F05". | Already there: `StatsQueriesContract`'s `weeklyVolume` and `sessions` clauses (`LedgerTestSupport/Persistence/StatsQueriesContract+Weeks.swift:84-158`) run against GRDB and the fakes; `sessionsCompleted` counts every workout that started in the range, whatever its source. | Not added. |
| 27 | "Every query it runs < 50 ms" on 20,000 sets. | Timed on `main`: `weeklyVolume` and `sessionsCompleted` (`StatsQueriesPerformanceTests.swift:53-55`). **Not timed:** `recent(limit:)`, `workouts(in:)`, `active()`, `all()`, `load()`. The first two have their index checked (`QueryPlanTests.swift:32-40`). | S5 adds a nightly timing test for the untimed reads. |
| 28 | (Not in the brief.) | The Debug menu opens from a long press on the placeholder's title (`TodayPlaceholder.swift:11-18`, `AppRoot.swift:28-32`). The UI tests find `today.title` (`Apps/LedgerUITests/Smoke.swift:15-17`, `DebugMenu.swift:16-21`, `LaunchPerformance.swift:20-25`). | Kept through S1 and S5 (see "Test plan changes"). |
| 29 | Decision #15: the week starts on the locale's first weekday. | `Weekday.first(of:)` (`Week.swift:25`) has no caller in `Sources`; `Settings.default.weekStart` is Monday, and `Settings.swift:36-39` says "the app seeds it". Nothing does. | Not F09's to fix; orchestrator decision 14. |
| 30 | (Standards §5: `Loadable`.) | Not on `main`. | S2 adds it. |
| 31 | "24.2k", "+8%", "−3%", kg conversion. | `Volume.compact(in:)` returns "24.2k" in one string, but `StatTile` wants the value and the unit apart (`StatTile.swift:24`, gallery :121). No percent function. Rounding helpers are internal (`NumberText.swift:11-21`), and so is `Units.gramsPerUnit` (`Units.swift:14`). | S2 adds `Volume.thousands(in:)` and `Volume.percentChange(from:)`. |
| 32 | (Implied.) | `FeatureToday` is main-actor isolated by default (`Package.swift:13, :126`). | Pure types are declared `nonisolated`, as `LedgerDesign` does (`WeekStrip.swift:12, :24`). |

### Liveness

What `main` offers is in row 13: three of Today's inputs have a live stream (active program, settings, the five
most recent workouts), a fourth is available (`ExerciseRepository.observeAll()`), and the stats are one-shot.
That is enough; no new persistence API is needed.

- **A workout finishes.** `materialize` writes the workout and the slots' misses in one transaction
  (`GRDBWorkoutRepository.swift:49-62`), so `observeRecent` and `observeActive` both yield and Today rebuilds. In
  S6 the session's own update arrives too, and the model treats a finished session state as today's workout at
  once, whichever arrives first (criterion 3, "within one stream update").
- **A program is saved** (F08, F11): `observeActive` yields.
- **Settings change** (F14): `observe()` yields.
- **An older workout is edited or deleted** (F13) and is not among the five most recent: no stream yields.
  SwiftUI cancels and restarts a tab's `.task` when the tab disappears and reappears, and `TodayRoot` restarts it
  when the scene becomes active, so Today is fresh whenever the lifter comes back to it. The same restart
  handles a new day. S5 confirms the tab behaviour on the simulator; if a tab's content is kept alive, the
  shell tells `TodayRoot` when its tab is selected instead.
- **Writes during a live workout** touch only `workout_event`, which none of these observations read, so Today
  does not refetch per logged set.

The store funnels its streams into one serial refresh loop (a `TaskGroup` of readers that mark "inputs changed"
on a channel that keeps only the newest mark, and one consumer that reloads). A finish that fires two or three
streams then costs one or two reloads, never overlapping ones.

### What needs `WorkoutSessionClient`

Only two things: the store's subscription to `updates`, and showing "Resume" for a workout that is live now.
`TodayPresentation` and the views take a `WorkoutState?`, so they do not need the protocol. The flip to Logged
does not need it either (the history observation covers it); the session stream only makes it immediate.

### Routes to screens that do not exist yet

`Routes+Today.swift` (S5) maps every route. Until its feature lands, a route shows a `PlaceholderScreen` that
names the destination, so the app never has a dead button and a test can see the route arrive. `main` is not
distributed (TestFlight is F30).

| Route | Until its feature lands | Then |
|---|---|---|
| `.startWorkout`, `.resumeWorkout` | Placeholder "Workout" pushed on Today's stack. | F10 presents its cover. |
| `.openWorkout(id)` | The History tab is selected and a placeholder "Workout" detail is pushed there (F13 criterion 6 wants the History tab selected). | F13. |
| `.editWeek`, `.openProgram` | The Program tab is selected (a placeholder tab). | F11. |
| `.settings` | Placeholder "Settings" pushed on Today's stack. | F14. |
| `.setUpProgram` | Placeholder "Set up program". | F08; once its root branch lands, the No-program card is only seen in passing. |

### Presentation purity and cost

- `TodayPresentation.make(_:)` reads only its `TodayInput`: program, exercises by id, settings, the week's
  finished workouts, the five recent ones, the previous week's volume, the live workout, `now`, a calendar and a
  locale. The store fills `now`, the calendar and the locale from `@Dependency(\.date)`, `\.calendar` and
  `\.locale`. A source test fails on `Date()`, `Date.now`, `Calendar.current`, `Locale.current` or
  `TimeZone.current` anywhere in `FeatureToday`.
- Weights and volumes are never turned into `Double`. Loads print through `Weight.formatted(in:)`
  (`Weight.swift:101`), volumes through `Volume.formatted(in:)` (`Volume.swift:22`) and the new
  `thousands(in:)`; the percent is exact `Decimal` division inside `LedgerDomain`, rounded once. The feature
  only adds `Volume`s, which is exact. Dates go through `Date.FormatStyle` with the injected locale, calendar
  and time zone.
- Reads per refresh: four observed fetches (program, settings, recent 5, exercises) and two one-shot reads
  (`workouts(in:)` over the stats week joined with the program week, at most 13 days; `weeklyVolume(in:)` for
  the previous complete week). Row 27 says which are timed today.
- The strip, the tile and the card agree by construction, because one read feeds all three. Each strip day looks
  up its own date with `scheduledDay(on:in:)`, so a week start changed after the block began cannot shift the
  schedule. "Sessions planned" is the number of strip days with a session. "Week n of N" is the program week of
  today.

## Seams with F08, F10 and later features

Shared files, and exactly what F09 changes in each:

| File | F09's change | F08 / F10 touch the same file |
|---|---|---|
| `LedgerKit/Package.swift` | S1: `defaultLocalization: "en"` after `name:` (line 73); `resources: [.process("Resources")]` on `LedgerAppKit` (lines 169-183). S3: the same on `FeatureToday` (line 126). S4: `"FeatureToday"` in `snapshotTestTargets` (line 67). **No new dependency edge in any slice**, so `package-graph.expected.txt` does not change. | F08 at line 125 and line 67; F10 at lines 131-135 and line 67. One-line conflicts; the orchestrator rebases. |
| `scripts/coverage-thresholds.json` | S3: `"FeatureToday"` in `required` (line 15). The gate demands it once the module has executable lines (`scripts/coverage-gate.sh:106-107`). | F08 adds `"FeatureOnboarding"`, F10 `"FeatureWorkout"`, on the same line. |
| `LedgerTestSupport/Previews/PreviewScan.swift:9` | S4: `"FeatureToday"` in `registeredModules` (else `LedgerDesignTests/PreviewTests.swift:43-44` fails). | Each lane adds its module to the same set literal. |
| `LedgerAppKit/AppRoot.swift` | S1 only: lines 26-32, `.ready` draws `MainRoot`. | Neither should need it after S1. |
| `LedgerAppKit/MainRoot.swift` (new in S1) | Created in S1; not touched again. | F08 wraps the tabs in its "no active program" branch. F10 adds the cover. Different lines of one small file. |
| `LedgerAppKit/AppTabs.swift` (new in S1) | S5: the Today tab's content. | F11–F14 each replace their placeholder tab. |
| `LedgerAppKit/Routes.swift` (new in S1), `Routes+Today.swift` (new in S5) | S5 maps `TodayRoute`. | F10 owns the `.startWorkout` and `.resumeWorkout` cases: whichever of S5 and F10's cover slice merges second wires those two cases. F08 owns `.setUpProgram`. |
| `LedgerAppKit/AppComposition.swift` | None. The stores are already bound process-wide (`AppComposition.swift:39-43, :128-136`). | F10 binds `workoutSession` and adds its launch step. |
| `LedgerAppKit/AppKit+Previews.swift` | S1 adds two cases; S5 removes `.today`. | Possibly both. |
| `LedgerFakes` | None in S1–S5. | F08's `fourDayDefault` fixture; F10's session fake, which S6 uses. |
| `LedgerDomain` | S2: an extension appended to `Rules/WeekCalendar.swift`, two functions in `Units/Volume.swift`, a new `Model/Loadable.swift`. | New files of their own. No overlap. |
| `LedgerDesign` | S4: one `IconPillButton` initializer and one `PrimaryButton` initializer. Both additive; no existing reference image changes. | F10 adds `ReceiptLayout.swift`. |
| `Apps/LedgerUITests` | S1: a new `Tabs.swift` (nightly). `Smoke`, `DebugMenu` and `LaunchPerformance` are not edited by F09. | F08 owns their fallout once a fresh launch shows onboarding. |
| `TestPlans/*.xctestplan` | None: `FeatureTodayTests` and `LedgerAppKitTests` are already in the plans (`PR.xctestplan:99-103, :141-145`). | — |

Proposed merge order:

1. **F09 S1.** F08's Domain slice and F10's first slice (protocol, key, fake) do not touch the shell and can
   run alongside it.
2. F09 S2, S3, S4 in order, in parallel with the other lanes' own slices.
3. F08's root-branch slice and F10's cover slice: any time after S1, in either order.
4. F09 S5: any time after S4; independent of step 3.
5. F09 S6: after S5 and after F10's first slice.

Later features: F24 adds "HELD" to the preview rows and its own deload eyebrow, so `TodayModel`'s rows carry
`Prescription.isHeld` and `isDeload` from the start (`Prescription.swift:14-15`). F24 also lists
`FeatureToday/OffScheduleSheet.swift` in its Touches; it extends the sheet S4 builds. F15 will centralise
identifiers; S4 and S5 use testing-strategy §2.7's form (`today.title`, `today.upNext.startButton`,
`today.settingsButton`, `today.rest.editWeekButton`, `today.rest.offScheduleButton`,
`today.offSchedule.row.<n>`, `today.recent.row.<n>`).

## Decisions for Pete

Each has a default, so none blocks the start. Decision 4 is first used in S1 (the tab icons; the gear is S4),
decisions 1, 2 and 5 in S3, and decision 3 in S4.

**1. A workout is running for a different day than today's.**
This happens when you train off-schedule on a rest day and minimise the workout, or start Tuesday's session at
11:30 pm and it is now Wednesday.
- **A (recommended).** The running workout takes over Today's main card: its name ("Lower B — Hinge focus"), its
  exercises, and one orange button, "Resume · 12:40". Today never offers "Start workout" while something is
  running.
- **B (what the prototype does).** Today keeps showing what the calendar says. On a rest day you see "No session
  today" with no Resume button; the way back to your workout is "Train off-schedule", then the same day again.
  On a training day you see "Start workout" for the scheduled session, and tapping it asks "You have a workout
  in progress: Resume it / Discard and start new".
- By default: A.

**2. You did a scheduled session a day early.**
Wednesday is Lower A. On Tuesday, a rest day, you used "Train off-schedule" and did Lower A. On Wednesday:
- **A (what the brief says).** Today offers Lower A again, "Up next · Start workout", as if it were not done.
- **B (recommended).** Today shows it as logged: "LOGGED · WEEK 1", Tuesday's time and sets, "View session",
  "Next: Friday · UB". This week's Lower A is done, whichever day you did it.
- By default: A, because the brief states it. B is a one-line rule change in S3.

**3. Four of Today's five states were never designed in the dark style.**
Only "Up next" exists in the dark (v2) design. Logged, Rest day, No program, Block complete and the "Train
off-schedule" sheet exist only as v1's white cards. The plan draws them in the v2 style: flat on the dark
ground, hairlines, the same type as Up next, outlined pills for the secondary buttons. One visible choice: v1
prints "LOGGED · WEEK 1" in orange; the brief allows orange only on the main button, today's dot, "UP NEXT" and
the "+8%", so the plan makes that label grey.
- **Recommended.** Go ahead. The eight screenshots are attached to the S4 pull request, before anything reaches
  the app, and you ask for changes there.
- **Alternative.** Design those states first; S4 waits.
- By default: go ahead, grey label.

**4. Icons.**
The prototype draws its own four tab icons and its own gear. The plan uses Apple's stock icons: a bar chart
(Today), a calendar (Program), a dumbbell (Library), a clock (History) and the standard gear, with the selected
tab in orange as the prototype's tab bar shows.
- **Recommended.** Stock icons now. Custom ones can replace them later in one small change (they would be image
  assets, with re-recorded screenshots).
- **Alternative.** Custom icons from the start; S1 and S4 each grow by that design-system work.
- By default: stock icons.

**5. Three pieces of wording.**
- The resume button: "Resume · 3:00" (the brief, from v1) or "Resume workout · 3:00" (v2 and the design
  gallery). Recommended: "Resume · 3:00", which still fits at large text sizes.
- The large title when there is no program, and when the block is over: the brief defines the title only as the
  day's name or "Rest day". Recommended: "Today" in both cases.
- When Today cannot read your data (a damaged record): recommended "Can't show today right now" with "Your
  workouts are still on this iPhone. Open the app again to try once more.", matching the can't-open-your-data
  screen.
- By default: the recommended wording.

What you do **not** need to look at: how the tab bar and navigation are built; where strings are stored; the
placeholder screens that buttons open until F08, F10, F11, F13 and F14 land (nothing is distributed before
F30); how Today refreshes; the screenshot matrix; the names of the new helper functions; criterion 1's "five
rows" becoming four (Lower A has four exercises); "0k" versus "0.0k"; dropping a pulse animation that was never
designed.

## Decisions for the orchestrator

1. **S1 merges first; F08's root branch and F10's cover hang off `MainRoot`.** Recommend yes. Reason: one small
   file holds the three lanes' root changes, on different lines, instead of three edits to `AppRoot`'s switch.
2. **Routing pattern for all features.** Recommend: a feature exposes `public nonisolated enum XRoute: Hashable,
   Sendable` and `XRoot(onRoute: @escaping @MainActor (XRoute) async -> Void)`; a route is an intent, never a
   navigation call. `LedgerAppKit/Routes.swift` holds `AppTab`, one `AppDestination` enum for every pushable
   screen, and `AppRouter`; `Routes+<Feature>.swift` maps each feature's routes; every tab's stack registers
   `AppDestination` once. Reason: standards §2 ("a `Route` value the App target resolves"), architecture §12,
   and F12 needs one destination "on every tab stack" (F12 brief:35). This departs from architecture §4's
   "a `NavigationStack` keyed by that feature's `Route` enum": the stacks are keyed by `AppDestination`.
3. **Localisation pattern for all features.** Recommend: one `Resources/Localizable.xcstrings` per module with
   copy; `resources: [.process("Resources")]` on its target; `defaultLocalization: "en"` once; the key is the
   English text with its format specifiers, as `LedgerDesign` already keys its words and as every brief's "Copy
   (exact)" is written; `String(localized:bundle: .module, locale:)` for strings handed to `LedgerDesign` or
   built in presentation code, `Text(_, bundle: .module)` for text drawn directly, never a bare `Text("…")`
   (it looks in the main bundle); catalogs are edited by hand (worktree agents cannot use Xcode's sync), and a
   test per module checks the catalog against a literal key list through S1's `StringCatalog` helper. Reason:
   standards §7; F06 notes ("features keep their copy in their own string catalogs"); architecture §11.
4. **Store pattern for all features.** Recommend: `XRoot` owns the store in `@State` and runs it from `.task`;
   `XScreen(model:)` only draws a state and is what previews, snapshots and accessibility tests use;
   `XStore` is `@MainActor @Observable final class` with `@ObservationIgnored @Dependency` properties, a
   `Loadable<Model>` state, `run() async` (structured, no stored `Task`), synchronous intents; `XPresentation`
   is a `nonisolated` namespace of pure functions. Tests use `withTestDependencies { $0.inMemoryStores(seed:) }`
   and await changes with `Observations { store.state }` (iOS 26), never a sleep. Reason: standards §3, §4, §5;
   architecture §7; F07's finding that an appearance action inside a scroll view traps the preview renderer
   (F07 notes, S3 decision 6).
5. **`WeekCalendar.nextScheduledDay(after:in:)`, date-based, replaces the brief's two weekday-based helpers.**
   Recommend yes. Reason: it follows `scheduledDay(on:in:)` day by day, so it is right when the stats week and
   the program week differ, and one function gives both "later this week" and "next week".
6. **Criterion 1's "five preview rows" is read as four.** Recommend correcting the brief. Reason: row 15.
7. **Sessions done and this week's volume come from one `workouts(in:)` read; `StatsQueries` is used only for
   the previous week.** Recommend yes. Reason: the strip, the tile and the card cannot disagree, and it saves
   two reads; `WorkoutState.volume` is the same rule-34 sum, exact.
8. **Snapshot matrix: the brief's light and dark at `.large` and `.xLarge`, plus three AX3 images.** Recommend
   yes, in place of the six cells per state that testing-strategy §2.6 asks of screens. Reason: about 3.2 MB as
   planned against about 6 MB for six cells of full screens (an AX3 screen is about 190 KB); AX3 is covered
   where wrapping is at risk. A cheaper option is in "Test plan changes".
9. **The gear is an SF Symbol through a new `IconPillButton(_:systemImage:action:)`.** Recommend yes if Pete
   takes decision 4's default. Reason: adding a case to `LedgerIcon` would need curve support and would change
   F06's gallery tests and about a dozen reference images (`LedgerIcon.allCases` is drawn at
   `TokenPages.swift:153` and `Components+Previews.swift:74`).
10. **`PrimaryButton` gains an initializer that takes a `Text` (S4).** Recommend yes. Reason: the brief asks for
    `Text(timerInterval:)`, which cannot be passed as a `String`; previews and snapshots freeze it with
    `pauseTime`.
11. **Week strip speech.** Recommend keeping F06's component and its pinned tree: the mark is chosen by v1's
    precedence (done, then today, then planned, then rest; v1:1431), and the feature's `accessibilitySummary`
    says "Today" when today's mark is done. The brief's exact phrase "Wednesday 16, today, planned" is not
    reproduced. Reason: changing `WeekStrip.Mark` reopens a component F06 closed after three rounds.
12. **No resume-timer pulse.** Recommend dropping the brief's line. Reason: row 20.
13. **`TodayRoute` gains `.openProgram`; `.openWorkout` selects the History tab.** Recommend yes. Reason: rows
    24 and F13 criterion 6.
14. **Decision #15's locale week start is not implemented** (row 29). Recommend assigning it to F08, which
    anchors a new program's start date on it, or to a small F07 follow-up in `DatabaseLaunch`. Reason: until
    then a US lifter gets Monday weeks, on Today and in the block's start.
15. **`Loadable` lives in `LedgerDomain` and lands in S2.** Recommend yes; move it earlier if F08 or F10 needs
    it first. Reason: standards §5 defines it as a domain modelling rule; three private copies would drift.
16. **Catalog keys hold at most one plural value; " · " joins fragments.** Recommend yes ("%lld exercises" and
    "~%lld min" are two keys). Reason: a key with two counted values needs hand-written substitution entries,
    which are easy to get wrong without Xcode's editor.
17. **The Debug menu hook is `TodayRoot(onRoute:onTitleLongPress:)`,** as `TodayPlaceholder` has today.
    Recommend yes. Reason: the smallest change that keeps the UI tests' long press on `today.title` working.
18. **S1 and S5 must run `LedgerUITests/DebugMenu` by hand.** Recommend making it part of their gate. Reason:
    the PR plan runs only `Smoke` (`PR.xctestplan:160-162`), so a broken long press would pass the gate.
19. **Docs drift for the orchestrator to fix:** architecture §2 ("`Apps/Ledger/` … tabs, routes") and §4, and
    the F09 brief's Touches (`Apps/Ledger/Sources/Navigation/…`, `LedgerDomain/Calendar/…`).
20. **Whether to split S4, or fold S2 into S3** (see the notes under the slice table). Recommend neither.

## Test plan changes

**Renamed** (testing-strategy §6; suite `TodayPresentationTests` unless noted):

| Brief | Plan |
|---|---|
| `test_presentation_upNext_weekOneWednesday_LowerA` | `upNext_weekOneWednesday_isLowerAWithFourRows` |
| `test_presentation_weekStrip_doneTodayPlannedStates` | `weekStrip_marksDoneTodayPlannedAndRest` |
| `test_presentation_loggedCard_nextLine_laterThisWeek`, `…_nextWeek` | `logged_nextLine_laterThisWeek`, `logged_nextLine_nextWeek` |
| `test_presentation_restDay_nextUpLaterThisWeek`, `…NextWeek`, `…lastWeekOfBlock` | `restDay_nextUp_laterThisWeek`, `restDay_nextUp_nextWeek`, `restDay_lastWeekOfBlock` |
| `test_presentation_deloadMeta` | `upNext_deloadWeek_metaAndLoads` |
| `test_presentation_blockComplete_whenIndexPastWeeks`, `test_presentation_noProgram` | `blockComplete_whenWeekIndexPastTheBlock`, `noProgram_cardStripAndZeroStats` |
| `test_presentation_stats_deltaPositiveNegativeHidden`, `…_kgConversion` | `stats_delta_positiveNegativeHidden`, `stats_kilograms_convert` |
| `test_presentation_recent_fiveNewestFirst_todayLabel` | `recent_fiveNewestFirst_todayLabel` |
| `test_presentation_timeEstimate_usesDecision14Formula` | `upNext_minutes_areTimeEstimateMinutes` |
| `test_presentation_weekStartSunday` | `weekStartSunday_stripAndSessions` |
| `test_store_startWorkout_emitsRouteOnce` | `TodayStoreTests.start_doubleTap_emitsTheRouteOnce` |
| `test_store_liveWorkout_showsResumeAndFlipsToLoggedOnFinish` | `TodayStoreTests.liveWorkout_showsResume_thenLoggedOnFinish` (S6) |
| `test_store_offSchedule_pickEmitsStartForThatDay` | `TodayStoreTests.offSchedule_pick_emitsStartForThatDay` |
| `test_store_settingsChange_rerenders` | `TodayStoreTests.settingsChange_rebuildsTheModel` |

**Moved.** The brief's `TodaySnapshotTests` name is already used in `LedgerAppKitTests` for the placeholder
until S5 deletes it; the two live in different targets, so S4 can add its own. The brief's two
`LedgerPersistenceTests` are not added (row 26).

**Added.**
- S1: `AppRouterTests` (selection, push, pop, a destination opened in another tab), `AppCopyTests` (catalog
  keys), the `Tabs` UI test (nightly: four tabs, each shows its title).
- S2: `WeekCalendarTests.nextScheduledDay_*` (later this week, next week, last week, an empty week between,
  misaligned week start, a DST zone, before the block), `VolumeTests.percentChange_*` and `thousands_*`.
- S3: `live_otherDay_*` and `logged_doneEarlierThisWeek` (Pete's decisions 1 and 2), `beforeBlockStart`,
  `misalignedWeekStart_stripLooksUpEachDate`, `zeroVolume_readsZeroK`, `missingExercise_rowIsOmitted`,
  `lateNightWorkout_belongsToItsStartDay` (decision #26), `logged_lastWeek_hasNoNextLine`;
  `TodayCopyTests.catalog_holdsEveryKey` and `catalog_pluralRules`;
  `FeatureTodaySourceTests.sources_neverReadTheClockOrTheCurrentCalendar`.
- S4: `TodayAccessibilityTests`, one literal list of elements (label, value, traits) per state, read from
  `TodayContent`; the 44 pt targets; `PreviewTests` for `FeatureToday`.
- S5: `TodayStoreTests.workoutMaterialised_showsLogged` (no session client), `programSaved_rebuildsTheModel`,
  `streamEndsBeforeAValue_showsFailed`, `secondTapWhileRouting_isDropped`; `TodayRouteMappingTests`;
  `TodayQueriesPerformanceTests` (nightly, reusing `StatsQueriesPerformanceTests.seeded(in:)`, each read under
  `PerformanceBudget.statsQuery`).

**Snapshot matrix.** Measured on `main`: 124 reference PNGs, 4,308,969 bytes (`LedgerDesignTests` 121 /
4,296,245; `LedgerAppKitTests` 2 / 9,883; `LedgerWatchAppKitTests` 1 / 2,841). Text-dense references 402 px
wide cost 54–93 bytes per pixel row (hairline list 295 px = 23 KB; slice-3 sheet 954 px = 77 KB; all components
1,584 px = 86 KB; gallery 7,010 px = 493 KB; sheet at AX3 742 px = 69 KB).

| What | Cells | PNG | Est. bytes |
|---|---|---|---|
| `TodayContent` × {upNext, upNextDeload, logged, restDay, noProgram, blockComplete, recentEmpty} (S4) | light, dark × `.large`, `.xLarge` | 28 | ~2.2 MB (600–1,200 px tall, 45–95 KB each) |
| `TodayContent` × {upNext, restDay} at `.accessibility3`, dark (S4) | 1 | 2 | ~0.4 MB |
| `OffScheduleSheet` (S4) | light, dark × `.large`, `.xLarge`, plus dark AX3 | 5 | ~0.2 MB |
| `TodayContent` × resumeLive, timer frozen with `pauseTime` (S4) | light, dark × `.large`, `.xLarge` | 4 | ~0.35 MB |
| **Total** | | **39** | **~3.2 MB** (2.5–3.8) |

S5 deletes the placeholder's 2 PNG (9,883 bytes). A cheaper option, about 1.9 MB: full content for upNext,
noProgram and recentEmpty, and the card alone for the other five states, since the header, strip, tiles and
list are the same in each. The tab shell gets no pixel reference (the system tab bar's material is not a stable
reference); it has a preview render test and the `Tabs` UI test.

**Existing tests on `main` that are affected.**

| Test | What happens | Slice |
|---|---|---|
| `LedgerAppKitTests/PreviewTests` (registry equals the `#Preview`s) | Fails unless the registry grows with the new previews. | S1 adds the cases; S5 removes `.today`. |
| `LedgerUITests/Smoke.test_launchesToToday` (`today.title` exists, label "Today") | Passes through S1 (the placeholder is inside the Today tab). Passes after S5 on a fresh database only if the no-program title is "Today" (Pete's decision 5). Breaks when F08's root branch lands. | F09 keeps it green; F08 fixes it for onboarding. |
| `LedgerUITests/DebugMenu`, `LaunchPerformance` (nightly; long press on `today.title`) | Pass if the title keeps its identifier and the Debug long press. Not in the PR plan. | S1 and S5 run them by hand. |
| `FeatureTodayTests.module_name_matchesTarget` | Its subject, `FeatureTodayModule`, is deleted. | S3 deletes the test. |
| `scripts/coverage-gate.sh` | Fails with "FeatureToday has coverage now" until it is in `required`. | S3. |
| `LedgerDesignTests/PreviewTests` (`modulesWithPreviews` ⊆ `registeredModules`) | Fails once `FeatureToday` has a `#Preview`. | S4. |
| `LedgerAppKitTests/TodaySnapshotTests` and its 2 PNG | Their subject, `TodayPlaceholder`, is deleted. | S5 deletes them. |

## Risks

**Accessibility traps.**
- The accessibility helper reads no elements through a hosted `ScrollView` (F06 notes, slice 3, test
  infrastructure). Tests read `TodayContent`, the scroll view's only child; `TodayScreen` is covered by its
  preview render.
- A modifier applied from outside reaches every element inside a component (F06's `SetRow` finding). Name
  `WeekStrip` days and `StatTile`s through their `accessibilitySummary` parameters only.
- One intended tree per state, pinned by a literal test. Decide it before writing the views: each card is a
  container whose first element is its heading; `Eyebrow` is already a heading (`Eyebrow.swift:25`), so a card
  title that is also a heading gives the rotor two stops per card. Recommend the eyebrow as the card's one
  heading and the title as text; `today.title` is the screen's heading.
- The header's long press is Debug-only. Tests build Debug, so the pinned tree must show the title as a heading
  with no button trait.
- The resume label changes every second. Pin its VoiceOver label with `pauseTime`, and do not give it
  `.updatesFrequently` unless the tree test says so.
- The Up-next line "UP NEXT" plus "Week 1 of 8 · ~52 min" must stack at accessibility sizes, as F06's components
  do with `dynamicTypeSize.isAccessibilitySize`. `HairlineRow` already moves its accessory under the title at
  those sizes; F06's reviewer left to F09's review whether RECENT's chevron should stay trailing (F06 review
  R2-N6). Recommend accepting the component as it is.
- Orange audit (criterion 12): the selected tab is orange too (spec §8.4 lists "the tab icon"). The criterion is
  read as covering Today's content; the snapshot of each state is the evidence.

**Performance (architecture §15).**
- Five of Today's reads have no timing test on the 20,000-set fixture (row 27). They should be far under 50 ms
  (at most five workouts, one week, 224 exercises), but that is unproven until S5's nightly test runs. If
  `ExerciseRepository.all()` is slow, read only the day's exercises by id.
- The stores share one serial `DatabaseQueue` (`LedgerStores.swift:5-7`). On the very first launch the catalog
  seed runs after the first frame (`DatabaseLaunch.swift:104-122`) and Today's reads queue behind it (budget
  300 ms, `PerformanceBudget.swift:9`). First launch only.
- "Cold launch to Today < 600 ms" is measured at the root's first appearance (`AppComposition.swift:109-117`),
  before Today's data arrives, and is not gated (decision #30). S5 logs the first load's duration; a Diagnostics
  line is left to F26.
- A finish fires up to three streams; the serial refresh loop coalesces them.

**Build and tooling.**
- No string catalog has been built in this package yet. S1 must prove three things: `xcodebuild` compiles the
  catalog for a package target with `defaultLocalization` set; `scripts/check.sh --fast` (host `swift test`,
  `check.sh:163-171`, which builds every target) and `swift package describe` tolerate it; and the working tree
  is clean after a full gate (if `xcodebuild` rewrites the catalog, commit what it writes).
- The package also builds for macOS (`Package.swift:74-80`). iOS-only SwiftUI API needs `#if os(iOS)`
  (`fullScreenCover`, the navigation-bar toolbar placement).
- SwiftLint limits are errors under `--strict` (`.swiftlint.yml:52-60`, plus SwiftLint's defaults for closures
  and parameters): files up to 300 lines, type bodies 150, function bodies 40, closure bodies 30, five
  parameters. `TodayPresentation` is split into extensions for that
  reason, and views stay small (standards §7: 150 lines).
- Previews must draw `TodayScreen(model:)` from fixed inputs. The `date` dependency is pinned only in tests
  (`WithTestDependencies.swift:87`), so a store-driven preview of the seed program would show "Block complete"
  after 2026-10-12.
- `LedgerFakes` coverage is measured only from three test targets (`Package.swift:63`). Another reason F09 adds
  nothing there.

**Behaviour the brief leaves open** (defaults taken; each is a test in S3).
- Today is before the block's first day (travel west on day one, or a future start from F11): shown as a rest
  day whose next day is the first scheduled one.
- A wholly empty program week between today and the next session: the rest copy says "next Monday" although it
  is two weeks away. Accepted; new copy would be Pete's.
- Logged on the last week with no later day: the "Next:" line is omitted (the brief's "Next: week 9" would name
  a week the block does not have).
- A slot whose exercise is no longer stored: its preview row is omitted; `TimeEstimate` falls back to the slot's
  own values (`TimeEstimate.swift:14-15`).
- Off-schedule sessions can make "sessions this week" read 5/4 (accepted in the brief).
- The app left open on Today across midnight does not roll over until it is backgrounded or the tab is
  revisited.

**Cross-lane.** The three one-line conflicts in the Seams table; who wires `.startWorkout` when S5 and F10's
cover cross; the unimplemented locale week start (orchestrator decision 14).

## Inputs the implementer needs

### S1 — tab shell

Read: standards §2, §3, §7; architecture §3, §4, §11–§14; `docs/product-spec.md` §2.1 and §8.4, §8.7;
`design/prototype/LedgerTabs.dc.html` and `LedgerTabsDark.dc.html` (whole files, 40 and 39 lines: markup 10–16,
icons and labels 20–35); F07 notes "Slice S3" decisions 2, 6, 8 and open question 3; this file's Seams and
orchestrator decisions 2, 3, 17, 18.

Signatures on `main`:
- `AppRoot` — `LedgerAppKit/AppRoot.swift:7`; the state switch :24-38; the Debug sheet :28-32;
  `DatabaseUnavailableView` :42-52.
- `AppComposition.state` — `AppComposition.swift:47`; `diagnostics(health:)` —
  `AppComposition+Diagnostics.swift:13`.
- `TodayPlaceholder(onTitleLongPress:)` — `TodayPlaceholder.swift:7-23`.
- `DebugMenu(diagnostics:)` — `LedgerDesign/Gallery/DebugMenu.swift:8, :23`.
- `AppPreview` — `AppKit+Previews.swift:7-25`; `PreviewTests` — `LedgerAppKitTests/PreviewTests.swift:9-23`;
  `renderPreview(size:_:)` — `LedgerSnapshotTesting/PreviewRendering.swift:15`.
- `PreviewScan.sourcesDirectory` (the model for `StringCatalog`) —
  `LedgerTestSupport/Previews/PreviewScan.swift:12-15`.
- `Package.swift:72-80` (package), `:169-183` (`LedgerAppKit`).
- UI tests — `Apps/LedgerUITests/Smoke.swift`, `DebugMenu.swift`, `LaunchPerformance.swift`.

Keep: the Today tab's content is `TodayPlaceholder { … }` unchanged, so `today.title` and the long press work as
today. Pure value types (`AppTab`, `AppDestination`) are `nonisolated`.

### S2 — Domain additions

Read: ADR-007; decisions #15, #18, #26; spec §7.7 rules 34, 43, 46; v1:1130-1136 (the "Next" rule) and
1448-1454 (the rest note).

Signatures on `main`:
- `WeekCalendar` — `LedgerDomain/Rules/WeekCalendar.swift:30`; `init` :36; `weekIndex(for:)` :53;
  `weekday(of:)` :71; `scheduledDay(on:in:)` :127; `isBlockComplete(_:on:)` :132; the private `calendar` :34
  (reachable from an extension in the same file).
- `CivilDate` — `LedgerDomain/Model/CivilDate.swift:12`; `init?(_:in:)` :30; `adding(days:)` :59;
  `days(since:)` :65; `weekday` :70; `startOfDay(in:)` :76.
- `Program.week(at:)` — `Program.swift:64`; `Week.schedule` — `Week.swift:40`; `Weekday` — `Week.swift:7`.
- `Volume` — `LedgerDomain/Units/Volume.swift:7`; `compact(in:)` :27; the internal `value(in:)` :32;
  `Decimal.rounded(scale:_:)` and `roundedToInt(_:)` — `NumberText.swift:11, :19`.
- Existing suites to extend — `LedgerDomainTests/Rules/WeekCalendarTests.swift`,
  `Adversarial/WeekCalendar*AdversarialTests.swift`, `Units/VolumeTests.swift`.

Shape: `nextScheduledDay(after date: Date, in program: Program) -> ScheduledDay?` returns the first day after
`date`'s civil day, inside the block, on which the program schedules a session: its `CivilDate`, program week
index, `Weekday` and `DayTemplateID`. `Volume.percentChange(from previous: Volume) -> Int?` is `nil` when
`previous` is zero, else the change in whole percent, ties away from zero (24,180 against 22,400 lb is 8).
`Volume.thousands(in:)` is `compact(in:)` without the "k". `Loadable<Value: Sendable>`: `idle`, `loading`,
`loaded(Value)`, `failed(any Error)`.

### S3 — presentation

Read: the brief in full (the copy block is the catalog's key list); spec §3.5, §3.10 "Today (v2)", §6.5, §6.6,
§7.7 rules 34–35, 42–43, 45–46; decisions #14, #15, #17, #18, #25, #26; v1:1125-1136, 1218-1223, 1430-1471
(the logic); v2:553-566 (the sample values); this file's "Presentation purity and cost", Pete's decisions 1, 2
and 5, orchestrator decisions 7, 11, 13, 16, and the "Behaviour the brief leaves open" list.

Signatures on `main`:
- S2's additions, and `WeekCalendar.week(containing:)` :82, `previousCompleteWeek(before:)` :88,
  `firstDayOfWeek(containing:)` :77, `civilDate(of:)` :47.
- `ProgressionRules.prescribe(week:weekIndex:slot:exercise:units:)` — `Rules/ProgressionRules.swift:21`;
  `Prescription` — `Model/Prescription.swift:5`.
- `TimeEstimate.minutes(day:prescriptions:)` — `Rules/TimeEstimate.swift:16`.
- `DayTemplate.shortTitle`, `.name`, `.tag`, `.slots` — `Model/DayTemplate.swift:4-25`.
- `WorkoutState` — `Model/WorkoutState.swift:33`; `source` :36; `phase` :45; `doneSets` :90; `totalSets` :95;
  `volume` :100; `elapsed(at:)` :111; `WorkoutSource` :9.
- `Weight.formatted(in:)` — `Units/Weight.swift:101`; `Volume.formatted(in:)` — `Units/Volume.swift:22`.
- `Settings.units`, `.weekStart` — `Model/Settings.swift:5, :15`.
- `WeekStrip.Day` and `Mark` — `LedgerDesign/Components/WeekStrip.swift:12-37` (the model may hold
  `WeekStrip.Day` values directly).
- Fixtures — `LedgerFakes/Fixtures/Fixtures.swift:22` (locale), `:25` (calendar), `:34` (now), `:49` (date),
  `:66`, `:69` (settings); `Fixtures+Program.swift:56, :85, :106, :120` (days), `:139` (`seedProgram`), `:169`
  (`seedSession`); `Fixtures+History.swift:10` (`history(weeks:)`); `ExerciseCatalog.seed()` —
  `LedgerDomain/Catalog/ExerciseCatalog.swift:78` (`Fixtures.catalogByID()` is internal).
- `SessionBuilder.build(…)` — `Rules/SessionBuilder.swift:16` (to build a finished week-1 workout in a test).
- `StringCatalog` (from S1); `Package.swift:126`; `scripts/coverage-thresholds.json:15`.

Shape: `public nonisolated enum TodayRoute` is the brief's enum plus `.openProgram`. `TodayModel` holds the
header (date, title), `[WeekStrip.Day]`, the card (`upNext`, `logged`, `restDay`, `noProgram`,
`blockComplete`), the off-schedule list, the two tiles and the recent rows, every string final. The CTA is
`.start(route)` or `.resume(startedAt:)`.

### S4 — views

Read: standards §7; architecture §11; testing-strategy §2.5, §2.6; v2:67-129 (the whole Today screen: header
69-75, strip 77-85, Up next 87-106, tiles 108-117, RECENT 119-126); v1:361-447 for the states v2 lacks (rest
card 380-387, logged 388-399, tiles 422-433, recent 435-444) and v1:99-101 (the gear); F06 notes "Not built"
(lines 795-798, 1228-1241) and its slice-3 test-infrastructure note on scroll views; this file's Risks
(accessibility) and Pete's decisions 3 and 4.

Signatures on `main` (all under `LedgerDesign/Components/`):
- `WeekStrip(days:)` — `WeekStrip.swift:40`.
- `StatTile(value:unit:caption:delta:accessibilitySummary:)` — `StatTile.swift:24`;
  `StatTileRow` — :96.
- `Eyebrow(_:tint:)` — `Eyebrow.swift:16`.
- `HairlineList` — `HairlineList.swift:6`; `HairlineRule` — :22;
  `HairlineRow(_:detail:action:accessory:)` — `HairlineRow.swift:17`, without accessory :60.
- `PrimaryButton(_:icon:action:)` — `PrimaryButton.swift:17` (the whole view, :8-41, for the `Text` initializer);
  `PillButton(_:style:action:)` — `PillButton.swift:16`; `IconPillButton(_:icon:action:)` —
  `IconPillButton.swift:10`. Their tree cases to extend — `LedgerDesignTests/AccessibilityTreeTests.swift:150`.
- `EmptyState(_:body:)` and `(_:body:actionTitle:action:)` — `EmptyState.swift:15, :21`.
- `SheetChrome(_:cancel:onCancel:content:)` — `SheetChrome.swift:20`.
- `ledgerHitTarget()` — `ControlStyle.swift:7`; tokens under `LedgerDesign/Tokens/` (`LedgerFont.Role` —
  `LedgerFont.swift:11-19`, `LedgerSpacing`, `LedgerColor`).
- Test helpers — `assertLedgerSnapshot(of:named:devices:themes:typeSizes:)` —
  `LedgerSnapshotTesting/LedgerSnapshot.swift:73`; `assertPhoneSnapshot` — `PhoneSnapshot.swift:11`;
  `View.accessibilityElements(_:)` — `AccessibilityElements.swift:24`; the pattern of literal trees —
  `LedgerDesignTests/AccessibilityTreeTests.swift:13-95`.
- `PreviewScan.registeredModules` — `LedgerTestSupport/Previews/PreviewScan.swift:9`; `Package.swift:67`.

### S5 — store and wiring

Read: standards §3, §4, §8; architecture §7, §13; testing-strategy §2.6, §3; this file's "Liveness", "Routes to
screens that do not exist yet", orchestrator decisions 2, 4, 17, 18; F13 criterion 6; F10's brief, "Domain
changes" (`StartWorkoutUseCase`), for what `.startWorkout` will meet.

Signatures on `main`:
- `ProgramRepository.observeActive()` — `LedgerDomain/Protocols/Repositories.swift:38`.
- `SettingsRepository.observe()` — :93.
- `WorkoutRepository.observeRecent(limit:)` — :86; `workouts(in:)` — :75.
- `ExerciseRepository.observeAll()` — :21.
- `StatsQueries.weeklyVolume(in:)` — :120.
- Keys — `LedgerDependencies/Keys/StoreKeys.swift:13-41`; `logger` — `Keys/DeviceKeys.swift:51`;
  `LedgerLogger` — `LedgerLogger.swift:6`.
- `withTestDependencies` — `LedgerTestSupport/WithTestDependencies.swift:39`; `inMemoryStores(seed:)` — :72;
  `InMemoryStores.Seed` — `LedgerFakes/InMemoryStores.swift:15-60`.
- Performance fixture — `LedgerPersistenceTests/Performance/StatsQueriesPerformanceTests.swift:27`
  (`seeded(in:)`); `PerformanceBudget.statsQuery` — `PerformanceBudget.swift:14`.
- Shell — S1's `Routes.swift`, `AppTabs.swift`, `MainRoot.swift`.

Shape: the store keeps one pending route; a tap while one is pending is dropped, and `TodayRoot` delivers it
with `.task(id:)` and clears it when the shell's handler returns (criterion 2). `TodayRoot` restarts `run()`
when the scene becomes active.

### S6 — live session

Read: F10's brief "Domain changes" and criteria 10–12, and whatever F10's first slice merged (the protocol's
final shape, the key's name, the fake's API); the brief's criterion 3; this file's "Liveness"; Pete's
decision 1.

Signatures: `WorkoutState.startedAt` and `phase` — `LedgerDomain/Model/WorkoutState.swift:43, :45`;
`WorkoutPhase` — :4; `SessionBuilder.resumable(_:program:weekIndex:day:)` — `Rules/SessionBuilder.swift:73`;
S5's `TodayStore` and its refresh loop.

## Orchestrator rulings (2026-10-04)

Pete approved the M1 opening lanes (F08, F09, F10 in parallel) on 2026-10-04. The plan above is accepted with the
rulings below. Where a ruling and the plan disagree, the ruling wins.

**Slices.** S1 tab shell (`feat/F09-s1-tab-shell`) starts now and is on the critical path: F08's screen and root
slices and F10's cover slice wait for it. It also lands the localization scaffolding for every lane. S6 waits for
F10 S1 (the session seam), which starts now as well.

**The plan's decisions.**
- 1 accepted: S1 merges first; F08's root branch and F10's cover hang off `MainRoot.swift`.
- 2 accepted with one change: `onRoute` is synchronous, `@escaping @MainActor (XRoute) -> Void` (see "M1 shared
  conventions" below). One `AppDestination` for every pushable screen. S1 amends architecture §4, so its PR is
  flagged for Pete.
- 3 and 4: replaced by "M1 shared conventions" below. S1 owns the shared localization helper and writes the rule
  into standards §7. S1 must prove, by building, that a catalog with a plain string, a formatted string and a plural
  resolves from `Bundle.module` on the simulator and in the host `swift test` tier (or say what differs there).
- 5 accepted: one date-based `nextScheduledDay(after:in:)`. 6 accepted: criterion 1 reads four rows (brief amended).
- 7 accepted: one `workouts(in:)` read feeds the strip, the sessions tile and the volume.
- 8 accepted: the brief's matrix plus three AX3 images. 9 accepted, pending Pete's decision 4 (stock icons by
  default). 10 accepted: `PrimaryButton` gains a `Text` initializer in S4.
- 11 accepted: F06's `WeekStrip` and its pinned speech stay. 12 accepted: no pulse. 13 accepted: `.openProgram`;
  `.openWorkout` selects the History tab.
- 14: follows Pete's answer on first-launch units and week start; if he picks a region default, F08 S2 owns it.
- 15 accepted: `Loadable` in `LedgerDomain`, S2. 16 accepted: one plural value per key.
- 17 accepted: `TodayRoot(onRoute:onTitleLongPress:)`. 18 accepted: S1's and S5's gates include
  `LedgerUITests/DebugMenu`, run through the simulator lock.
- 19: docs drift is fixed in the slice that touches the area (S1: architecture §2 and §4).
- 20 accepted: S4 is not split and S2 is not folded.

**Pete's decisions.** Asked on 2026-10-04; until he answers, these hold: (1) a running workout takes over Today's
card; (2) the brief's rule (a session done a day early is offered again), with the recommendation to show it Logged
put to Pete before S3; (3) the four undesigned states are drawn flat in the v2 style and reviewed from S4's
screenshots; (4) Apple's stock icons for the tabs and the gear; (5) the recommended wording. The decision-#29
strings move into the catalog unchanged in S1 (they name the product, against the naming rule: put to Pete).

### M1 shared conventions (orchestrator, 2026-10-04; the same text is in the F08, F09 and F10 notes)

The three planners proposed the same patterns with small differences. These are the rulings; they hold for every M1
feature. F09 S1 lands the localization scaffolding and writes rules 1 and 3 into `docs/engineering-standards.md` §7 and
`docs/architecture.md` §4; once that slice is on `main`, the docs are the source and this block is a summary.

1. **Localization.**
   - One hand-written `Resources/Localizable.xcstrings` per module that has copy. Source language English. The key is
     the English text with its format specifiers. The target gains `resources: [.process("Resources")]`;
     `defaultLocalization: "en"` is set once in `Package.swift` (F09 S1).
   - All of a module's copy is resolved in its copy file(s): `<Feature>Copy.swift` (and `<Feature>Copy+<Area>.swift`
     when it grows), a `nonisolated enum` whose members return `String`, or `Text` only where the string embeds a live
     view such as a timer. No other file in the module holds a user-facing literal or a localized lookup: views,
     stores, presentation builders and `LedgerDesign` components receive `String`s.
   - Lines the Domain already formats (weights, volumes, receipt rows, the last-performance line, rest labels, clock
     text) and data (program and day names, catalog names) are shown as given and are not catalog entries.
   - One shared helper in `LedgerTestSupport/Localization/` and one test per module: every key the copy files use is in
     the catalog and the reverse; no lookup or user-facing literal outside the copy files; a plural key has `one` and
     `other`. A key holds at most one counted value; fragments are joined with " · ".
   - Shipped copy never contains the product name (`docs/product-decisions.md` › Naming).
2. **Stores.** `XRoot` (public; owns the store in `@State`; runs its async work from `.task` / `.task(id:)`),
   `XScreen(model:)` (only draws a state; what previews, snapshots and accessibility tests use), `XStore`
   (`@MainActor @Observable final class`; dependencies as `@ObservationIgnored @Dependency`; synchronous intents; no
   stored `Task` and no `Task { }` in a store or a view), `XPresentation` (a `nonisolated` namespace of pure functions
   from inputs to a display model). State is `Loadable<Model>` (`LedgerDomain`, lands with F09 S2) when the states
   are exactly loading / loaded / failed, otherwise a store-specific enum. Tests never sleep: they call the async
   method directly or await `Observations`.
3. **Routing.** A feature exposes `public nonisolated enum XRoute: Hashable, Sendable` and
   `XRoot(onRoute: @escaping @MainActor (XRoute) -> Void)`. `onRoute` is **synchronous**: a route is an intent, and the
   app resolves it (`LedgerAppKit/Routes.swift`, `Routes+<Feature>.swift`; every tab's stack is keyed by the one
   `AppDestination`). A feature never presents another feature. A feature with no exit the app must resolve
   (onboarding) has no route. A feature that presents itself over the tabs (the workout) exports its presenter and
   modifier; its start and resume entry points are synchronous intents as well, drained by its own `.task`.
4. **Shared one-line files** (`Package.swift` `snapshotTestTargets`, `scripts/coverage-thresholds.json` `required`,
   `LedgerTestSupport/Previews/PreviewScan.swift` `registeredModules`, and, added in the S1 touch-up after
   re-review n6, `LedgerAppKitTests/ModuleCopyTests.swift` `exemptions`): add only your module's name or entry. The
   orchestrator resolves the conflicts when it merges `main` into a branch.
5. **Accessibility.** One intended VoiceOver tree per component or screen, written down in these notes and pinned by a
   table-driven test before the tester starts (F06's lesson).
6. **Test names** follow `docs/testing-strategy.md` §6 (`subject_condition_expectation`, a sentence as the display
   name), not the briefs' `test_…` names.

## Slice S1 — tab shell (G1 implementer, 2026-10-04)

Branch `feat/F09-s1-tab-shell` at `a24eb60` (the plan). No commits. Paths that start with a module name are under
`LedgerKit/Sources/`; test paths are under `LedgerKit/Tests/`.

Documentation looked up (sosumi): `Tab` and its initializers, `TabView(selection:)`, `NavigationStack(path:)`,
"Localizing package resources", "Localizing and varying text with a string catalog". The iOS 27.0 SDK's interface was
read for `Tab(_:systemImage:value:content:)`: a `String` value takes the `StringProtocol` overload and is shown as
given; a literal would take the `LocalizedStringKey` overload and look in the main bundle.

### What landed

**LedgerAppKit (product)**
- `Routes.swift` (new): `AppTab` (`today`, `program`, `library`, `history`, in the bar's order), `AppDestination` (one case, `.settings`; deviation 3), `AppRouter` (`@MainActor @Observable`:
  `selectedTab`, `subscript(path:)` per tab, `open(_:in:)`). All internal: nothing outside the module uses them.
- `AppTabs.swift` (new): `TabView(selection:)` of four `Tab(_:systemImage:value:)`, each a
  `NavigationStack(path:)` over the router's path for that tab with the one
  `navigationDestination(for: AppDestination.self)`; `.tint(LedgerColor.accent)`. Today hosts `TodayPlaceholder`;
  Program, Library and History a `PlaceholderScreen`. A tab's root hides the navigation bar (it draws its own
  title); a pushed screen keeps the bar and its back button.
- `MainRoot.swift` (new): owns the router in `@State`, draws `AppTabs`, presents the Debug menu sheet (moved
  from `AppRoot`).
- `PlaceholderScreen.swift` (new): a title in `.display`, a heading, with the identifier its caller gives.
- `AppCopy.swift` (new): the module's copy file. `title(of: AppTab)`, `title(of: AppDestination)`,
  `databaseUnavailableTitle`, `databaseUnavailableBody`.
- `Resources/Localizable.xcstrings` (new): seven keys (four tab titles, "Settings", decision #29's two strings,
  wording unchanged).
- `AppRoot.swift`: `.ready` draws `MainRoot`; `DatabaseUnavailableView` takes its strings from `AppCopy`. The
  `.databaseUnavailable` and `.idle` branches are as they were.
- `TodayPlaceholder.swift:11`: `Text("Today")` became `Text(AppCopy.title(of: .today))` (deviation 1).
- `AppKit+Previews.swift`: cases "Tabs" and "Placeholder".
- `Package.swift`: `defaultLocalization: "en"`; `resources: [.process("Resources")]` on `LedgerAppKit`;
  `testResources["LedgerAppKit"] = [.process("Fixtures")]` (the catalog fixture). No dependency edge changed:
  `package-graph.expected.txt` is untouched and `scripts/check-package-graph.sh` passes.

**Test-only**
- `LedgerTestSupport/Localization/StringCatalog.swift`: reads a catalog from the source tree; `problems` (the
  catalog rules); `unresolvedKeys(in:)`; `resourceBundle(ofModule:)`; `specifiers(in:)`.
- `LedgerTestSupport/Localization/SwiftSource.swift`: a small reader of Swift sources (code, comments, string
  literals with their interpolations and the code before them).
- `LedgerTestSupport/Localization/CopyAudit.swift`: the module check (`findings`).
- `LedgerSnapshotTesting/PreviewRendering.swift`: the Mac host draws a preview in a window (deviation 2).
- `LedgerAppKitTests`, 55 new tests in 7 suites: `AppRouterTests` (7), `AppTabsTests` (4, iOS only),
  `AppCopyTests` (5), `CatalogFixtureTests` (5) with `Fixtures/Localizable.xcstrings`, `StringCatalogTests` (6),
  `SwiftSourceTests` (8), `CopyAuditTests` in three files (20), and `Support/TestCatalog.swift`. The target now
  has 93 tests in 17 suites on the simulator.
- `Apps/LedgerUITests/Tabs.swift` (2 tests; nightly, as the Nightly plan runs every UI test and the PR plan
  selects `Smoke`). No test plan and no project file changed.

**Docs**: standards §7 gains "Localization: one catalog and one copy file per module" (M1 convention 1, as
built); architecture §4 has the shell and the routing rule (convention 3), §2's `Apps/Ledger/` and `LedgerAppKit/`
lines say where the root, tabs and routes are, §12 points to §4.

### The localization pattern as built

The rule is standards §7, "Localization: one catalog and one copy file per module"; `LedgerAppKit` is the model. In
short, for a module `X` with copy:

1. `Package.swift`: `resources: [.process("Resources")]` on `X`'s target (`defaultLocalization: "en"` is already
   set).
2. `Sources/X/Resources/Localizable.xcstrings`, written by hand in Xcode's layout. Every key spells out its
   English text, `"state" : "translated"`: a plain key's text is the key; a counted key has `one` and `other`,
   one `%lld`, and its `other` form is the key.
3. `Sources/X/<Feature>Copy.swift`: a `nonisolated enum`; every lookup is
   `String(localized: "…", bundle: .module)` (plus `locale:` for a number, `comment:` if needed), its key a
   literal; a value in the key is a parameter of the member declared `Int` or `String`. Nothing but such
   lookups in that file; no lookup and no user-facing literal in any other file.
4. Two tests in `XTests`, copied from `LedgerAppKitTests/AppCopyTests.swift`:
   `#expect(try CopyAudit(module: "X", exempting: […]).findings == [])` and
   `#expect(try StringCatalog(module: "X").unresolvedKeys(in: #require(StringCatalog.resourceBundle(ofModule: "X"))) == [])`,
   plus, for each counted string, the copy member called with 1 and with several.

**Proof 1: a hand-written catalog in a package target compiles and resolves from `Bundle.module`.**
- *iPhone simulator (`xcodebuild`, iOS 27.0), in the gate.* `CatalogFixtureTests` reads
  `LedgerAppKitTests/Fixtures/Localizable.xcstrings` through the test target's own `Bundle.module`:
  a plain string (`fixture.plain` → "Resolved from the catalog"), formatted strings with two numbers and with a
  text (`fixture.week %lld of %lld` → "Week 3 of 8", `fixture.next %@` → "Next: Friday") and a plural
  (`%lld fixture sets` → "0 fixture sets", "1 fixture set", "2 fixture sets", "21 fixture sets"). The fixture's
  plain and formatted keys differ from their English text on purpose, so a lookup that missed the catalog would
  return the key and fail the test. `countedString_groupsDigitsByTheLocale` pins what `locale:` does: "1,234 fixture
  sets" for `en_US`, "1.234 fixture sets" for `de_DE` (the words stay English: the locale formats the number, the
  bundle picks the language).
- *The shipped catalog.* `AppCopyTests.builtBundle_resolvesEveryKey` asks the built
  `LedgerKit_LedgerAppKit.bundle` for each of the seven keys. The bundle holds `en.lproj/Localizable.strings`
  with exactly those keys (read with `plutil -p` from `.derivedData/Build/Products/Debug-iphonesimulator/`).
- *Mac host (`swift test`).* The same suites pass. Swift 6.4's `swift test` builds with Swift Build by default
  (`--build-system swiftbuild`), which compiles the catalog (`…xctest/Contents/Resources/LedgerKit_LedgerAppKit.bundle/
  Contents/Resources/en.lproj/Localizable.strings`). With the deprecated `--build-system native` the catalog is
  copied as it is (`Localizable.xcstrings` in the bundle): a plain lookup returns its key and "1 exercises" comes
  out for a count of one (measured in a scratch package, both ways).
- **Consequence for tiers.** Copy tests pass on the simulator and on the host with the pinned toolchain, so they
  need no `#if os(iOS)`. `scripts/check.sh --fast` runs only `LedgerDomainTests` and `LedgerPersistenceTests`
  (`check.sh:166-167`), so it builds the catalogs but runs no copy test: **a module's copy is proven by the full
  gate (the iOS simulator)**, or by `swift test --filter <Module>Tests` on the host. A copy test must never be run
  with `--build-system native`; it fails there by design.
- Two facts found on the way, both now rules in standards §7 and checked by `StringCatalog.problems`:
  `xcstringstool compile` emits **nothing** for a key with no localization (the form Xcode gives a key it
  extracted), and nothing for a unit whose state is `new`. So every key spells out its English text, marked
  `translated`; otherwise "the string comes from the catalog" would be true only of the source file.

**Proof 2: the catalog ⇄ code check is mechanical and two-way.** `CopyAudit` reads the sources, not a list a
person keeps. Each failure was shown once against the real module on the host tier (the check reads the source
tree, so the tier does not matter), then everything restored (SHA-256 of the four files compared) and passing;
the log is `…/scratchpad/f09s1/proof2-failures.log`:

| Change | `AppCopyTests.copy_followsTheStandard` reported |
|---|---|
| `AppCopy.swift` gains a lookup of "Start workout" | `AppCopy.swift:25: looks up "Start workout", which the catalog does not hold` |
| The catalog gains the key "Start workout" | `Localizable.xcstrings: "Start workout" is not looked up by a copy file` |
| `TodayPlaceholder.swift:11` back to `main`'s `Text("Today")` | `TodayPlaceholder.swift:11: a string literal outside the copy files: "Today"` |
| `PlaceholderScreen.swift` looks a string up itself | `PlaceholderScreen.swift:17: a localized lookup outside the copy files: localized:` (and the literal) |
| `AppCopy.swift` gains `NSLocalizedString(muscle, bundle: .module, …)`, a key that is not a literal | `AppCopy.swift:25: a lookup that is not String(localized:): NSLocalizedString` |

The same cases, and each catalog rule, are pinned on sources and catalogs built in memory (`CopyAuditTests`,
`StringCatalogTests`, `SwiftSourceTests`: 34 tests). An independent cross-check: the compiler's own extraction
(`AppCopy.stringsdata` in the build's intermediates) lists the same seven keys the audit derives, and every other
file of the module "no localized string"; for the fixture it lists `fixture.week %lld of %lld`, `fixture.next %@`
and `%lld fixture sets`, which is the `Int` → `%lld`, `String` → `%@` rule the audit applies.

How strict "a user-facing literal" is: outside a copy file, **any** string literal with a letter in it is a
finding, unless it is an accessibility identifier, an SF Symbol's name or a log line, or its file is exempt by
name with a reason in the module's test. `LedgerAppKit` exempts two files: `AppComposition.swift` (launch
arguments, the database's file name, the logger's category) and `AppComposition+Diagnostics.swift` (Debug only).
In a copy file the audit also refuses what it could not compare with the catalog: a lookup whose key is not a
literal (a key built from an enum's raw value), and any lookup API other than `String(localized:)`. I found that
gap in my own review while the first full gate was running (a key looked up that way, and missing from the
catalog, passed in silence), closed it with the table's last row and two tests, and ran the gate again; the gate
cited below is the second one. The same change keeps an interpolation's code out of its line's code, so that the
"written `bundle: .module`" rule also covers a lookup with a value in its key, which the first version skipped.
Limits, for the reviewer: the audit reads text, not types. It does not see a string built without a literal
(`String(describing:)`), a literal inside a regex literal, or copy in a file that is exempt; an exemption is
per file, so an exempt file is not checked for literals at all (lookups there are still findings), and
Debug-only code is exempted by file, not by `#if DEBUG` region.

**Proof 3: Xcode is not required, and the build does not rewrite the catalog.**
- Both catalogs were written in an editor and compiled by `xcodebuild` (the gate) and by `swift test`; the
  project was never opened in Xcode, and `project.pbxproj` is untouched.
- The full gate (below) built and tested both catalogs on the iOS simulator and left them byte-identical: their
  SHA-256 sums taken before the gate were checked after it (`shasum -a 256 -c`: both OK), and `git status --short`
  after the gate lists the same files as before it. The earlier simulator runs and the host runs left them
  untouched as well.
- What Xcode's own catalog sync would do was emulated on scratch copies with the tool the build uses,
  `xcrun xcstringstool sync`, fed the compiler's `.stringsdata` of this build: both catalogs came back
  byte-identical (`cmp`), because the code's keys and the catalog's agree. When the sync does have something to
  write (a key added to the scratch `.stringsdata`), the only other difference is the last byte: Xcode writes no
  newline at the end of the file, and the hand-written catalogs have one. Not verified: opening the project in
  the Xcode app itself.

### The shell's intended VoiceOver tree

1. **The selected tab's screen.** In S1 that is one element: the screen's title, a heading. Today: "Today"
   (`today.title`, the placeholder's, unchanged). Program, Library, History: the tab's title (`program.title`,
   `library.title`, `history.title`).
2. **A pushed screen**: the system's back button, then the screen's title, a heading (`settings.title`). Nothing
   in S1's interface pushes one; the router does.
3. **The tab bar**: four tab buttons in the order Today, Program, Library, History, each read by its title; the
   selected one is marked selected. The role and the position ("Tab, 1 of 4") are the system's words.

Pinned: (1) by `AppTabsTests.selectedTab_showsItsOwnScreen` (label; traits exactly heading and static text; no
value), on the shell hosted in a window on the simulator; (2) the title by `AppTabsTests.destination_opensOnEveryTab`
and `openedDestination_staysOnItsTabsStack`; (3) by `LedgerUITests/Tabs.test_fourTabs_todaySelected_inTheBarsOrder`
(the buttons of the one tab bar, their labels, their left-to-right order, `isSelected`). Not pinned by a test: the
system's words for a tab, and the back button (a hosted view's tree holds neither the tab bar nor the navigation
bar; the one-off experiment below saw the back button, labelled "Back", and used it).

### Decisions and deviations

1. **`TodayPlaceholder.swift:11` changed by one line**, against "the Today tab hosts the existing
   `TodayPlaceholder` unchanged" (plan, S1 row; criterion 2). `main` has `Text("Today")` there
   (`git show a24eb60:LedgerKit/Sources/LedgerAppKit/TodayPlaceholder.swift`, line 11): a literal outside the copy
   file, which SwiftUI looks up in the app's main bundle. Left alone, criterion 4 ("every string the shell shows
   comes from LedgerAppKit's String Catalog") would be false for the one string Today shows, or the audit would
   need an exemption for a real user-facing literal. It now reads `Text(AppCopy.title(of: .today))`. What the tab
   shows is unchanged: `TodaySnapshotTests` passes against M0's two references, untouched; the identifier and the
   long press are as they were.
2. **`LedgerSnapshotTesting/PreviewRendering.swift` is outside the slice's file list.** On the Mac host
   `renderPreview` drew with `ImageRenderer`, which traps on the shell: "SwiftUICore/Logging.swift:232: Fatal
   error: no current update to enqueue action to" (host run 1, `PreviewTests.preview_renders(.tabs)`; the whole
   test process died). Narrowed in a scratch package: a `TabView` alone, a `TabView(selection:)` and a
   `NavigationStack(path:)` alone all render; a `NavigationStack(path:)` inside a `Tab` traps. The host now hosts
   the preview in a window (`NSHostingView`), as iOS has since F07 S3 (its decision 6). The iOS and watchOS paths
   are untouched, so nothing the gate runs changed. On the host all 26 previews of the three modules render
   through the new path (20 `LedgerDesign`, 4 `LedgerAppKit`, 2 `LedgerWatchAppKit`). The alternative, leaving
   the `.tabs` case out on the host, would have to be repeated by every preview that contains the shell (F08's
   root branch, F10's cover).
3. **`AppDestination` starts with one case, `.settings`**, not the plan's "placeholder cases". It is the one
   destination already decided to be a pushed screen of that shape (decision #19; F14 names `Routes.swift`). The
   plan's other placeholders ("Workout", "Set up program") become F10's cover, F13's `workout(WorkoutID)` and
   F08's root branch, so adding them now would ship two more catalog strings that nothing reaches and that S5 would
   reshape. S5 adds the cases its routes need with `Routes+Today.swift`. One case is enough to test the router,
   the registration on every stack and the placeholder.
4. **`AppTab`, `AppDestination` and `AppRouter` are internal**, not public: `MainRoot` is the only owner, inside
   the module; tests use `@testable import`. A later feature's `Routes+<Feature>.swift` is in `LedgerAppKit` too.
5. **Every catalog key spells out its English text** (`"state" : "translated"`), where the conventions said only
   "the key is the English text". Reason: proof 1's two facts. A test enforces that the text equals the key.
6. **The check audits sources; it does not compare against "a literal key list"** (the plan's decision 3, which
   the conventions replaced with "every key the copy files use is in the catalog and the reverse"). To name a
   lookup's key without the compiler, an interpolation must be a parameter declared `Int` or `String`
   (standards §7); anything else is a finding, never a silent pass.
7. **In a test target with resources, `Bundle.module` is the test target's bundle**, even under
   `@testable import` of a module that has its own (measured; no ambiguity error). `LedgerAppKitTests` owns the
   fixture, so its tests find the module's bundle with `StringCatalog.resourceBundle(ofModule:)`, which looks
   beside the test bundle. On the host `Bundle.allBundles` does not list the test bundle, so the helper starts
   from a class of its own (`Bundle(for:)`); verified on the simulator and the host.
8. **A tab's root hides the navigation bar; a pushed screen keeps it.** With a bare `NavigationStack` the
   placeholder's title would sit one empty bar lower than in M0. The screens that replace the placeholders draw
   their own headers (v2), and each decides for itself: the modifier is applied where `AppTabs` builds a root,
   not inside `PlaceholderScreen`.
9. **Icons are SF Symbols passed as `systemImage:`** in `AppTabs.swift` (`chart.bar`, `calendar`, `dumbbell`,
   `clock`). Checked as asked: no `ledger_raw_*` rule matches `systemImage:` (lint is green without a
   suppression), and standards §7 limits features to `LedgerDesign` tokens for "color, type, spacing, radius";
   icons are not in that list, and architecture §11 says the tab bar is the native `TabView`, tinted. So nothing
   forbids it and no other route was needed. The names stand at the call (`systemImage: "…"`), which is where the
   audit allows a literal.
10. **Four `Tab`s written out, not a `ForEach` over `AppTab.allCases`**: F11–F13 each replace one tab's root, on
    its own line, and each symbol's name stays at its `systemImage:`.
11. **No pixel reference of the shell**, as the plan says (the system tab bar's material is not a stable
    reference): the "Tabs" preview renders in `PreviewTests`, the hosted tree and the UI test pin what is shown,
    and the screenshots show it.
12. **`MainRoot` keeps the `composition`** only to read Diagnostics for the Debug menu, as `AppRoot` did.
13. **Tab selection is not restored across launches**: criterion 1 says Today is selected on launch.
14. **The shared helper is three files**, not the plan's one `StringCatalog.swift`: the catalog and its rules, a
    reader of Swift sources, and the audit that joins them. The audit and the reader are what replaced the plan's
    "literal key list".
15. **Size**: 153 product lines against the plan's ~250 (the plan counted placeholder destinations and a larger
    router). Test support is 537 lines and tests 815, which is where this slice's weight is: the pattern's check
    is new code, and it is tested rule by rule.

### Criteria → tests

| S1 criterion | Proof |
|---|---|
| 1. Four tabs in order Today, Program, Library, History; Today selected on launch; a stack per tab; a tab keeps its stack | `AppRouterTests` (`tabs_areInTheBarsOrder`, `newRouter_selectsToday_withEmptyStacks`, `selectingAnotherTab_keepsEachStack`, `writingAPath_popsThatTabAlone`); in SwiftUI on the simulator, `AppTabsTests.openedDestination_staysOnItsTabsStack` (the pushed screen is shown, another tab selected, the tab selected again: the screen and the path are still there) and `selectingATab_swapsTheScreen`; in the running app, `LedgerUITests/Tabs.test_fourTabs_todaySelected_inTheBarsOrder` (one tab bar, four buttons, labels, left-to-right order, Today selected); screenshots `s1/` |
| 2. Today shows its placeholder unchanged (`today.title`, the Debug long press); the other tabs a placeholder that names the tab | `LedgerUITests/Smoke.test_launchesToToday` (in the gate, untouched), `LedgerUITests/DebugMenu` (untouched: the long press on `today.title` inside the tab opens the menu), `TodaySnapshotTests` (M0's two references, untouched), `LedgerUITests/Tabs.test_eachTab_showsItsOwnScreen_andTodayKeepsItsTitle` (`program.title`, `library.title`, `history.title` read "Program", "Library", "History"; back on Today, `today.title` reads "Today"), `AppTabsTests.selectedTab_showsItsOwnScreen` |
| 3. Routes are mapped in `LedgerAppKit/Routes.swift`; every stack is keyed by the one `AppDestination`; `open(_:in:)` selects the tab and pushes there | `AppRouterTests.open_inTheSelectedTab_pushesOnItsStack`, `open_inAnotherTab_selectsItAndPushesThere` (each tab), `open_twice_stacksInOrder`; `AppTabsTests.destination_opensOnEveryTab` (each tab's stack shows the destination: one registration per stack, in SwiftUI) |
| 4. Every string the shell shows comes from the catalog, decision #29's two included, wording unchanged; catalog and code agree both ways, by a test | **Superseded by fix round 1** (criterion 4 was revised, and `copy_followsTheStandard`, `builtBundle_resolvesEveryKey`, `databaseUnavailable_keepsItsWording` and `destinationTitles_nameTheScreen` no longer exist): now the gate's `scripts/check-string-catalogs.sh` (keys, both ways), `ModuleCopyTests` (the audit and the built bundle) and `AppCopyTests` (the wording). As first written: `AppCopyTests.copy_followsTheStandard` (both directions, and no copy outside `AppCopy.swift`), `builtBundle_resolvesEveryKey`, `databaseUnavailable_keepsItsWording`, `tabTitles_areTheSpecs`, `destinationTitles_nameTheScreen`; the pattern itself: `CatalogFixtureTests`, `StringCatalogTests`, `SwiftSourceTests`, `CopyAuditTests` |
| 5. The selected tab's icon and label use the accent; VoiceOver reads each tab as its title with the system's tab traits; stock symbols | **Superseded by fix round 1** (the tint is `LedgerColor.accentText`, and `TabsAdversarial.test_selectedTab_isDrawnInTheAccent_andNoOtherIs_lightAndDark` reads the bar's pixels in both themes; screenshots re-shot). As first written: Screenshots `s1/` (accent on the selected tab, light and dark; the four symbols); `LedgerUITests/Tabs` (the tab bar's buttons, labelled by title, `isSelected` on the selected one only, after every tap). The accent is `.tint(LedgerColor.accent)` on the `TabView`; no test reads a pixel of the system bar |
| 6. Database-unavailable and idle are unchanged | `AppRoot.swift`'s two branches are untouched lines (`git diff a24eb60`); the unavailable screen's wording is pinned (`databaseUnavailable_keepsItsWording`) and its preview renders (`PreviewTests`, "Database unavailable"); the launch suites (`AppCompositionTests`, `LaunchOrderTests`, the F07 adversarial suites) pass untouched |

### Code lines (added lines of `git diff -U0 a24eb60`, new files whole, blank and whole-line comment lines excluded)

| Path | Added | Removed |
|---|--:|--:|
| `LedgerAppKit/AppTabs.swift` (new) | 47 | 0 |
| `LedgerAppKit/AppCopy.swift` (new) | 25 | 0 |
| `LedgerAppKit/Routes.swift` (new) | 21 | 0 |
| `LedgerAppKit/PlaceholderScreen.swift` (new) | 20 | 0 |
| `LedgerAppKit/MainRoot.swift` (new) | 18 | 0 |
| `LedgerAppKit/AppKit+Previews.swift` | 10 | 0 |
| `LedgerKit/Package.swift` | 6 | 1 |
| `LedgerAppKit/AppRoot.swift` | 5 | 14 |
| `LedgerAppKit/TodayPlaceholder.swift` | 1 | 1 |
| **Product** | **153** | **16** |
| `LedgerTestSupport/Localization/` (`SwiftSource` 208, `CopyAudit` 186, `StringCatalog` 127) | 521 | 0 |
| `LedgerSnapshotTesting/PreviewRendering.swift` | 16 | 0 |
| Tests (`LedgerAppKitTests` 758, `Apps/LedgerUITests/Tabs.swift` 57) | 815 | 0 |

Under the plan's ~250 by about 40 %: see deviation 15. Not counted: the two catalogs (83 and 62 lines of JSON),
docs, the four screenshots (93–102 KB each).

### Gate and coverage

**Full gate.** `/usr/bin/python3 <sim-lock> scripts/check.sh` from the worktree root, on the final tree (13 GB
free before it): **exit 0, `check.sh OK`**, 584 s (tools 0 s, format 0 s, lint 74 s, iOS build 19 s, iOS boot
0 s, iOS tests 264 s, watchOS build 18 s, watchOS boot 0 s, watchOS tests 208 s, coverage 1 s). Queued
2026-10-04 18:30:16, it waited 734 s for the lock and ended 2026-10-04 18:52:14.

17 test targets ran and passed (PR), 8 (PR-Watch); `Smoke` is in both. The gate log holds no warning. The iOS
result bundle holds 1,678 tests: 1,660 passed, none failed, 12 skipped and 6 expected failures, all 18 in other
targets' suites (Dependencies, Design, Domain, Persistence) and none added by this slice; `LedgerAppKitTests` ran
93 tests in 17 suites.

| Module | Lines | Coverage | Threshold | |
|---|--:|--:|--:|:-:|
| LedgerDependencies | 204 / 213 | 95.77 % | 90 % | ✓ |
| LedgerDesign | 2113 / 2175 | 97.14 % | 60 % | ✓ |
| LedgerDomain | 2009 / 2027 | 99.11 % | 95 % | ✓ |
| LedgerFakes | 1327 / 1342 | 98.88 % | 90 % | ✓ |
| LedgerHealth | 47 / 48 | 97.91 % | 80 % | ✓ |
| LedgerPersistence | 2479 / 2497 | 99.27 % | 90 % | ✓ |
| LedgerSync | 31 / 34 | 91.17 % | 90 % | ✓ |
| Overall | 8210 / 8336 | 98.48 % | 80 % | ✓ |

`LedgerAppKit`, `LedgerTestSupport` and `LedgerSnapshotTesting` are excluded from the coverage gate, as before.
After the gate only Markdown changed: this section, one sentence of proof 3 and open question 11.
`scripts/check.sh --lint-only` passed again afterwards (exit 0).

**Nightly UI tests and the package tests on the simulator.** One session under the lock (Nightly plan,
`-only-testing` each; iPhone 17, iOS 27.0), each result read from its own result bundle. It ran on the final
product code; the only later change is the audit's (`LedgerTestSupport` and its tests), which neither the app nor
a UI test links:

| Run | Result | Time |
|---|---|---|
| `LedgerUITests/Tabs`, light appearance | 2 of 2 passed | 8.5 s and 27.7 s |
| `LedgerUITests/Tabs`, dark appearance | 2 of 2 passed | 15.7 s and 24.0 s |
| `LedgerUITests/DebugMenu.test_diagnostics_showsTheSeededCatalog` (untouched) | passed | 15.4 s |
| `LedgerUITests/LaunchPerformance.test_launchToFirstFrame` (untouched) | passed | 50.6 s |
| `LedgerUITests/Smoke.test_launchesToToday` (untouched; also in the gate) | passed | 5.9 s |
| `LedgerAppKitTests` (before the audit's last change, which added two tests) | 91 tests in 17 suites passed | 4.1 s |

The simulator's appearance was light before the session and was set back to light after it. The four
screenshots in `screenshots/s1/` are that session's `Tabs` attachments (Today and Library, light and dark).

**Launch time (decision #30: reported, never gated).**

| How launched | F07 S3 (placeholder alone) | S1 (tab shell) |
|---|---|---|
| `XCTApplicationLaunchMetric`, 5 launches | 2.48 s mean, RSD 2.1 % | 3.98 s mean, RSD 23.9 % (4.17, 3.15, 5.40, 2.74, 4.45 s) |
| In-app, under XCUITest (Diagnostics) | 2308 ms | 4058 ms |
| In-app, plain `simctl launch`, first after install | 1291 ms | 1496 ms |
| In-app, plain `simctl launch`, warm | 353, 335 ms | 448, 458, 421 ms |

The XCUITest figures cannot be compared: two other agents were building on this Mac during the session, and the
spread (RSD 24 % against 2 %) points to that load; I did not measure `main` under the same load. The plain warm
launches are the usable number: about 100 ms more than the placeholder alone, on a busier machine, and inside the
600 ms budget. None of these is a device's number.

**One-off experiment in the running app (never committed).** To see "a tab keeps its stack" with real taps, which
nothing in S1's interface can do, `MainRoot` was changed for one run to start with Settings pushed on Library's
stack, and a temporary UI test tapped through the tabs: Library showed `settings.title` and not `library.title`;
after visiting Today, Program and History in turn, Library still showed `settings.title` each time; the navigation
bar's back button ("Back") popped to `library.title`; and after one more round trip the root was still there.
Passed (36.4 s). Both temporary changes were undone inside the same locked session, before the final tree was built
and tested: `MainRoot.swift`'s SHA-256 was compared with the one taken before the change, and the temporary test
file is gone (`git status`).

**Host (Mac, final tree).** `swift test --package-path LedgerKit --filter 'PreviewTests|LedgerAppKitTests'`: 89
tests in 16 suites pass (the three modules' previews, and everything of `LedgerAppKitTests` but the iOS-only
`AppTabsTests`). `swift build -c release --target LedgerAppKit`: exit 0, no warnings (the Debug menu compiles out).
The three new `LedgerTestSupport` files also type-check against the watchOS simulator SDK.
The whole package on the host (`swift test`, unfiltered): every test target passes except `LedgerDesignTests`'
Archivo font suites, which fail on the Mac host only, as on `main` (52 issues, the number F07's notes record;
their helper looks for the font in the simulators' flat bundle). None is in a file of this slice.

**The first full gate is not cited.** It exited 0 (609 s; 17 and 8 test targets), but I changed the audit while
it ran, so it tested a tree in between. The gate above ran after that change, on the tree as it is.

### How to verify by hand

- Launch the app on a simulator: four tabs, Today selected and orange, "Today" where it was in M0. Tap each tab:
  its title, the tab's icon and label orange. Long-press "Today": the Debug menu, as before.
- `swift test --package-path LedgerKit --filter LedgerAppKitTests` on the Mac (about 20 s after the first build)
  runs every package test of this slice except `AppTabsTests`, which needs the iPhone simulator.
- The check (**superseded by fix round 1**: `AppCopyTests.copy_followsTheStandard` no longer exists): add
  `Text("Hello")` to a file of `LedgerAppKit` that is not `AppCopy.swift` and run `--filter ModuleCopyTests`, which
  names the file and the line; add a key to its catalog, or look up a key the catalog lacks, and run the gate,
  whose string catalog step names the key.
- The compiled table: `plutil -p .derivedData/Build/Products/Debug-iphonesimulator/LedgerKit_LedgerAppKit.bundle/en.lproj/Localizable.strings`
  after a gate run lists the seven keys.
- The native build system's behaviour: `swift test --package-path LedgerKit --build-system native --filter
  'AppCopyTests|CatalogFixtureTests'` fails `builtBundle_resolvesEveryKey` and the fixture's tests (not run in
  this repository; measured in a scratch package).
- Screenshots: `tasks/features/F09-today/screenshots/s1/`.

### Open questions (each with a recommendation)

1. **Decision #29's body names the product** ("Ledger tries again when you come back to it."), against the
   naming rule, and now sits in the catalog unchanged, as ruled. Recommend "It tries again when you come back."
   or "The app tries again when you come back to it."; it is a one-key change in `AppCopy.swift`, the catalog and
   `AppCopyTests.databaseUnavailable_keepsItsWording`. A test that no catalog value contains the product name
   (one line in `StringCatalog.problems`) should land with that change, not before: it would fail today.
2. **`LedgerDesign` still looks its five VoiceOver words up outside a copy file and without a catalog**
   (`WeekStrip.swift:108-114`, `SetRow.swift:146-154`: "English until the module has a string catalog"). It is
   not audited, so nothing fails. Recommend a small follow-up in the slice that next touches `LedgerDesign`
   (F09 S4): `DesignCopy.swift`, a five-key catalog, `resources` gaining `.process`, and the two tests. Until
   then those five lookups fall back to their keys, which are the English words.
3. **Stock symbols** (Pete's decision 4, default taken): bar chart, calendar, dumbbell, clock. The prototype's
   History icon is a clock with a counter-clockwise arrow; `clock.arrow.circlepath` is the closer stock symbol.
   Recommend Pete looks at the screenshots; swapping a name is one word in `AppTabs.swift`.
4. **Which tier proves copy.** `check.sh --fast` runs no copy test (it filters to Domain and Persistence).
   Recommend leaving it: the full gate runs them on the simulator, and a module's host run is one command.
5. **The catalog's last byte.** Xcode writes a catalog without a final newline; the hand-written ones end with
   one, as every other text file here. It only shows if Xcode ever rewrites a catalog for a real change (one
   extra line in that diff). Recommend leaving the newline.
6. **Xcode's IDE was not opened.** The sync was emulated with `xcstringstool sync` (proof 3). Recommend Pete
   builds once in Xcode after the merge and checks `git status`; if Xcode does touch a catalog, the fix is to
   commit what it writes, as the plan's risk note says.
7. **`AppDestination` and `AppTabs.screen(for:)` are shared one-line files** for F10–F14 (a case, a title until
   the screen lands, a line in the switch). Recommend treating them as convention 4's shared files: add only your
   own case; the orchestrator resolves the conflicts.
8. **watchOS is unproven** for catalogs (no watch module has one). (**Superseded**: there is no per-module pair
   any more; F18 teaches the catalog step to read the watch build and gives a watch test target the bundle
   check. Standards §7, "Not yet converted".) As first written: Recommend F18 repeats `AppCopyTests`' pair
   for `LedgerWatchAppKit` in its first slice and reports.
9. **A real push through the interface.** Nothing in S1's interface pushes a screen, so "a tab keeps its stack"
   is pinned on the router and on the hosted shell, and was seen once in the running app by the experiment
   under "Gate and coverage". Recommend S5's UI test (the gear opens Settings) adds "switch away and back" to
   its flow.
10. **A copy member that returns `Text`** (**superseded**: the one `Text` a copy member returns is
    `Text("… \(timerInterval: …)", bundle: .module)`, and the audit refuses a `Text` joined from parts; standards
    §7, "Copy file". S4 writes "Resume · m:ss" that way.) As first written: (the conventions allow one where a line embeds a live view, such as
    S4's "Resume · m:ss"). The audit reads `String(localized:)` lookups only, so a `Text("Resume · \(timer)",
    bundle: .module)` in a copy file would be a finding. Recommend S4 looks up the word ("Resume") as a `String`
    and builds the `Text` from it, the " · " and `Text(timerInterval:)`, which the audit already accepts; extend
    `CopyAudit.copyFile` only if a real format with an embedded view turns up. Standards §7 says it this way.
11. **Tab identifiers.** A tab bar button's identifier is its symbol's name (`chart.bar`) and its label the
    title; the `Tabs` UI test finds tabs by label. Recommend F15, which centralises identifiers, gives each
    `Tab` one (`tab.today`) if it wants tests that survive a renamed tab.

### Inputs for F08's and F10's slices

(Rewritten in the S1 touch-up, 2026-10-05, to the code as fix round 1 left it. Architecture §4 is the source;
this is where to put your lines.)

**`MainRoot.swift`** (40 lines) is the resolver: it owns the router (`@State private var router`) and, when they
land, the presenters of the features that present themselves over the tabs. It has three members, one per
feature that changes it, so that the changes do not meet:
- `body` returns `content`: what is presented over everything. **F10** applies its exported cover modifier
  here, to `content`. iOS-only API (`fullScreenCover`) needs `#if os(iOS)`: the package also builds for the Mac
  host, and `PreviewTests` render the shell there. A presenter kept in `@State` beside the router does no work
  in its `init` (`@State` builds one on every `init` of `MainRoot` and keeps the first).
- `content` returns `tabs`: which screen the root shows. **F08** adds its "no active program" branch here,
  around `tabs`, so that `MainRoot` stays in the tree and keeps the router while onboarding is shown; the tabs
  then appear with Today selected and empty stacks.
- `tabs` is `AppTabs(router:onTodayTitleLongPress:)` with the Debug sheet on it. Leave the sheet there: the UI
  tests open it from `today.title`.
- Routes: `MainRoot` builds each feature's `onRoute` from the router and the presenters and hands it to
  `AppTabs`, which passes it to the feature's root. What a route does is written once per feature, in
  `LedgerAppKit/Routes+<Feature>.swift`, as calls on the router (`router.selectedTab = .program`,
  `router.open(.settings, in: .today)`) and the presenters. `AppRouter` is `@MainActor @Observable` and internal:
  a feature never sees it. `onRoute` is synchronous.
- A new pushed screen: a case in `AppDestination` (`Routes.swift`) and its line in `AppTabs.screen(for:)`. While
  it is a placeholder, its title is one member of `AppCopy` (`settingsTitle` is the model) with its key in the
  catalog, passed at that line; both go when the feature's screen lands.
- Every public entry view of a feature is named `…Root`, a tab's root or a pushed screen: it owns its store and
  takes `onRoute`.
- The tab bar's tint (`LedgerColor.accentText`) ends at each tab's stack. A system control in a tab wears the
  system's tint until the screen tints it; the cover and onboarding sit outside the tabs and get neither.

**Your own catalog** (standards §7, "Localization", is the source, and "Localization, for a feature author"
under "S1 fix round 1" below is its short form; the bullets here that the later rounds replaced are marked):
- `Package.swift`: add `resources: [.process("Resources")]` to your target's line
  (`.target(name: "FeatureOnboarding", dependencies: featureSpine, resources: […], swiftSettings: uiSettings)`).
  Do not touch `defaultLocalization`.
- Copy `LedgerAppKit/Resources/Localizable.xcstrings` for the layout, and `LedgerAppKitTests/Fixtures/
  Localizable.xcstrings` for a counted key's `variations`.
- Your copy file must be named `<Something>Copy.swift` (or `…Copy+<Area>.swift`), anywhere in the module.
- Counts and names go into a key as `Int` and `String` parameters of the member:
  `static func exercises(_ count: Int, locale: Locale) -> String { String(localized: "\(count) exercises",
  bundle: .module, locale: locale) }` looks up `%lld exercises`. A `Double`, a `Weight`, a formatted date: format
  it first and pass the `String`. A literal `%` in copy is `%%` in the catalog key only when the key carries a
  value (`"\(week)% of the block"` is keyed `%lld%% of the block`); in a key without one it stays single
  (`100% done`). (Corrected in fix round 1: this sentence said `%%` always, which is review B1.)
- Expect the audit to flag, in files that are not copy files: a `Text("…")`, a string passed to a `LedgerDesign`
  component, a constant holding copy, an enum's display string. It does not flag
  `.accessibilityIdentifier("…")`, `identifier:` arguments, `systemImage:` / `systemName:`, log lines on a logger,
  literals without a letter (" · "), comments, or `*+Previews.swift` (which must be wholly inside `#if DEBUG`).
  (**Replaced**: there is no per-module test. For a literal no lifter sees, add it, by its text, to your module's
  entry in `ModuleCopyTests.exemptions` with the reason.)
- (**Replaced**: you write no copy test of the two that this bullet described. `ModuleCopyTests` audits your
  module and asks its built bundle for every key; a counted string you still test through your copy file, with
  one and with several.)
- Previews that include the shell or any `NavigationStack` inside a `Tab` render in `PreviewTests` on the
  simulator and on the host (deviation 2).

### S1 — orchestrator rulings after G3 (2026-10-04)

G3 did not approve: 1 Blocking, 7 Should fix, 12 nits (`review.md`). The review shows that the audit's weak point is
that it derives a lookup's key from source text (B1, the shadowing case in S2, N4), while every build already writes
the compiler's own keys. Fix round 1 therefore changes who checks what, rather than patching the derivation.

**Who checks what (replaces "two tests copied into each module").**
1. **Keys, both ways, by the compiler.** A new gate step (a script under `scripts/`, with script tests, run by
   `scripts/check.sh` after the iOS build and so by CI) takes each module's `Resources/Localizable.xcstrings`, runs
   `xcrun xcstringstool sync` on a temporary copy with that target's `.stringsdata`, and fails when the result
   differs from the committed catalog (final newline aside), saying in plain words which key the code looks up that
   the catalog lacks, and which catalog key no code looks up. It needs no list of modules: it finds the catalogs.
   This also proves on every gate that Xcode's own sync would not rewrite a catalog.
2. **No copy outside the copy files, by the source audit.** `CopyAudit` keeps its literal and lookup rules and
   loses its key derivation (`key(of:)`, the parameter-type inference): B1, S2's shadowing and N4 go with it. It
   gains: outside a copy file every `Text("…")`-style literal is a finding, interpolated or not; in a copy file a
   lookup whose key has an interpolation must pass `locale:`.
3. **The built bundle resolves every catalog key** (`unresolvedKeys`), with a committed test that shows it failing
   (S4).
4. **One suite audits every module** (in `LedgerAppKitTests`, parameterised over the package's source modules):
   UI modules are audited by default; a module with no user-facing copy by design (Domain, Persistence,
   Dependencies, Sync, Health, Fakes, TestSupport, SnapshotTesting) is named in one table with its reason; a module
   not yet converted (`LedgerDesign`, `LedgerWatchAppKit`) is named in a second table that only shrinks. A feature
   adds a catalog and a copy file and nothing else; there is no per-module test to forget (S7's registry).

**The review's items.**
- **B1** closed by 1 and 2 above; standards §7 states the `%` rule as the compiler has it, and the wrong sentence in
  these notes is corrected.
- **S1 accepted:** a copy file may hold two lookup forms: `String(localized: "…", bundle: .module[, locale:])`, and
  `Text("… \(timerInterval: …)", bundle: .module)` for a string that embeds a live timer (key `… %@`). No `Text + Text`.
- **S2 accepted** as in 1 and 2.
- **S3 accepted:** exemptions name literals, not files (a new literal in the file is a finding); the logger's
  `category:` joins the allowed leads; a Debug-only exemption is verified (the file is inside `#if DEBUG`); §7 says
  the reviewer confirms each exemption and that a file declaring a view, a store or a presentation builder is never
  exempt.
- **S4 accepted.**
- **S5 accepted:** `MainRoot` has three members: `body` (where F10 adds its cover modifier), `content` (where F08
  adds its branch) and `tabs`. Architecture §4 names the resolver: `MainRoot` builds each feature's `onRoute` from
  the router and the presenters it owns and hands it to `AppTabs`. Every public entry view of a feature, a tab root
  or a pushed screen, is named `…Root`, owns its store and takes `onRoute`.
- **S6 decided under the accessibility rule already applied in F06** (text and icons meet AA): the tab bar's tint is
  `LedgerColor.accentText` (the accent in dark, `#B2390E` on light), re-measured and re-shot; Pete is told. The
  tint must not reach tab content: reset it where `AppTabs` builds each stack's root, and say so in §4.
- **S7 accepted:** §7 names the two modules not yet converted (a chore PR after this slice converts them), and
  settles: (1) a counted key has one `%lld`, the number that picks the plural; any other number in it is passed
  already formatted, as `%@` ("%@ of %lld sets"); (2) a translator's comment is written in code (`comment:`) and
  the catalog's copy of it must match (the sync check enforces it); (3) `locale:` also picks the plural form and
  the digits, with one pinned case; (4) spoken text (VoiceOver labels, values, hints) is copy and lives in the copy
  file; (5) display names of Domain enums shared by several features are not settled: the first slice that needs
  one in a second module raises it with the orchestrator.
- **Nits:** N1, N2, N5 (previews are covered by check 1; say so), N6 (an unreadable folder fails the audit), N8,
  N10, N11, N12 accepted; N3 and N7 noted in §7 and for S5; N4 and N9 go away.
- **Could not settle:** U1 run `AppTabsTests` fifty times under the lock and report; U2 report whether a
  deprecation warning in a package target fails the gate (a known gap in `check.sh`: do not fix it here); U3
  re-run every module's previews on the host after the change.
- **Not taken:** generated string symbols (the review's alternative). They would give the same key agreement from
  the compiler, but rest on newer tooling that nobody has built against in this package or on the CI image; the
  sync check gives it with tools the build already runs. Revisit if hand-written copy files become a burden.

**G2 round 1 (strike 1)** found no fault in the shell (criteria 1–3, 5, 6) and eleven things in the copy audit
(`test-findings.md`; ten tests fail on purpose). Rulings, for the same fix round:

- **F9-S1-1** is review B1: closed by moving key agreement to the compiler's keys. The tester's key tests whose
  subject was the audit's own derivation move to the new gate step's script tests (the same cases: a `%` with and
  without a value, positional and counted keys).
- **F9-S1-2 accepted:** a lookup is never written inside another literal's interpolation; in a copy file that is a
  finding. A join is two statements. Every lookup in a copy file carries `bundle: .module`, wherever it stands.
- **F9-S1-3 accepted:** a lookup whose key carries a value passes `locale:`; §7 says the locale also picks the plural
  form and the digits.
- **F9-S1-4 decided by the Naming rule** (`docs/product-decisions.md`: "Shipped copy never contains the product
  name"): the audit refuses a catalog entry that holds the product's name, and the can't-open screen's second
  sentence becomes "Your workouts are still on this iPhone. The app tries again when you come back to it."
  Criterion 4 is amended. Pete approved the old wording on 2026-10-04 and is told of the change; the watch's copy
  of the sentence changes in the chore that converts `LedgerWatchAppKit`.
- **F9-S1-5 and F9-S1-6 accepted together:** an allowed label is an argument label (it follows `(` or `,`), and it
  allows every literal inside that argument's expression (a ternary, an interpolation); a name that only reads
  like a label (a ternary arm, a `case`) allows nothing.
- **F9-S1-7 accepted:** lookups are matched across line breaks; `localizedAttributedString(forKey:` joins the list.
- **F9-S1-8 and F9-S1-9** are closed by the sync check (it compares the catalog as the tool would write it, byte for
  byte, so layout, order, duplicate keys and Unicode spelling are all covered); where the audit still compares
  strings in Swift it compares them exactly, not by canonical equivalence.
- **F9-S1-10 accepted:** §7 lists the audit's known limits, each pinned by a `limit` test as the design lint's are:
  a regex literal; a text made from a name. Exemptions per literal (S3) and the Debug check on `*+Previews.swift`
  close (a) and (d); the sync check closes (e).
- **F9-S1-11 accepted:** snapshot references for `PlaceholderScreen` and the can't-open screen (light and dark, the
  matrix of testing-strategy §2.6); the "Tabs" preview keeps no pixel reference (the system bar's material is not a
  stable reference) and the notes say what pins it instead.

### S1 fix round 1 (G1 implementer, 2026-10-04)

The round was cut in two by a usage limit. The helper agent I had started for the gate step did not report
back; I read its script and its suite, ran both, ran eight mutants of the script against the suite (all killed),
and added the two of the tester's inputs it had left out. Everything below was run after the restart unless a
time says otherwise.

**1. What changed, by ruling.**

- **Who checks what, 1: keys by the compiler** (B1, S2, N4, F9-S1-1, -8, -9). New
  `scripts/check-string-catalogs.sh`; called at `scripts/check.sh:200-204`, between the iOS build and the wait
  for the simulator, in every mode that builds iOS. Its cases: `scripts/tests/adversarial/string-catalogs.adv.sh`
  (71, marked `# needs macOS:`); its place in `check.sh`: `check-wiring.adv.sh` (the `FULL` order, W10, W68,
  W70–W75). Listed in `docs/testing-strategy.md:412-414, 432-458` and `docs/ci-cd.md:40-41, 80-95`.
- **2: the source audit** (S3, N5, N6, F9-S1-2, -3, -5, -6, -7, -10). `CopyAudit` derives no key any more
  (`key(of:)` and the parameter inference are gone). The rules are in the new
  `LedgerTestSupport/Localization/CopyAuditRules.swift`: allowed labels with `category:` (`:18`), the lookup
  spellings with `localizedAttributedString(forKey` (`:21`), what no lifter sees (`isUnseen`, `:29`), literals and
  lookups outside a copy file (`strayProblems`, `:42`), the two forms inside one (`copyFileProblems`, `:71`;
  `stringLookupProblem`, `:139`: nested, one line, `bundle: .module`, `locale:` with a value;
  `textLookupProblem`, `:154`), Debug-only files (`debugOnlyProblems`, `:95`), exact comparison (`isSameText`,
  `:116`). The lexer now knows the call argument a literal stands in, the literal that holds it and the code
  after it: `SwiftLexer.swift` (`argument`, `:147`; `noteInArgument`, `:179`), `SwiftLexer+Literals.swift`
  (`readInterpolation`, `:62`), `SwiftSource.swift` (`trail`, `:25`; `holder`, `:28`; `SwiftCallArgument`,
  `:55`; `lines(ofCode:)`, `:106`, which reads across line breaks). `CopyAudit.swift`: `Exemptions` (`:20`,
  literals per file and `debugOnly`), `init(module:)` (`:42`), `init(moduleWithoutCatalog:)` (`:51`),
  `sources(ofModule:)` (`:91`, throws on a folder it cannot read).
- **3 and 4: one suite, every module** (S4, S7's registry). New `LedgerAppKitTests/ModuleCopyTests.swift`:
  the two tables (`:17`, `:31`), the exemptions (`:37`), every module audited or named (`:77`), the audit
  (`:87`), a listed module must still fail (`:92`), the built bundle (`:103`), and `unresolvedKeys` shown failing
  (`:116`). `AppCopyTests` keeps only the wording. `LedgerActivityKit` and the eight placeholder feature modules
  are audited, not listed: each holds one file with its own name in a literal, which `placeholderName(of:)`
  (`:63`) finds and sets aside, so that the feature that replaces the file edits nothing here.
- **F9-S1-4, N2.** `StringCatalog.swift:30` (`productName`), `:77` and `:93` (a key or text that names the
  product), `:82` (the sentence about `translated`). `AppCopy.swift:37-43` and the catalog hold criterion 4's
  new sentence; the tester's product-name tests pass through that change, with no exemption.
- **S1.** The two forms are in standards §7 and in `copyFileProblems`. `Text + Text` is forbidden in §7 and is
  a known limit of the audit (4 below).
- **S5.** `MainRoot.swift:22` (`body`), `:27` (`content`), `:32` (`tabs`). `docs/architecture.md:179-201`
  names the resolver and the `…Root` naming.
- **S6.** `AppTabs.swift:32` (`.tint(LedgerColor.accentText)`), `:45` and `:69` (`tabContentTint()`, which is
  `tint(nil)`). The API: `tint<S: ShapeStyle>(_ tint: S?)`. Apple's page does not say what nil does, so
  `AppTabsTests.swift:72` measures it: a shape filled with `.tint`, inside `tabContentTint()` and a tint around
  that, is drawn pixel for pixel as with no tint at all. `docs/architecture.md:173-178`. Screenshots and contrast
  in 9 below.
- **S7.** `docs/engineering-standards.md:169-368`, rewritten (and its bullet at `:162-165`): the counted key with a second number as `%@`,
  comments in code, what `locale:` picks, spoken text, the undecided shared names, the two modules not yet
  converted, the generated-symbols alternative.
- **Nits.** N1 `AppTabs.swift:61`. N8 `AppCopy.swift:23` (`settingsTitle`) and `AppTabs.swift:51`. N10
  `docs/architecture.md:476-478`. N11 `MainRoot.swift:11-13`. N12: §7 says code-unit order
  (`engineering-standards.md:203-207`), and which units: I measured `xcstringstool`, and it orders keys by
  their UTF-8 bytes, so by Unicode scalar, not by UTF-16 unit. The fixture's own table is not done (10 below).
  N2, N5, N6 above.
- **F9-S1-11.** New `LedgerAppKitTests/ShellSnapshotTests.swift` and twelve references under
  `__Snapshots__/ShellSnapshotTests/` (a placeholder screen and the can't-open screen, light and dark at
  large, xLarge and accessibility3; recorded on the iPhone 17, iOS 27.0, at 20:51, and matched in every run
  since). The "Tabs" preview has no reference. It is pinned by `AppTabsTests` (the hosted tree), `PreviewTests`
  (it renders, on the simulator and the host) and the `Tabs` and `TabsAdversarial` UI tests (the running app, the
  selected tab's colour included).
- **Criterion 4's sentence.** `AppCopy.swift:37-43`, `Resources/Localizable.xcstrings`, `AppCopyTests`, the
  tester's two suites (5 below), and the six new references of the can't-open screen. No earlier reference
  showed that screen.
- **These notes.** The sentence about `%` under "Your own catalog" above is corrected in place.

**2. Localization, for a feature author.** Add two things to your module: `Resources/Localizable.xcstrings`
(and `resources: [.process("Resources")]` on the target) and `<Feature>Copy.swift`. Write every lookup there as
`String(localized: "…", bundle: .module)`, with `locale:` straight after the bundle when the key carries a
value, and `comment:` where a translator needs one; a line with a live timer is
`Text("… \(timerInterval: …)", bundle: .module)`. Every other file takes `String`s. Give each key its English
text in the catalog, marked `translated`, with the comment the code gives. You add no test and no list entry.
Three checks find the module: the gate compares the catalog with the keys the compiler extracted and spells any
key you got wrong; `ModuleCopyTests` audits the sources and asks the built bundle for every key. If the audit
flags a literal no lifter sees, add it, by its text, to `ModuleCopyTests.exemptions` with the reason; the G3
reviewer confirms it. Standards §7 has the rest.

Two commands run them (added in the S1 touch-up, re-review n6). The audit and the bundle check, on the Mac, a
few seconds after the build: `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter
ModuleCopyTests`. The key comparison runs only in the gate, after its iOS build: `scripts/check.sh`. Your own
module's tests run neither.

**3. The gate step: proof.** Each case runs the real script and the real `xcstringstool` on a throwaway
repository whose `.stringsdata` the real compiler wrote (`string-catalogs.adv.sh`, 71 of 71, 6 s).

| Asked | Case | What the step does |
|---|---|---|
| a key used and missing | SC01 | fails, naming the key and `StartCopy.swift:2` |
| a key unused | SC02, SC68 | fails, naming the key; also when the catalog marks it `stale` or `manual` |
| a plain key with `%` | SC03, SC04 | `100% done` passes; `100%% done` fails both ways |
| a key with a value and `%%` | SC05, SC06 | `%lld%% of the block` passes; `%lld% of the block` fails both ways |
| a counted key | SC07, SC08 | passes with an `Int`; fails when the code's value is a `String` |
| a bare `Text("…")` in a view | SC09 | fails, naming the key and `StartView.swift:3` |
| a duplicate key | SC10 | fails with the tool's diff |
| keys out of order | SC11, SC12 | fails with the diff; in order, passes |
| composed against decomposed | SC13, SC14 | fails both ways, each key spelled with its escapes |
| a comment that is not the code's | SC15, SC16 | fails with the diff |
| nothing to compare with | SC17–SC20, SC26 | fails: no build, a watch build only, a file added since the build, no catalog at all; a deleted file's old output is ignored |
| never writes to the repository | SC21–SC23 | every file has the same hash after a passing and a failing run |
| the tester's moved cases | SC32–SC57 | section 5 |

Beyond the suite: the script passes on this tree's real build (7 keys, under a second, the tree untouched);
eight mutants (no key comparison, no layout comparison, stale output read, an unbuilt file accepted, exit 0 on a
failure, the catalog written, keys compared without case, no catalog accepted) each fail the suite.

Modes. `check-wiring.adv.sh` pins the call, with fake tools, in the full gate, `--skip-lint`, `--ios-only`,
`--ios-only --skip-static`, `--record-snapshots` (a failing catalog stops the record run before any test) and
its absence from `--lint-only`, `--static-only` and `--fast`. Run for real, through the lock: the full gate, and
`CI=true LEDGER_COMPILATION_CACHE=YES scripts/check.sh --ios-only --skip-static` (exit 0, 266 s; the step
passed). The compilation cache: I built with `COMPILATION_CACHE_ENABLE_CACHING=YES`, moved LedgerAppKit's object
folder (its `.stringsdata` with it) out of the build folder, and built again. All eleven of its compiles were
`Replay cache hit`, each with `Using CAS output localization-strings`, the 13 files were back, and the step
passed on them. So a cache hit writes the files.

Not checked: GitHub's runner, with a cache another run saved; `GITHUB_ACTIONS` set (it only changes
xcbeautify's renderer); `--record-snapshots` for real (fake tools only); a lookup compiled only for watchOS,
which the step would report as unused because it reads the iOS build (§7 says so).

**4. Known limits of the audit** (standards §7, each kept by a `limit` test: `CopyAuditLimitTests`, and the
tester's two for the last two lines).

- A literal without a letter that is not handed straight to `Text(…)`.
- A call that only reads like an allowed one (`Chip(category: "Push day")`, `toastLogger.error("…")`).
- `Text + Text` in a copy file. Ruling S1 forbids it, and the tester's
  `textMember_builtFromLookupsAndAView_hasNoFinding` requires no finding for it; I left the audit silent and
  wrote the rule in §7. Say if the audit should refuse it: that test then changes.
- What a key's value is: an expression, a `Double`, an optional. The tester's
  `interpolationNotABareParameter_isAFinding` held the audit to this through the derivation that is gone. The
  compiler warns of an optional, and a warning does not fail a package build (U2).
- Code in a copy file that holds no literal.
- An exemption is a text: it covers every literal of its file that reads so.
- A text made from a name (`Text(day.rawValue.capitalized)`).
- A regex literal that holds a quote or `/*`.

**5. Sanctioned test edits.** Line numbers are the current file's. "Moved" cases have the same inputs and the
same expectation in `string-catalogs.adv.sh`.

*Moved to the gate step's suite, the Swift test deleted:*
- `CatalogBuildAdversarialTests.auditKey_isFoundationsKey`, with `Lookup`, `week`, `total`, `name`, `tag` and
  the twelve `lookups`: SC32–SC43.
- `CopyFileAdversarialTests.parameterType_decidesTheSpecifier`: SC44–SC47.
- `CopyFileAdversarialTests.lookupInAComment_isNotALookup`: SC48.
- `CopyFileAdversarialTests.composedAndDecomposedKeys_areNotTheSameKey`: SC13, SC14.
- `CopyAuditAllowedAdversarialTests.catalogAndCopyFile_disagree_isAFinding` and its seven `disagreements`:
  SC49–SC55.
- `CopyAuditAllowedAdversarialTests.oneSideMissing_isAFindingPerKey`: SC56, SC57.
- `StringCatalogAdversarialTests.keysOutOfOrder_areAProblem`: SC11, SC12.

*Deleted, its rule gone with the derivation; not the same expectation:*
- `CopyFileAdversarialTests.interpolationNotABareParameter_isAFinding` and its eleven `wrongValues`. It
  expected a finding from the audit for each. The eleven inputs are kept as SC58–SC66, SC69 and SC70, where the
  expectation is the key the compiler gives each. The finding for one of them, a lookup inside the key, stays in
  Swift (`nestedLookupNotWrittenAsTheRule_isAFinding`). Limit 4 above is what was lost.

*Adapted to the new exemption shape (path to literals), nothing else:*
- `CopyAuditAdversarialSupport.swift:50` (`exempting:` is a `CopyAudit.Exemptions`).
- `CopyAuditAllowedAdversarialTests.swift:36` (`exemption_coversItsFileOnly`), `:46-56`
  (`staleExemption_isAFinding`), `:68-71` (`exemptFile_lookupIsStillAFinding`).

*Changed because a ruling changed what is right; none of these three kinds was sanctioned, so please audit them
first:*
- `CopyAuditAllowedAdversarialTests.swift:75-86`: the limit `exemptFile_hidesALifterFacingLiteral` ("an
  exemption covers the whole file") is now `exemption_namesLiterals_aTitleInTheFileIsStillAFinding`, one
  finding on line 4 (S3 closes the limit).
- `:96-103` (`textMadeFromAName_hasNoLiteralToFind`): `Text("\(Card.today)")` left the limit's screen and is
  asserted to be a finding (ruling 2: every literal handed to `Text`).
- `:115-123` (`previewsFile_isNotRead_othersAre`): the preview is inside `#if DEBUG`, and a bare one is asserted
  to be a finding (F9-S1-10d, N5).
- `CopyFileAdversarialTests.swift:31-44` (`nestedLookupNotWrittenAsTheRule_isAFinding`): its control was the
  nested right form, which F9-S1-2 makes a finding. The control is now the join in two statements, and the
  nested right form is asserted to be a finding.
- `CopyFileAdversarialTests.swift:189, :206` (two `rightLookups`): `counted(` for `lookup(`, so that a key
  with a `String` value passes `locale:` (F9-S1-3 as ruled: any value).
- `AppCopyAdversarialTests.swift:7-9, :12-13, :15, :29-30` and `AppRootAdversarialTests.swift:9-11, :20, :92`:
  criterion 4's new sentence, and the test's name. `AppCopyAdversarialTests.swift:26`: `AppCopy.settingsTitle`
  (N8 removed `title(of: AppDestination)`).
- `CatalogBuildAdversarialTests.swift:8-9`: the suite's comment.
- `Apps/LedgerUITests/TabsAdversarial.swift:83, :142-146, :171-174`: `accentShare` takes the appearance. Dark
  keeps the tester's bounds; light counts the deep accent (red 140–200, green 25–85, blue under 45). The two
  thresholds are unchanged (S6).

Every other tester test passes unedited; none is disabled or in `withKnownIssue`.

**6. Size.** Product lines of the slice (LedgerAppKit and `Package.swift`, without blank lines and comments):
170 added, 16 removed, against 153 after G1. The round added 17: comments on the lookups, `settingsTitle`,
`MainRoot`'s members, the tint. Test support: `CopyAudit.swift` 106 lines (was 246), with
`CopyAuditRules.swift` 207, `SwiftLexer.swift` 210 and `SwiftLexer+Literals.swift` 110 new, and
`SwiftSource.swift` 115 (was 255); the script 190 and its suite 407.

**7. The gate.** `/usr/bin/python3 …/sim-lock.py scripts/check.sh`, from the worktree root, at 23:46:
`GATE_EXIT=0`, `check.sh OK`, 600 s (lint and script tests 73, iOS build 83, string catalogs under 1, iOS tests
230, watchOS build 24, watchOS tests 187, coverage 1; no wait for the lock). Coverage 98.48 % overall, every
module over its threshold. After it I changed only documents: three lines in the step list of
`docs/testing-strategy.md`, the sentence on key order in standards §7, and this section. No gate script reads
them. `scripts/check.sh --lint-only` ran again on that tree at 00:00: `LINT_ONLY_EXIT=0`, 77 s, 650 script cases, none
failed.

Other runs, all through the lock: `LedgerAppKitTests` on the simulator, 191 tests in 31 suites, exit 0 (179 in
29 on the Mac host); the CI-mode gate above.

**8. UI tests** (Nightly plan, iPhone 17, iOS 27.0, one locked session at 23:26, on the code the gate ran):
Smoke 1 of 1; DebugMenu 1 of 1; LaunchPerformance 1 of 1 (first frame 2.568 s average, 0.67 % deviation);
Tabs 2 of 2 in light and 2 of 2 in dark; TabsAdversarial 7 of 7, the accent test and the system's
accessibility audit among them. Each run's exit status was 0.

**9. Contrast** (`tasks/features/F09-today/screenshots/s1/`, the four replaced; measured after matching the
screenshots to sRGB). The system draws the tint a little off the token.

| Theme | Selected tab's icon and label | Behind it | Contrast |
|---|---|---|---|
| Light | `#A73107` (token `#B2390E`) | `#E4E2DB` | 5.25:1 |
| Dark | `#FF682F` (token `#FF5B22`) | `#141416` | 6.37:1 |

Both pass AA for text (4.5:1) and for icons (3:1). Unselected tabs: 17.84:1 light, 13.89:1 dark.

**10. Could not settle, could not do, could not verify.**

- **U1.** `AppTabsTests` fifty times (`-test-iterations 50`): exit 0, no issue. The three plain tests started 50
  times each, the two with arguments 200 cases each.
- **U2.** No: a deprecation warning in a package target does not fail the gate. The build log shows
  `-warnings-as-errors` on the app targets' compiles (`LedgerWatch`, `LedgerWatchTests`) and on none of the
  package targets'; and this gate passed with compiler warnings in two package test targets
  (`PayloadVersionAdversarialTests.swift:29`, `LedgerDesignTests/PreviewTests.swift:90`). `Package.swift:10-12`
  says the opposite. Not fixed, as told. I did not compile a deprecated call under the gate to watch it pass.
- **U3.** Every module's previews render on the host after the `PreviewRendering` change: LedgerDesign 20,
  LedgerAppKit 4, LedgerWatchAppKit 2.
- **N12, first half, not done.** A table of its own for the test fixture needs edits the tester-file rule does
  not sanction: six lookups, two `unresolvedKeys` calls and the fixture's path in
  `CatalogBuildAdversarialTests`, and a `table:` parameter on `unresolvedKeys`. It is mechanical; say the word.
- **`Text + Text`** (limit 3) and **what a key's value is** (limit 4) are open between a ruling and the
  tester's tests, as described there.
- **The tint in a tab's content** is tested on the modifier, not on `AppTabs` itself: nothing a tab draws today
  wears the tint, and `ImageRenderer` cannot draw a `NavigationStack`. That `AppTabs.stack` applies the modifier
  is one line to read (`AppTabs.swift:45`).
- **The imports before `#if DEBUG`.** The Debug-only check lets `import` lines stand before `#if DEBUG`: the
  tester's helper puts `import SwiftUI` first in every file it builds. Our four Debug-only files open with
  `#if DEBUG`.
- **`PreviewScan`** still skips a folder it cannot read (N6 named it in passing); the audit's own reader throws.
- The runner and the record mode, as in 3.

### S1 — orchestrator rulings after fix round 1 (2026-10-05)

- **`Text + Text` in a copy file is a finding.** Standards §7 forbids it, so the audit refuses it; the tester's
  `textMember_builtFromLookupsAndAView_hasNoFinding` pinned the earlier rule and the tester changes it in the
  close-out.
- **A key's values are whole numbers and texts.** The catalog check refuses a key with any specifier other than
  `%lld` and `%@` (with their positional forms and `%%`), which catches a `Double` or another type formatted into a
  key. An optional interpolated into a key stays a known limit until package targets treat warnings as errors
  (a queued chore: `check.sh` does not pass `-warnings-as-errors` to them, though `Package.swift` says so).
- **N12 is taken:** the test target's fixture catalog gets a table of its own, so that building the tests in Xcode
  never rewrites it. The mechanical edits this needs in the tester's files are sanctioned.
- The edits to the tester's files that go beyond the three sanctioned kinds each follow from a ruling; the tester
  audits them first in the close-out.
- Not taken: testing the tint reset on `AppTabs` itself (nothing a tab draws wears the tint yet; F09 S5 pins it
  when Today has a control that would).

### S1 — orchestrator rulings after the close-out (2026-10-05)

G3 approved the fix round (0 Blocking; R1–R3, eight nits). G2's close-out closed the round-1 findings (two with a
named remainder), audited the edits to its files and found three low items. For the touch-up:

- **R1 accepted:** the gate step fails a lookup whose source file is not a copy file, in its own words, with cases
  in the suite. That closes the audit's first known limit for every module with a catalog.
- **R2 decided:** the conversion chore after this slice converts `LedgerDesign` only. `LedgerWatchAppKit` and
  `WatchFeatureWorkout` convert with F18, when the step learns to read the watch build and a watch test target asks
  the watch bundles for their keys. §7, the table's reason and the step's message say so. (The watch's copy of the
  can't-open sentence loses the product's name in the chore, as a plain wording change.)
- **R3 accepted** (the hand-off text for F08 and F10 is rewritten; the brief's figure is corrected to 2.70:1).
- **F9-S1-12 accepted** (the step must pass on a tree it cannot write).
- **F9-S1-13 and n2:** a translator's comment may stand in the catalog alone; when the code gives one, the catalog's
  must equal it. §7 says so.
- **F9-S1-14 and n5:** a locale written into a copy member (`locale: .current`) joins "Known limits"; §7 says the
  locale is a parameter of the member and that the timer form carries the timer and no other value.
- **n1, n3, n4, n6, n7, n8 accepted** as the re-review writes them.
- **N12 moves to the `LedgerDesign` chore** (it needs edits in the tester's files; this touch-up leaves them alone).

### S1 touch-up (G1 implementer, 2026-10-05)

Done in two passes. The first built everything except R1 and n1, which each contradicted a tester case that
passed (ST04 and ST09 of `string-catalogs-tester.adv.sh`; shown on scratch copies of the step), and I stopped on
them as told. The orchestrator then ruled: n1 is not taken, and R1 is taken with one sanctioned edit to the
tester's suite. This section describes the tree after the second pass. The four tests that failed on purpose
pass.

**The sanctioned edit to the tester's suite.** ST04's two fixture files have copy-file names; the sources in
them, the comments, the order and the expectation are as they were. `git diff cf7e459 --
scripts/tests/adversarial/string-catalogs-tester.adv.sh` shows these three lines and no other:

| Line | Was | Is |
|---|---|---|
| 42 | `cat >"$SRC/FirstComment.swift" <<'SWIFT'` | `cat >"$SRC/FirstCommentCopy.swift" <<'SWIFT'` |
| 46 | `cat >"$SRC/SecondComment.swift" <<'SWIFT'` | `cat >"$SRC/SecondCommentCopy.swift" <<'SWIFT'` |
| 161 | `module comment-twice Tabs FirstComment SecondComment && …` | `module comment-twice Tabs FirstCommentCopy SecondCommentCopy && …` |

No other tester file is touched: `git diff cf7e459 -- LedgerKit/Tests/LedgerAppKitTests/Adversarial
Apps/LedgerUITests/TabsAdversarial.swift` is empty. With R1 built, no other tester case fails.

**n1: ruled not taken.** A source edited after the build is compared by the `.stringsdata` that build wrote.
`check.sh` always builds before the step, so the gate cannot meet it; a run by hand needs a build first. The
script and ST09, which pins it, are as they were. It is said in standards §7
(`docs/engineering-standards.md:387-391`) and in the step's header (`check-string-catalogs.sh:31-32`).

**Built, by item.**

1. **`Text + Text` in a copy file is a finding.** In a copy file a `Text(…)` whose first argument is not a
   string literal is a finding (`CopyAuditRules.swift:91-93`, message at `:127-128`); a literal there was
   already held to the timer form. That refuses the join wherever its parts are made: `Text(resume)`,
   `Text(String(localized: …))`, `Text(verbatim: " · ")`. The calls are read by the new
   `SwiftSource.calls(of:)` (`SwiftSource.swift:119`), from the code with its spaces, so that `return Text(` is
   not one name. The tester's `textJoinedFromParts_isAFinding` passes, 3 of 3. Mine:
   `CopyAuditTests+CopyFiles.swift:109` (six shapes), `:118` (a name that only ends in Text),
   `SwiftSourceTests+Calls.swift:63`. `CopyAuditLimitTests.limit_textJoinedFromParts` is deleted, and the limit
   left §7 (`docs/engineering-standards.md:225-227`, `:292-294`).
2. **A key holds only `%lld` and `%@`.** `StringCatalog.otherSpecifiers(in:)` (`StringCatalog.swift:172`) reads
   every other specifier, flags, width, precision and length included; `valueProblems` (`:120`) makes one
   problem of them for a plain key and for a counted key and its forms. The tester's
   `keyWithAnotherSpecifier_isAProblem` (5 of 5) and `doubleFormattedIntoAKey_isAFinding` pass, and its control
   `keyWithWholeNumbersAndTexts_isNoProblem` still does. Mine: three rule cases from
   `StringCatalogTests.swift:164`, the reader at `:43`, and a `Double` through the audit at
   `CopyAuditTests+CopyFiles.swift:130`. The step's hint (`check-string-catalogs.sh:176-180`) and
   `docs/testing-strategy.md:465-469` no longer offer `%lf` (n7; SC75). §7: `:230-232`, `:296-298`, and the
   limit on a key's value at `:362-367`, which now names an expression and an optional only. One side effect:
   a `%` straight before a conversion letter in a key without a value ("50%off") reads as a specifier.
3. **F9-S1-12.** The copy that gets a final newline is a new file written with `cat`
   (`check-string-catalogs.sh:108`), the one-line fix the tester named; `cp` gave it the mode of a read-only
   catalog. ST23 passes. SC76 adds a read-only catalog that ends without a newline, and fails with `cp` back.
4. **R1: a lookup that is not in a copy file fails the gate step.** The step's `jq` program marks each
   extracted lookup by its file's name, as `CopyAudit.isCopyFile` names a copy file
   (`check-string-catalogs.sh:94`). A lookup in any other file is a finding of its own, with file and line,
   whether or not the catalog has its key (`:99`), under its own heading and with what to do instead: move the
   lookup into the copy file and hand the view a `String`; in Debug-only code write `Text(verbatim: "...")`; do
   not give the catalog a key for it, and delete one it holds only for it (`:159-171`). The key comparison now
   reads the copy files' lookups only (`:95-96`, `:100-102`), so its message, which begins "Give the catalog a
   key for each lookup it lacks", is never about a lookup in the wrong file; its last sentence, on a literal
   handed to a view, moved to the new message (`:172-181`). A catalog key that only a wrong-file lookup uses is
   not called unused (`:97`, `:102`): the lookup's own line covers it. Either finding fails the catalog (`:183`).
   - Cases in `string-catalogs.adv.sh`: SC09 (a bare `Text("Start workout")` in a view: the lookup's line, no
     "lacks", nothing says to add a key), SC77 (a preview's `Text("Sample row")` inside `#if DEBUG`, its key in
     the catalog), SC78 (`Button("\(done)/\(total)")`, no letter, its key `%lld/%lld` in the catalog), SC79 (a
     lookup in `TabsCopy+More.swift` passes), SC80 (`CopyButton.swift` is no copy file), SC81 (both kinds at
     once, each under its heading). The fixtures are compiled with `-D DEBUG` for SC77. Thirty of the suite's
     older cases needed their lookup fixtures renamed to copy-file names (`PercentPlain` to `PercentPlainCopy`
     and so on); their inputs and expectations are unchanged.
   - Six mutants of the rule each fail a case: no such check; any name that holds "Copy"; no `+<Area>` files;
     keys compared from every file; the finding printed but not failing; a key called unused though a
     wrong-file lookup uses it.
   - `LedgerAppKit` passes on this tree's build: 1 catalog, 7 keys, all looked up in `AppCopy.swift`.
   - §7 describes the rule in check 1 (`docs/engineering-standards.md:261-269`). The first known limit is
     narrowed, not deleted (`:350-355`): what the rule closes, a letterless literal handed to a view in a module
     with a catalog, is gone from it. What is left: a letterless literal that is no lookup (a
     `"\(done)/\(total)"` held in a `String`), and any in a module that has no catalog, where the step does not
     look (the tester's ST08). `CopyAuditLimitTests.swift:16` still keeps the audit's side.
     `docs/testing-strategy.md:446-454` and `docs/ci-cd.md:86-88` describe the rule too.
5. **R2.** `docs/engineering-standards.md:175-177`, `:325-334`, `:381-387`, `:408`;
   `ModuleCopyTests.swift:32-41` (the table's comment and both reasons; `LedgerDesign`'s now gives the measured
   size, 14 lookups in six files); the step's message when a catalog has nothing to be compared with
   (`check-string-catalogs.sh:135-142`, and its header), pinned by SC18; `docs/testing-strategy.md:458-460`,
   `docs/ci-cd.md:89-90`. `WatchFeatureWorkout` holds no copy yet, so it stays audited and is not in the table:
   a module that passes the audit cannot be listed there.
6. **R3.** "Inputs for F08's and F10's slices" above is rewritten to the code as it is (`:1073-1101`), and the
   two bullets of "Your own catalog" that described a per-module test are replaced (`:1121-1125`). Two of the
   first round's recommendations that now mislead are marked superseded: 8 (F18 repeats a per-module pair) and
   10 (join "Resume · m:ss" from `Text`s), at `:1054` and `:1062`. The brief already reads 2.70:1.
7. **Nits.**
   - n1: not taken, above.
   - n3: §7 "Known limits" gains parentheses that do not balance (`:376-379`), kept by
     `CopyAuditLimitTests.swift:46`.
   - n4: any `*.xcstrings` under `LedgerKit/Sources` that is not a module's
     `Resources/Localizable.xcstrings` fails the step, named (`check-string-catalogs.sh:217-225`, `:232-235`);
     SC71–SC74.
   - n6: `ModuleCopyTests.exemptions` is in convention 4's list in these notes (`:665`), in its own comment
     (`ModuleCopyTests.swift:44`) and in §7 (`:307-309`). The same block in F08's and F10's notes is the
     orchestrator's. The two commands are in §7 (`:339-342`) and in "Localization, for a feature author"
     (`:1292`).
   - n8: the first round's rows 4 and 5 of "Criteria → tests" and its "The check" bullet are marked superseded
     (`:908`, `:909`, `:1017`).
   - §7's three sentences: the comment (`:200-202`), the locale as the member's parameter (`:216-218`, and
     `locale: .current` under "Known limits", `:368-369`, kept by the tester's
     `limit_localeWrittenIntoTheMember`), the timer form (`:225-226`).
8. **N12 moves to the `LedgerDesign` chore.** The test fixture catalog's own table needs edits in the tester's
   `CatalogBuildAdversarialTests` (six lookups, two `unresolvedKeys` calls, the fixture's path) and a `table:`
   parameter on `unresolvedKeys`; this touch-up leaves all of that.

**Also changed, not in the list.** `docs/ci-cd.md:41` and `docs/testing-strategy.md:465-466` name the tester's
suite, and §7's "Known limits" names its close-out suite (`:344-348`): the tester's close-out listed these as
due. `SwiftSourceTests` is split in two files for the lint's length limit.

**Checks, on the final tree.**

- The gate: `/usr/bin/python3 …/sim-lock.py scripts/check.sh`, from the worktree root, at 01:40: `GATE_EXIT=0`,
  `check.sh OK`, 510 s (lint and script tests 71, iOS build 13, string catalogs under 1, iOS tests 221, watchOS
  build 13, watchOS tests 188, coverage 2), with no wait for the lock. Coverage 98.48 % overall. After it only
  this section changed. (The first pass's tree passed the gate twice, at 01:06 and 01:23, in 513 s and 508 s.)
- Script suites, in that gate and by themselves: `string-catalogs-tester.adv.sh` 37 of 37, ST04 among them;
  `string-catalogs.adv.sh` 82 of 82 (71 before the touch-up; SC09, SC17 and SC18 changed, SC71–SC81 new); all
  12 suites pass.
- Swift, on the Mac host: `LedgerAppKitTests`, 196 tests in 30 suites, exit 0. The gate ran them on the
  simulator.

**Size.** No product file changed: 170 lines added and 16 removed for the slice, as after fix round 1. Test
support: `StringCatalog.swift` 209 lines (was 181), `SwiftSource.swift` 148 (115), `CopyAuditRules.swift` 213
(207). The script is 240 lines (190) and its suite 488 (407).

**Not done as written.**

- n1, by ruling.
- The first known limit is narrowed where the task says to remove it (item 4): part of it is still true.
- The UI tests were not run again: they are not in the PR plan, and no file they build changed.

### S1 — orchestrator's close (2026-10-05)

- The touch-up's one edit to the tester's suite is the sanctioned one: ST04's two fixture file names, three lines;
  the tester's Swift files are unchanged since `cf7e459`. The tester's closing conditions are met (the rulings are
  built, F9-S1-12 is fixed, F9-S1-13 and -14 each have their sentence), so **G2 is closed**; **G3 approved** at the
  re-review, and its three items are done.
- §7's first known limit is narrowed rather than removed (it still holds for literals that are not lookups and for
  a module without a catalog). Accepted.
- `main` (F10 S1, #27) is merged into the branch before the gate that precedes the push.

## Slice S2 — Domain additions (G1 implementer, 2026-10-05)

Branch `feat/F09-s2-domain` at `985a8fb` (the specification). No commits. Paths that start with a module name are
under `LedgerKit/Sources/`; test paths are under `LedgerKit/Tests/LedgerDomainTests/`. The specification is the
brief's last section ("Plan amendments — slice S2"); "the task" below is the orchestrator's message that started
this slice.

### What landed

**LedgerDomain (product, 54 lines)**
- `Rules/WeekCalendar.swift`, appended after the schedule helpers:
  - `public struct ScheduledDay: Hashable, Sendable` with `date: CivilDate`, `weekIndex: Int`,
    `dayTemplateID: DayTemplateID`, a public memberwise `init`, and `weekday: Weekday` computed from `date`.
  - `WeekCalendar.nextScheduledDay(after date: Date, in program: Program) -> ScheduledDay?`.
- `Units/Volume.swift`, after `compact(in:)`: `thousands(in units: Units) -> String` and
  `percentChange(from previous: Volume) -> Int?`.
- `Model/Loadable.swift` (new): `public enum Loadable<T> { case idle, loading, loaded(T), failed(any Error) }` and
  `extension Loadable: Sendable where T: Sendable {}`.

Nothing that existed changed: `git diff -U0 985a8fb -- LedgerKit/Sources` is two hunks of added lines (+57 in
`WeekCalendar.swift`, +26 in `Volume.swift`) and the new file. Nothing uses the new code yet.

**Tests (27 new, in `LedgerDomainTests`)**
- `Support/Fixtures+Schedule.swift` (new): spec §6.4's four days and its 8-week schedule
  (`Fixtures.fourDayProgram(startDate:)`), and a block that trains every day (`everyDayProgram`).
- `Rules/WeekCalendarTests+NextScheduledDay.swift` (new; 3 tests of the `WeekCalendarTests` suite): a table of
  16 moments in §6.4's block begun on 2026-09-14, the brief's three among them; one instant read in three zones;
  a table of 23 moments around midnight in six zones.
- `Rules/WeekCalendarTests+NextScheduledDayBlocks.swift` (new; 8 tests of the same suite): a block begun
  midweek under every week start, empty weeks, nothing scheduled, no weeks, weeks edited after validation, a
  block that runs past 9999-12-31, extreme moments, a 5,000-week block, and the `ScheduledDay` value.
- `Rules/NextScheduledDayPropertyTests.swift` (new; 2 seeded tests, tag `.property`): random blocks, zones,
  week starts and moments against a slow day-by-day reference written in the test.
- `Units/VolumeTests.swift`: 10 tests appended in two extensions (`git diff 985a8fb` shows 149 insertions and no
  deletion in it).
- `Units/VolumePropertyTests.swift` (new; 2 seeded tests): the percent against integer arithmetic; `thousands`
  against `compact`.
- `Model/LoadableTests.swift` (new; 2 tests).

**Docs**: `docs/architecture.md` §5, the `WeekCalendar` line, names the next scheduled day. Architecture lists
neither `Volume`'s formatting nor `Loadable`, so it has no other line to change.

### Decisions and deviations

1. **`Loadable` is standards §5's, where §5, the brief and the plan differ.** §5
   (`docs/engineering-standards.md:129-130`) writes `enum Loadable<T> { case idle, loading, loaded(T),
   failed(Error) }`. The brief's criterion 4 (`tasks/features/F09-today.md:157-158`) names the parameter `Value`,
   and the plan's shape (this file, "Inputs › S2") constrains it, `Loadable<Value: Sendable>`. As the task rules,
   §5 wins on both: the parameter is `T` and it is unconstrained. Three things are not differences:
   - `failed(any Error)` is §5's `failed(Error)`, the same type, spelled with `any` as the module spells every
     existential (`any Decoder`, `any Encoder`).
   - `public`, without which no feature could use it.
   - `Sendable` when `T` is (criterion 4), as a conditional conformance. §5 does not forbid it and §4 asks it of
     every type that crosses an isolation boundary. A value that is not `Sendable` can still be held
     (`LoadableTests.sendable_whenItsValueIs`).

   Nothing else is added: no `Equatable` (an `any Error` has none), no `value` accessor, no `map`. See open
   question 1 on the parameter's name.
2. **`percentChange` is `nil` in one more case than the task names.** The task says it "returns `nil` only for a
   zero previous volume"; the specification says "`nil` when the previous volume is zero" and "never traps,
   whatever the two volumes". Built:
   - Zero previous: `nil`.
   - A change beyond `Int`: clamped to `Int.min` or `Int.max`. This is the decision the task asks for.
   - A result that is not a number: `nil`. That is a NaN volume (`Volume(gramReps: .nan)` can be built, though
     never encoded or decoded), or arithmetic that leaves `Decimal`'s own range of about 3.4 × 10¹⁶⁵, where
     `Decimal` gives NaN and does not trap (measured on the host: `Decimal.greatestFiniteMagnitude * 100`, the
     same value divided by `leastNonzeroMagnitude`, and `x / 0` are all NaN).

   Why not a number for the third case. No integer is honest there: `greatestFiniteMagnitude` after its own
   negative is −200 % in truth, but the difference overflows, so a value chosen by sign would be a wrong number,
   and 0 would read as "no change". `nil` hides the delta, which is what Today does when it has nothing to
   compare. `WorkoutState.elapsed(at:)` maps NaN to zero (`Model/WorkoutState.swift:111`), but it has no optional
   to return. A volume in the app cannot get there: weights are not negative and 10¹⁶⁵ gram·reps is out of reach.
   Left unguarded, the result would have been garbage, not a trap: `NSDecimalNumber(decimal: .nan).intValue`
   returned 4382196393 on the host, and NaN compares below every number, so a clamp alone would have given
   `Int.min`. See open question 2.
3. **`percentChange`'s arithmetic.** `(self − previous) ÷ previous × 100`, all in `Decimal`, then one rounding,
   half away from zero (`Decimal.roundedToInt()`, `Units/NumberText.swift:19`; the clamp comes before it and
   cannot move a value inside the range). It is the brief's rule as written ("delta = (this −
   previousCompleteWeek) / previousCompleteWeek"), so:
   - It is the same number in pounds and kilograms, and for a pound volume against a kilogram one.
   - A negative previous volume keeps the formula's sign: −50 after −100 is −50 (pinned by
     `percentChange_negativePrevious_followsTheFormula`). No volume in the app is negative.
   - How exact: the subtraction and the multiplication are exact, and the one division carries 38 significant
     digits. A tie is a terminating decimal and comes out exact (the tie rows, in pounds and in kilograms). The
     rounding is right for any two volumes that differ by fewer than about 5 × 10³⁴ of their last decimal place
     (for pounds to the hundredth, 5 × 10²⁷ gram·reps). Beyond that a result within one part in 10³⁷ of a tie
     could round the other way; I did not build a remainder check for it. The seeded test compares against
     integer arithmetic up to 10¹⁰ lb in hundredths.
4. **`thousands(in:)` is cut from `compact(in:)`**: `String(compact(in: units).dropLast())`, with "0" for the
   zero volume. The two therefore agree by construction, pounds and kilograms, grouping and sign included. The
   other way to share the digits, a helper that both call, would change `compact`'s body, and the slice changes
   no existing declaration.
   - "Zero" is the zero volume (`gramReps == 0`), as the specification says ("Zero reads "0"; every other volume
     keeps one decimal"). A volume that only rounds to zero keeps the decimal: 40 lb reads "0.0", and 50 lb reads
     "0.1". See open question 3.
   - For volumes beyond `Int` it prints what `compact` prints. That is F02's behaviour and not this slice's:
     `Decimal.roundedToInt()` wraps there (it never traps), so the digits are meaningless from about 9 × 10¹⁸
     units. `thousands_extremes_neverTrap` pins only that nothing traps. See open question 4.
5. **`ScheduledDay.weekday` is computed from `date`**, not stored. The specification lists four things the value
   gives ("its `CivilDate`, the program week's index, its `Weekday` and the `DayTemplateID`"); a stored weekday
   could disagree with the date, and a computed one cannot. So the `init` takes three arguments.
6. **What "the block" is, for a program edited after validation.** `Program.weeks` and `Week.index` are `var`
   (`Model/Program.swift:18`, `Model/Week.swift:38`), so a caller can hold weeks out of order, an index twice, a
   gap, or no weeks. `nextScheduledDay` follows the two functions that already answer for such a program:
   - The block is `weeks.count` weeks from `startDate`, as `isBlockComplete` counts it
     (`Rules/WeekCalendar.swift:132-134`).
   - A day's week is the first week that carries its index, as `Program.week(at:)` finds it
     (`Model/Program.swift:64-66`) and so as `scheduledDay(on:in:)` judges the day (`:127-129`).

   The function does not call `week(at:)` per day. It builds the index-to-week table once, first week wins, so
   the search is one pass over the weeks and at most seven days per week. With `week(at:)` (a linear scan) per
   candidate, an empty block of n weeks would cost about 3.5 n² comparisons, and rule 4 sets no maximum length.
   `nextScheduledDay_editedWeeks_resolveAsScheduledDayDoes` and the second seeded test hold the two readings
   together.
7. **Today is never the answer, and a moment before the block gives the block's first session**, wherever that
   is: with an empty first week it is in the second (`nextScheduledDay_emptyWeeks_arePassedOver`).
8. **A block that runs past 9999-12-31** stops there: a later day has no `CivilDate`, so there is nothing to
   return (`nextScheduledDay_blockPastYear9999_endsAtTheLastCivilDate`).
9. **No instant arithmetic.** The moment becomes a day number once (`CivilDate.dayNumber(of:in:)`, in the
   calendar's zone); everything after is integer days. Foundation maps any `Date`, the infinities and NaN
   included, to a day between 4713 BC and the year 506713 (measured on the host), so no moment overflows.
10. **Tests of the existing suites are in new files**, as extensions (`WeekCalendarTests.swift` is 262 lines
    and the lint stops a file at 300), except `VolumeTests.swift`, which only grew. The seeded suite is
    `NextScheduledDayPropertyTests`: the name with a `WeekCalendar` prefix is 41 characters, one over the lint's
    limit for a type name.
11. **The midnight table depends on the zone database.** It uses the transitions the F02 suites already use
    (Santiago 2026-09-06, Havana 2026-03-08, Cairo 2026-04-24, each a 23-hour day) and adds three 25-hour days
    (Santiago 2026-04-04, Havana 2026-11-01, Cairo 2026-10-29). Each row first asserts how long its day is, so a
    changed zone rule fails with that message and not with a wrong session.
12. **The plan and the code agree**, with two small corrections to the plan's inputs: `Volume.value(in:)` is
    `private`, not internal (`Units/Volume.swift:58`, line 32 before this slice), and neither new function needs
    it; and the extension uses the private `dayNumber(of:)` (`Rules/WeekCalendar.swift:102`), not the private
    `calendar`.
13. **Size**: 54 product lines against the plan's ~80.

### Criteria → tests

| S2 criterion | Proof |
|---|---|
| 1. `nextScheduledDay(after:in:)`: the first later scheduled day, in the calendar's zone, as a `ScheduledDay`; bounded by the block; before the block gives the first session; each day judged by its own program week; the three dated examples | `WeekCalendarTests.nextScheduledDay_fourDayBlock_isTheFirstLaterSession` (16 rows; rows 1, 2 and 9 are the brief's: after Wed 09-16 it is Fri 09-18, Upper B, week index 0; after Sat 09-19 it is Mon 09-21, Upper A, week index 1; after week 8's Friday it is `nil`), `nextScheduledDay_sameInstant_followsEachZonesDay` (UTC+14, UTC−11 and UTC give three different sessions for one instant), `nextScheduledDay_aroundMidnight_followsTheCivilDay` (23 rows: one second before and at midnight in UTC, Kiritimati and Pago Pago; 23-hour days in Santiago, Havana and Cairo; 25-hour days in the same three), `nextScheduledDay_blockBegunMidweek_readsEachDaysOwnProgramWeek` (all seven week starts), `nextScheduledDay_emptyWeeks_arePassedOver`, `nextScheduledDay_nothingScheduled_isNil` (an empty schedule; no weeks), `nextScheduledDay_editedWeeks_resolveAsScheduledDayDoes`, `nextScheduledDay_blockPastYear9999_endsAtTheLastCivilDate`, `nextScheduledDay_extremeMoments_neverTrap`, `nextScheduledDay_longBlock_findsItsLastDay`, `scheduledDay_weekdayAndEquality`; seeded, 200 blocks each with 8 moments: `NextScheduledDayPropertyTests.nextScheduledDay_matchesTheDayByDaySearch` and `nextScheduledDay_editedWeeks_matchTheDayByDaySearch` |
| 2. `percentChange(from:)`: whole percent, half away from zero, exact, `nil` for a zero previous volume, never traps | `VolumeTests.percentChange_isAWholePercent` (24,180 against 22,400 lb is 8; 21,728 is −3; equal is 0), `percentChange_ties_roundAwayFromZero` (16 rows, each in pounds and in kilograms: ±0.5, ±1.5, ±2.5, ±99.5 and their near misses), `percentChange_zeroPrevious_isNil`, `percentChange_negativePrevious_followsTheFormula`, `percentChange_beyondInt_isClamped` (the last value inside each bound, the bound, one past it, 10⁶⁰, the greatest `Decimal`), `percentChange_notANumber_isNil`; seeded: `VolumePropertyTests.percentChange_matchesIntegerArithmetic` (200 seeds of 50 pairs) |
| 3. `thousands(in:)`: `compact`'s number without the "k"; the same kilogram conversion; zero reads "0"; one decimal otherwise | `VolumeTests.thousands_isCompactWithoutTheK` ("24.2" for 24,180 lb, "11.0" for it in kilograms, "1,234.5"), `thousands_zero_readsZero` (three zeros; 40 lb reads "0.0"; `compact` still prints "0.0k"), `thousands_plusK_isCompact` (10 amounts, both units, both ways), `thousands_extremes_neverTrap`; seeded: `VolumePropertyTests.thousands_matchesCompact` |
| 4. `Loadable`: `idle`, `loading`, `loaded`, `failed(any Error)`; `Sendable` when its value is | `LoadableTests.cases_carryTheirPayloads` (a `switch` with no `default` over the four cases, so a fifth case or a missing one does not compile), `sendable_whenItsValueIs` (handed to a function that takes only `Sendable` values; a class that is not `Sendable` can still be loaded) |
| 5. Foundation only; covered line for line; no existing test changes | `ModuleBoundaryTests.sources_importFoundationOnly` (untouched; `Loadable.swift` imports nothing); file coverage under "Gate and coverage"; `git diff 985a8fb --stat -- LedgerKit/Tests` shows insertions only, in one existing file |

**The slow reference** (`NextScheduledDayPropertyTests.slowNextScheduledDay`). From noon of the moment's own day
it steps one calendar day at a time with Foundation's `date(byAdding: .day, …)` and returns the first day for
which `scheduledDay(on:in:)` gives a template. It skips days before the block and gives up once
`isBlockComplete` is true. The moments and their days are built with Foundation alone: the first instant of a day,
its last second, or a second of its first 23 hours, from 15 days before the block to 15 days after ten weeks, in
13 zones. The same answer is also required under a second, random week start.

**Mutants.** Twenty small changes to the new code, one statement each, were each run against the final tests on the host (a
scratch script, not committed; the two sources' SHA-256 were checked against the ones taken before it). Each
failed at least one test, one of them by trapping:
- `nextScheduledDay`: the next day taken 86,400 seconds later (only the midnight table and the seeded test fail,
  which is what they are for); today included; the block one week short, one week long, one day short; the last
  week winning a repeated index; the stats week's index in place of the program week's; the block's first day left
  out for a moment before it (a trap); the UTC day in place of the zone's; the wrong weekday.
- `percentChange`: banker's rounding; truncation; half up for negatives; no clamp; no NaN guard; the absolute
  previous volume as divisor; `Double` arithmetic.
- `thousands`: zero keeping its decimal; "0" for every volume that rounds to zero; pounds whatever the unit.

### Code lines (added lines of `git diff -U0 985a8fb`, new files whole, blank and whole-line comment lines excluded)

| Path | Added | Removed |
|---|--:|--:|
| `LedgerDomain/Rules/WeekCalendar.swift` | 34 | 0 |
| `LedgerDomain/Units/Volume.swift` | 13 | 0 |
| `LedgerDomain/Model/Loadable.swift` (new) | 7 | 0 |
| **Product** | **54** | **0** |
| Tests (`WeekCalendarTests+NextScheduledDay` 226, `…Blocks` 140, `NextScheduledDayPropertyTests` 134, `VolumeTests` 126, `VolumePropertyTests` 63, `LoadableTests` 44, `Fixtures+Schedule` 40) | 773 | 0 |

Not counted: one line of `docs/architecture.md` and this section.

### Gate and coverage

**Full gate.** `/usr/bin/python3 <sim-lock> scripts/check.sh` from the worktree root, on the final tree (11 GB
free before it): **exit 0 (`GATE_EXIT=0`), `check.sh OK`**, 789 s (tools 1 s, format 0 s, lint and script tests
87 s, iOS build 71 s, string catalogs 0 s, iOS boot 1 s, iOS tests 316 s, watchOS build 51 s, watchOS boot 0 s,
watchOS tests 259 s, coverage 2 s). Queued 2026-10-05 04:14:25, it did not wait for the lock and ended 04:27:34.
I ran no other build during it. A hash of `git diff 985a8fb` and of the new files, taken before the gate, was the
same after it. After the gate only Markdown changed: this subsection and one phrase under "Mutants";
`scripts/check.sh --lint-only` passed again afterwards (exit 0).

- **iOS (PR plan)**: 1,926 tests, 1,905 passed, none failed, 12 skipped, 9 expected failures.
- **watchOS (PR-Watch plan)**: 1,575 tests, 1,558 passed, none failed, 12 skipped, 5 expected failures.
- `LedgerDomainTests` on each simulator: 812 tests, 810 passed and 2 skipped. None of the skipped tests or
  expected failures is this slice's: all 27 new tests passed on both simulators, with every row (four seeded
  tests of 200 seeds, and tables of 16, 23, 16 and 10 rows). So the 23- and 25-hour days of the midnight table
  hold in both simulators' zone data, as on the Mac.
- The gate log holds 10 compiler warnings, in three test files this slice does not touch
  (`LedgerPersistenceTests/Adversarial/PayloadVersionAdversarialTests.swift:29`,
  `LedgerDesignTests/PreviewTests.swift:90`, a `@Test` expansion in
  `LedgerPersistenceTests/Adversarial/SettingsDecodingAdversarialTests.swift:123`). They print when those files
  compile, and this slice changes `LedgerDomain`, which every target depends on. None names a file of this
  slice. I did not run a gate on `985a8fb` to compare.

| Module | Lines | Coverage | Threshold | |
|---|--:|--:|--:|:-:|
| LedgerDependencies | 228 / 237 | 96.20 % | 90 % | ✓ |
| LedgerDesign | 2113 / 2175 | 97.14 % | 60 % | ✓ |
| LedgerDomain | 2089 / 2107 | 99.14 % | 95 % | ✓ |
| LedgerFakes | 1413 / 1428 | 98.94 % | 90 % | ✓ |
| LedgerHealth | 47 / 48 | 97.91 % | 80 % | ✓ |
| LedgerPersistence | 2479 / 2497 | 99.27 % | 90 % | ✓ |
| LedgerSync | 31 / 34 | 91.17 % | 90 % | ✓ |
| Overall | 8400 / 8526 | 98.52 % | 80 % | ✓ |

**The new code's coverage**, read from both result bundles (`xcrun xccov view --report --json` and
`--archive --file`), the same on iOS and watchOS:

| File | Lines | New code |
|---|--:|---|
| `LedgerDomain/Units/Volume.swift` | 46 / 46, 100 % | `thousands(in:)` 3 / 3, `percentChange(from:)` 10 / 10 |
| `LedgerDomain/Rules/WeekCalendar.swift` | 105 / 107, 98.13 % | `ScheduledDay.init` 5 / 5, `weekday` 3 / 3, `nextScheduledDay(after:in:)` 20 / 20 and its three closures 5 / 5 |
| `LedgerDomain/Model/Loadable.swift` | no executable line | the cases are proven by the test's `switch` |

Every executable line this slice added (28 in `WeekCalendar.swift:145-200`, 13 in `Volume.swift:32-56`) has a
count above zero and no uncovered region. The two lines `WeekCalendar.swift` lacks are F02's: the two `?? 0`
fallbacks of `isoWeekKey(for:)` at line 96, which Foundation never takes.

**Host (Mac, final tree).** `scripts/check.sh --fast`: exit 0 (format, lint, the script suites, and
`LedgerDomainTests` with 823 tests in 135 suites and `LedgerPersistenceTests` with 449 tests in 103 suites). The
two seeded suites of this slice also pass at 5,000 seeds (`LEDGER_PROPERTY_SEED_COUNT=5000`, about 2 s each on the
host); the nightly lane runs 2,000.

**Not verified.**
- No device build: on a watch whose `Int` is 32 bits the clamp is to that `Int`'s bounds by construction
  (`Decimal(Int.min)`, `Decimal(Int.max)`), but no test ran there.
- CI did not run: nothing is pushed.
- The whole package on the host, unfiltered, was not run; the gate ran every test target on the simulators.

### Open questions (each with a recommendation)

1. **`Loadable`'s parameter is `T`; every other generic in `Sources` has a word for a name** (`Tally<Value>`,
   `ObservedState<State, Value>`, `JSONArray<Element>`), and the brief writes `Loadable<Value>`. No caller writes
   the parameter's name; only an extension with a `where` clause would. Recommend renaming it to `Value` and
   changing §5's sketch in the same small change, before S5, F08 or F10 extend the type. Until §5 says so the
   code follows §5.
2. **`percentChange` returns `nil` for a result that is not a number** (decision 2), where the task says "only
   for a zero previous volume". Recommend keeping it: the alternatives are a wrong number or an arbitrary one.
   If the ruling is "never `nil` but for zero", the smallest change is to return 0 there, as `elapsed(at:)` does
   for NaN: one line and one test.
3. **A week's first light set reads "0.0k"**, not "0k": any volume under 50 lb that is not zero (decision 4).
   Recommend keeping the specification's rule and looking at it in S4's screenshots; "0" for everything that
   rounds to zero would be one condition in `thousands(in:)` and is one of the mutants the tests now refuse.
4. **`Volume.formatted(in:)` and `compact(in:)` print wrapped digits beyond `Int`** (F02; `thousands` inherits
   it). Not reachable by lifting. Recommend leaving it and not re-finding it as S2's; if it is ever wanted, the
   fix is a clamp in `Decimal.roundedToInt()`, which S2 may not touch.
5. **An empty week between today and the next session** (plan, "Behaviour the brief leaves open"): the rest
   card's "next Monday" would be two weeks away. `ScheduledDay.weekIndex` and `date` let S3 tell; new copy would
   be Pete's. Recommend S3 keeps the accepted wording.
6. **Simulator zone data.** The 25-hour rows are new to the suite (decision 11). If a runner's zone database
   differs from this Mac's, those rows fail on their day-length line. Recommend keeping them; the fix then is a
   date, not the function.

### Inputs for S3

- **Next session.** `WeekCalendar(startDate: program.startDate, weekStart: settings.weekStart, calendar: calendar)
  .nextScheduledDay(after: now, in: program)` returns `ScheduledDay?`:
  - `date: CivilDate`, the day; `date.startOfDay(in: calendar)` is a `Date` for `Date.FormatStyle`'s weekday.
  - `weekday: Weekday`, the same day's weekday.
  - `weekIndex: Int`, the program week of that day, 0-based. Compare it with `weekIndex(for: now)`:
    equal is "later this week" in program weeks; `weekIndex + 1` is the "Next: week %lld" number.
  - `dayTemplateID`, to find the day's `tag` in `program.days`.
  - `nil` means no later session in the block. That is not always the block's last week: in week 3 of 8 it is
    `nil` when the later weeks are empty. The Logged card's "Next:" line is omitted. The rest card says "This is
    the last week of the block" only when `weekIndex(for: now) == program.weeks.count - 1`; what an earlier week
    with nothing left says is S3's to decide, and the brief has no copy for it. Today itself is never returned,
    logged or not. (Corrected in fix round 1, review nit n6.)
  - The brief's rest-card copy says "next %@" for "first day of next week". Program weeks and stats weeks differ
    when the block began midweek or the week start changed; whichever S3 means, `date` and `weekIndex` give both
    (`week(containing:)` for the stats week).
- **Delta.** `thisWeek.percentChange(from: previousWeek)` is `Int?`. `nil` hides the delta (a zero previous week;
  the absent previous week is S3's own `nil`). The sign is S3's to print ("+8%", "−3%" with U+2212); 0 comes back
  for anything within half a percent, −0.4 % included, and the brief does not say how 0 reads.
- **Tile.** `volume.thousands(in: settings.units)` is the value for the catalog's "%@k": "24.2", "1,234.5", and
  "0" for the zero volume, which gives criterion 8's "0k". It is a Domain-formatted string (no locale), like
  `formatted(in:)`.
- **State.** `Loadable<TodayModel>` has no `Equatable`: tests match it with `if case` or `switch`. It is
  `Sendable` when the model is.
- **Fixtures.** `LedgerDomainTests`' `Fixtures.fourDayProgram()` is not visible to `FeatureTodayTests`; S3
  re-dates `LedgerFakes`' `Fixtures.seedProgram()` as its plan says.

### S2 — orchestrator rulings after G2 and G3 (2026-10-05)

G3 approved: 0 Blocking, 0 Should fix, 6 nits. G2 round 1: 61 tests, one failing on purpose; four findings. The
tester's own full gate was not run (free disk under the floor); the orchestrator's gate after the fix round replaces it.

- **F9-S2-1 accepted, fixed at the root.** A volume too small to show prints an arbitrary number that differs from
  call to call, through `thousands(in:)` and through the existing `compact(in:)`. The fix goes where both get their
  digits, so both read "0.0" / "0.0k"; this is the one sanctioned change to existing behaviour in the slice (no
  real workout can produce the input). A test covers `compact` too.
- **F9-S2-2:** no change of behaviour; the doc comment states the true conditions for `nil` (the brief's criterion 2
  is revised), without a wrong bound.
- **F9-S2-3 accepted as specified:** days are calendar dates (ADR-007); a date a zone skipped can be the answer. The
  doc comment says so (criterion 1 revised).
- **F9-S2-4 accepted:** the three weak assertions are strengthened.
- **Review nits:** all six taken: the negative-baseline sign in `percentChange`'s doc; `thousands` and `compact` share
  one function for their digits instead of `dropLast`; `#require` for the day-length check; `Loadable<T>` stands (the
  brief now says `T`, as §5 does); and, for S3, `nil` from `nextScheduledDay` means "no later session in the block",
  which is not always "the last week of the block" (later weeks may be empty): the "Inputs for S3" line is corrected.

### S2 fix round 1 (G1 implementer, 2026-10-05)

On `feat/F09-s2-domain` at `09f2619`. No commits. Host only, as ruled: no simulator ran and no full gate.
"Before" below is `09f2619`.

**F9-S2-1: the cause.** `Decimal.roundedToInt(_:)` (`Units/NumberText.swift:19-21` before) handed whatever it had
to `NSDecimalNumber.intValue`. For a NaN that conversion is undefined. Measured on the host:
`NSDecimalNumber(decimal: .nan).intValue` was 4377898889 in one launch and 4309954441 in the next, and the
tester's table shows other numbers at other call sites in one launch.

The NaN is Foundation's: `Decimal` division gives NaN, not zero, for a quotient it takes to be too small.
`compact(in:)` divided twice, by the unit (`Units/Volume.swift:59` before, `value(in:)`) and by 100 (`:28`
before). Measured on a scratch copy of the arithmetic, for 1, 5 and 9 times each power of ten:
- the second division is NaN for every volume from 10⁻¹²⁷ g up to 10⁻⁸⁶ g, in both units;
- the first is already NaN up to 10⁻⁹⁶ g in pounds and up to 10⁻⁸⁸ g in kilograms;
- 10⁻⁸⁰ g is a number and read "0.0" before too.

That is well short of the smallest `Decimal`: 10⁻⁸⁷ g is 10⁻⁹⁰ kg, a number, and a hundredth of it is NaN
although `Decimal` can hold 10⁻⁹². I did not read Foundation's source for why.

**The fix** is one line, `Units/NumberText.swift:24`: the conversion is now
`isNaN ? 0 : NSDecimalNumber(…).intValue`. A value that is not a number rounds to 0, and the comment above it
says why. For the
formatters 0 is the right number and not only a convention: dividing a number by 453.59237, by 1,000 or by 100
can only make it too small, never too large, so a NaN there is a value nearer zero than `Decimal` can say (or
the weight or volume was NaN to begin with).

`compact(in:)` and `thousands(in:)` now take their digits from one private function,
`Volume.compactDigits(in:)` (`Units/Volume.swift:62-65`): `compact` appends "k", `thousands` returns it as it is,
or "0" for the zero volume. Nothing is cut from a string any more (review n2).

**What changed in existing behaviour, and for which inputs.** Only a value that is not a number, at the helper.
Every text for a value that is a number is the same as before: the existing tests pass untouched, and
`NumberTextTests.roundedToInt_numbers_roundByTheRule` pins the rounding.

| Caller of `roundedToInt` | Input that reached it as NaN | Before (one host run) | Now |
|---|---|---|---|
| `Volume.compact(in:)`, `Volume.thousands(in:)` (`Units/Volume.swift:63`) | a volume of 10⁻⁸⁶ g or less, either sign; a NaN volume | arbitrary ("431,784,903.3k" in the tester's run) | "0.0k", "0.0" |
| `Volume.formatted(in:)` (`:23`) | a volume of 10⁻⁹⁶ g (lb) or 10⁻⁸⁸ g (kg) or less; a NaN volume | arbitrary ("527,145,074,697" for 10⁻¹²⁷ g) | "0" |
| `Weight.wholeValue(in:)` (`Units/Weight.swift:114`) | the same sizes, as a weight; a NaN weight | arbitrary (4339062169 for 10⁻¹²⁷ g) | 0 |
| `PlateMath.perSide(load:inventory:)` (`Rules/PlateMath.swift:52`) | a plate too heavy for its count to be held: 10⁻³⁰ g per side against a 10¹⁰⁰ g plate | the plate loaded 4,339,062,169 times, a remainder of −4.3 × 10¹⁰⁹ g | the plate is left off |
| `RPE.init?` (`Units/RPE.swift:16`) | none: the guard above admits only whole values from 10 to 20, and a NaN fails it | unchanged | unchanged |
| `Volume.percentChange(from:)` (`Units/Volume.swift:57`) | none: `isFinite` is checked first | unchanged | unchanged |

Those six are every caller (`grep roundedToInt LedgerKit/Sources`). The four affected ones are fixed by the same
line. No stored weight or volume is near these sizes (ADR-007 stores whole 10⁻⁷ g), and no plate is 10¹³⁰ times
the load.

**Found beside it, reported and not fixed** (none is the same line):
1. **`Weight.formatted(in:)` prints "NaN"** for the same sizes (`Units/Weight.swift:101-109`; it does not use the
   helper). Run through the module: 10⁻¹²⁷ g reads "NaN" in both units; 10⁻⁸⁸ g reads "0" in pounds and "NaN" in
   kilograms; a NaN weight reads "NaN". It is the same text on every call, so it is not F9-S2-1's fault, but it
   is not a number. A fix would be in that function or in `Weight.value(in:)`. Recommend a line in the next slice
   that touches `Weight`, with the orchestrator's leave.
2. **Beyond `Int` the digits wrap** (F02; the tester's "other end"; my open question 4). `roundedToInt` wraps
   when the rounded value does not fit an `Int`. Run through the module: 10²⁵ g reads
   "-89,866,669,963,703,866.9k" through `compact`, "2,367,050,404,843,891,177" through `formatted` and
   2367050404843891177 through `wholeValue`; the greatest `Decimal` reads "0.0k". The cause is another one (the
   size of `Int`, not NaN) and the cure is a clamp in the same helper, a second change of existing behaviour that
   this round does not sanction. `thousands` and `compact` still agree there (one function now).
3. `LedgerPersistence` converts an RPE with `NSDecimalNumber(decimal:).intValue` directly
   (`Records/SlotRecords.swift:53`, `Records/WorkoutRecords.swift:140`). An `RPE` is always 5 to 10, so no NaN
   reaches it. No change wanted.

**What changed, item by item.**
1. **F9-S2-1.** The helper's line and comment (`Units/NumberText.swift:18-25`); `compactDigits(in:)`, with
   `compact`'s and `thousands`' bodies and `thousands`' comment (`Units/Volume.swift:26-37, 60-65`). Tests:
   - The tester's `thousands_smallestDecimalVolume_readsZeroPointZero` passes, with no edit to any tester file.
   - `VolumeTests.thousands_volumeTooSmallToShow_readsZeroPointZero`: 484 volumes of both signs from 10⁻¹²⁷ g
     to 10⁻⁷ g, in both units, read "0.0".
   - `VolumeTests.compact_volumeTooSmallToShow_readsZeroPointZeroK` (the test for `compact`): the same volumes
     read "0.0k" through `compact` and "0" through `formatted`.
   - `NumberTextTests` (new file, 4 tests): NaN rounds to 0 under every rule; numbers round as before;
     `Weight.wholeValue` for a weight too small to show; `PlateMath.perSide` with the plate too heavy to count.
   - Run before the fix, these and the tester's test recorded 986 issues, 4 of them the tester's; after it,
     none.
2. **F9-S2-2.** `percentChange`'s comment (`Units/Volume.swift:39-48`) names the three conditions for `nil`
   without a bound: `previous` is zero; either volume is not a number; `Decimal`'s arithmetic gives no number
   for the difference, the quotient or the percent. It also says that for a negative `previous` the sign is the
   formula's, with the example 100 after −100 is −200 (review n1). No behaviour changed. The line in my
   decision 2 above that gives "about 3.4 × 10¹⁶⁵" as where `nil` begins is wrong, as the tester showed (10¹²⁶
   after 1 is already `nil`); I have left that paragraph as written and correct it here.
3. **F9-S2-3.** `nextScheduledDay`'s comment (`Rules/WeekCalendar.swift:170-181`) says days are calendar dates
   and that a date a zone once skipped can be the answer, with Pacific/Apia's 2011-12-30 (checked on the host:
   Thursday 23:59:59 is followed by Saturday 00:00:00). No behaviour changed.
4. **F9-S2-4.**
   - `VolumeTests.thousands_extremes_neverTrap` is replaced by three tests with exact texts: the two above and
     `thousands_notANumberAndBeyondInt_agreeWithCompact` (a NaN volume reads "0.0" and "0.0k"; beyond `Int` the
     two still agree).
   - `Fixtures.everyDayProgram` gives each weekday of each week a template of its own
     (`Fixtures.everyDayTemplate(week:on:)`). The midnight rows and the year-9999 test now assert the template of
     the expected week and weekday, the weekday taken from Foundation's calendar.
   - `LoadableTests.sendable_whenItsValueIs` asserts "and only then": `Loadable<Draft>` and `Loadable<[Draft]>`
     are not `Sendable`, by two overloads that the compiler chooses between.
5. **Nits.** n3: the day-length check is `try #require` (`Rules/WeekCalendarTests+NextScheduledDay.swift:60`).
   n4: the seeded suite is `WeekCalendarPropertyTests`, in `Rules/WeekCalendarPropertyTests.swift`; lint allows
   it. The file was renamed with `mv`, not `git mv`, so `git status` shows a deletion and a new file until they
   are staged. n5: `Loadable<T>` stands. n6: the "Inputs for S3" line above is corrected in place and marked.

**Mutants** (seven, each against the final tests, sources checked by SHA-256 afterwards): `Loadable` always
`Sendable`; the next weekday's schedule entry and the next week's schedule (run against the midnight table
alone, which could not see either before); the NaN guard removed; NaN rounding to 1; `thousands` keeping the
"k"; `compact` losing it. All seven failed.

**Host results, final tree.**
- `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter
  'LedgerDomainTests|LedgerPersistenceTests'`: exit 0. `LedgerDomainTests`: 890 tests in 145 suites, all pass
  (884 in 144 before: 4 in `NumberTextTests`, and three `VolumeTests` in place of one). The tester's 61 are
  among them and all pass. `LedgerPersistenceTests`: 449 tests in 103 suites pass, with its 1 known issue.
- `git status --short` lists no file under `LedgerDomainTests/Adversarial/`.
- Host coverage (`--enable-code-coverage`, `LedgerDomainTests`): `Volume.swift` 49 / 49 lines and 22 / 22
  regions; `NumberText.swift` 105 / 106, the changed line covered in both branches (the regions it lacks are
  F02's, at lines 40 and 140); `WeekCalendar.swift` 105 / 107 as before.
- `scripts/check.sh --lint-only`: exit 0 (format, lint, package graph and pins, script suites), run after the
  last edit of this section.

**Product lines** (blank and whole-line comment lines excluded). This round: 7 added and 4 removed
(`Volume.swift` 6 and 3, `NumberText.swift` 1 and 1; `WeekCalendar.swift` comments only). The slice against
`985a8fb`: 59 added, 2 removed (`WeekCalendar.swift` 34, `Volume.swift` 17 and 1, `Loadable.swift` 7,
`NumberText.swift` 1 and 1).

**Not verified.**
- Nothing ran on a simulator, and no full gate: the orchestrator runs it. The coverage figures above are the
  host's.
- Only `LedgerDomainTests` and `LedgerPersistenceTests` ran. The other test targets link `LedgerDomain` and were
  not run on the host.
- An `Int` of 32 bits.

### S2 — orchestrator's close (2026-10-05)

- The orchestrator's full gate on the fix round's tree exited 0, with the tester's 61 tests passing and the tester's
  files unchanged since `09f2619`. The one failing test was F9-S2-1's; its cause was fixed at the root
  (`Decimal.roundedToInt` no longer hands a NaN to `NSDecimalNumber.intValue`). **G2 is closed; G3 approved.**
- Reported by the fix round and queued as follow-ups, not part of this slice (older formatting code, inputs no
  workout can produce): `Weight.formatted` prints "NaN" for a weight too small to show, and digits wrap for a value
  beyond `Int`.
- S2 is ready for its PR, which opens after #28 (S1) is on `main`: merge `main`, gate, push once.

## Slice S3 — orchestrator's brief (2026-10-05)

S3's specification is the brief's last section, "Plan amendments — slice S3". The branch
`feat/F09-s3-presentation` is cut from S2's tip `2d434aa`.

- Pete has not yet answered the two product questions this slice meets, so their defaults are built: a live
  workout takes over the card with Resume (criterion 4); a session done on another day does not make today's
  "Logged" (criterion 5). Keep each rule in one named function with its own tests, so the other answer is a small
  change.
- From S2's review: `nextScheduledDay` returning nil means "no later session in the block", which is not always
  "the last week of the block" (later weeks may be empty). The rest-day and Logged copy follow the function, not
  the week index.
- The localization rule is standards §7 as F09 S1 rewrote it: a catalog and `TodayCopy.swift`, nothing else to add;
  the gate's string-catalog step and `ModuleCopyTests` find the module by themselves.
- The session's workout arrives as a plain `WorkoutState?` (live, or finished in the one update that ends it); the
  store that subscribes is S5 and S6. Today plays no haptics.
- One PR: the plan estimates about 570 product lines. Stop and propose the split named in the plan ("strip, stats,
  recent" / "cards") only above about 750.

## Slice S3 — the presentation (G1 implementer, 2026-10-05)

Branch `feat/F09-s3-presentation` at `4abfb8f` (the specification). No commits. Paths that start with a module name
are under `LedgerKit/Sources/`; test paths are under `LedgerKit/Tests/FeatureTodayTests/`. "The specification" is the
brief's last section ("Plan amendments — slice S3"); "the task" is the orchestrator's message that started this
slice.

### The decision table for the card

Written before the code. The first row that holds decides the card; the header's title is decided by rows 2–6
alone, so a live workout changes the card and never the title.

| # | Holds when | Card | Title | Decided in |
|---|---|---|---|---|
| 1 | The session's workout is live | Up next, showing that workout (its name, its exercises), "Resume · m:ss" carrying `.resumeWorkout` | as rows 2–6 | `workoutTakingOver(_:)` (Pete's decision 1, default A) |
| 2 | There is no active program | No program, "Set up program" carrying `.setUpProgram` | "Today" | `day(_:)` |
| 3 | The moment is in program week `weeks.count` or later | Block complete, "Open Program" carrying `.openProgram` | "Today" | `day(_:)`, by `WeekCalendar.isBlockComplete` |
| 4 | The program schedules a session today, and a finished workout of the same program, week and day started today | Logged, "View session" carrying `.openWorkout(id)` | the day's name before " — " | `loggedWorkout(for:_:)` (Pete's decision 2, default A) |
| 5 | The program schedules a session today | Up next, "Start workout" carrying `.startWorkout` | the day's name before " — " | `day(_:)`, by `WeekCalendar.scheduledDay(on:in:)` |
| 6 | Otherwise: a rest day. A day before the block's first day is one, and speaks of the block's first week | Rest day, "Edit this week" carrying `.editWeek`, and the off-schedule list | "Rest day" | `day(_:)` |

- **Why a live workout comes first, before "no program" and "block complete".** The specification's criterion 4
  says the live workout takes over the card "whichever day it was started for, also on a rest day", and Pete's
  decision 1 gives the reason: Today is the way back to a running workout. A workout started on the block's last
  evening is still running after midnight, when the block is complete; a workout can outlive its program being
  replaced. In both cases the other card would leave the workout with no way back from Today. The live card needs
  nothing from the program (the workout carries its name and its exercises), so the order costs nothing.
  Criterion 7's cards still appear whenever no workout is live.
- **The two open product questions are one function each.** `workoutTakingOver(_:)` is Pete's decision 1: under the
  other answer (the prototype's) it returns the workout only on a day whose scheduled session it is
  (`SessionBuilder.resumable`), and nothing else changes. `loggedWorkout(for:_:)` is Pete's decision 2: under the
  other answer it drops the condition "started today", and nothing else changes. Each has its own tests
  (`live_*`, `logged_*`).
- **"Finished" includes the session's own workout the moment it is finished** (criterion 5): it is merged once, by
  id, into the week's workouts and into the recent ones (`withFinishedSession`), so the card, the strip, the tiles
  and the recent list flip in the same update, whichever of the session and the history arrives first. A discarded
  session's workout is neither live nor finished and changes nothing.

### What landed

**FeatureToday (product).** Everything but the route is internal: nothing outside the module builds an input or
reads a model (the store and the views are S4's and S5's, in this module).
- `TodayRoute.swift`: `public nonisolated enum TodayRoute`, the brief's six cases and `.openProgram`.
- `TodayInput.swift`: the one value `make` takes: `program`, `exercises` (by id), `settings`, `weekWorkouts`,
  `recentWorkouts`, `previousWeekVolume`, `session`, `now`, `calendar`, `locale`.
- `TodayModel.swift`: `header` (date, title, the gear's action), `weekStrip` (`[WeekStrip.Day]`), `card`
  (`upNext`, `logged`, `restDay`, `noProgram`, `blockComplete`), `stats` (two `Tile`s, shaped as `StatTile`
  takes them) and `recent`. `Equatable` and `Sendable`. A control is an `Action` (title and route); the Up-next
  card's button is `PrimaryAction`, `.start(Action)` or `.resume(Action, startedAt:)`.
- `TodayPresentation.swift`: `make(_:)`, the header, `Context` (the input with today's date, the strip's days, the
  program on the calendar and the finished workouts, resolved once), `Day` (what the program says about today)
  and the date and number helpers.
- `TodayPresentation+Card.swift`: `card(_:_:)`, the two rules, and the five cards.
- `TodayPresentation+OffSchedule.swift`, `+WeekStrip.swift`, `+Stats.swift`, `+Recent.swift`.
- `TodayCopy.swift` and `TodayCopy+Cards.swift`: 49 lookups, each `String(localized:bundle: .module)`, with
  `locale:` where the key carries a value.
- `Resources/Localizable.xcstrings`: 49 keys, six of them counted.
- The placeholder `FeatureToday.swift` is deleted, and with it `FeatureTodayTests.swift`
  (`module_name_matchesTarget`), as the plan's table of affected tests says.

**Shared files.** `LedgerKit/Package.swift`: `resources: [.process("Resources")]` on `FeatureToday` (deviation 13).
`scripts/coverage-thresholds.json`: `"FeatureToday"` joins `required`.

**Tests (`FeatureTodayTests`).** `TodayPresentationTests` in eight files (the suite, `+UpNext`, `+Live`, `+Logged`,
`+RestDay`, `+WeekStrip`, `+Stats`, `+Recent`), `TodayPresentationPropertyTests`, `TodayCopyTests`,
`FeatureTodaySourceTests`, and `Support/TodayTesting.swift` (the tags, the seeded generator, `TodayFixtures`, and
small views of a model for short failure messages).

### Decisions and deviations

1. **A live workout comes before "no program" and "block complete".** The task lists the table's rows as "no
   program / block complete / live workout / …"; the specification's criterion 4 says the live workout takes the
   card "whichever day it was started for". The reason is under the table. With the task's order, the two
   corners (`live_blockCompleteOrNoProgram_takesOverTheCard`) would show the other card, and the change is two
   lines of `card(_:_:)`.
2. **Only `TodayRoute` is public.** The plan's shape names it alone as public. `TodayInput`, `TodayModel`,
   `TodayPresentation` and `TodayCopy` are internal, as S1 left `AppTab` and `AppRouter` internal: `LedgerAppKit`
   sees `TodayRoot` and the route.
3. **Every extension is written `nonisolated extension`.** `FeatureToday` is main-actor isolated by default
   (`Package.swift:13`), and an extension of a `nonisolated` type takes the module's default again, with the
   types nested in it: without the keyword the build fails ("call to main actor-isolated static method … in a
   synchronous nonisolated context"; first host build). S4 and S5 will meet the same.
4. **The brief's keys that hold two counts, or a fragment the screen draws apart, are split** (standards §7: a
   counted key holds one `%lld`; fragments are joined with " · "; M1 convention 1). The table under "The catalog's
   keys" lists each. The join is one constant, `TodayPresentation.separator`: a copy file holds lookups only, and a
   literal without a letter is no lookup.
5. **The tiles' value and unit are apart**, because `StatTile` takes them apart (`StatTile.swift:24`; the gallery's
   `value: "3", unit: "/4"` and `value: "41.2", unit: "k"`, `:120-121`). So the brief's `%lld/%lld` is the number
   done and the key `/%lld`, and `%@k` is `Volume.thousands(in:)` and the key `k`. The caption is `lb moved` and
   the change is the tile's `delta`: the component writes the " · " between them.
6. **A number that is a key's second number is formatted with the injected locale**
   (`Int.formatted(.number.locale(_:))`, in `Context.number(_:)`) and passed as text, as §7 says: the sets done,
   the sessions done. The sessions tile's value is the same text.
7. **The rest card and the "Next:" line follow `nextScheduledDay`, not the week's number** (the orchestrator's
   brief). When it returns nil the Logged card has no "Next:" line and the rest card reads "This is the last week
   of the block.", also in an earlier week whose later weeks are all empty; the brief has no other sentence
   (open question 3). "Later this week" is the card's program week, the one the same sentence names ("in week
   1"), so a block that began midweek reads "Next up is Friday" until its own week ends.
8. **A day before the block speaks of the block's first week.** The specification says only that it is a rest
   day whose next session is the block's first. The card's week is `max(0, weekIndex)`: the body reads "Nothing
   scheduled for Sunday in week 1. Next up is Monday.", "Edit this week" carries `weekIndex: 0`, and the
   off-schedule list is week 1's. So the sentence has no "next" however far the start is (open question 2).
9. **The off-schedule list is every day of the program**, in the program's order, not only the days the card's
   week schedules: the body's criterion 5 lists "all four days" on a week whose Saturday is cleared, and decision
   #18's picker is for training a day the calendar does not offer. "{n} exercises" counts the slots whose exercise
   is stored, which is the number of rows that day's card would show. "Logged" is a finished workout of that
   program, week and day among the week's, whichever day it was done.
10. **The header's title follows the calendar, also while a workout is live.** Criterion 1 defines the title by
    the day; criterion 4 gives the live workout the card. On a rest day with a workout running the title is "Rest
    day" and the card is the workout.
11. **The live card keeps the Up-next card's shape.** Eyebrow "UP NEXT" (the brief has no other; open question
    4); the meta line of the session the workout was built for, when that is a week and a day of the active
    program, else none (`meta` is optional for this reason alone); the workout's own name and its own exercises
    with their targets, so a swapped exercise shows as swapped. `isHeld` is false on its rows: a workout does not
    record it.
12. **A change that rounds to zero reads "0%".** The brief gives "+8%" and "−3%"; S2's notes left zero to S3. A
    sign on zero would be wrong half the time (−0.4 % rounds to 0), and hiding it would read as "nothing to
    compare with" (open question 5).
13. **`Package.swift` gains a six-line target, not one line.** On one line it is 129 columns, over the
    formatter's 120. `LedgerAppKit`'s target is written the same way.
14. **A recent workout's minutes are rounded down** (`57:59` reads "57 min"), as `ClockText.elapsed` rounds
    seconds down, so the same workout never reads longer here than on its receipt. The brief does not say
    (open question 6).
15. **The session's finished workout joins the recent list too**, placed by its start, not only the week's
    workouts: otherwise the Logged card would name a session the list below it lacks for one update.
16. **The model holds the static texts as well** (eyebrows, button titles, "Cancel"), so that a view draws and
    looks nothing up. `PreviewRow` carries `isHeld` and `isDeload` for F24, as the plan asks; nothing draws them
    yet.
17. **Outside the years 1 to 9999 the strip has fewer than seven days.** A day there has no `CivilDate`, so it
    has no cell; `make` still returns a model for any `Date`, the infinities and NaN included
    (`make_momentOutsideTheCalendar_doesNotTrap`). No device clock is there.
18. **The plan's two catalog tests are not written** (`TodayCopyTests.catalog_holdsEveryKey`,
    `catalog_pluralRules`): since S1's fix round the gate's step and `ModuleCopyTests` do both for every module.
    `TodayCopyTests` holds the wording, and each counted text with one and with several.
19. **Not guarded: a week index no stored program can hold.** `Program` validates its weeks as 0 to n − 1, on
    `init` and on decoding, so what the store hands in is sound. A program edited in memory to hold a week whose
    index is near `Int.max`, with a live workout whose source names it, would overflow "week + 1" (and
    `ProgressionRules.prescribe` would count that many weeks first). Programs with a week missing, a day missing
    or a slot id twice are handled and tested.
20. **The catalog was written by a scratch script, not typed** (not committed): it reads each lookup's key and
    comment from the two copy files, takes the six singular forms from a table, and writes the file in the
    tool's layout with the keys in UTF-8 order. The gate's step is what proves it: the keys are the compiler's,
    and `xcstringstool sync` would write the same bytes.

### Criteria → tests

Suite `TodayPresentationTests` unless another is named. The worked examples use `Fixtures.seedProgram()` re-dated
to Monday 2026-09-14 (`TodayFixtures.program()`), the catalog's exercises, and `Fixtures.now` (Wednesday
2026-09-16 05:20 UTC); loads are also checked against `ProgressionRules` and minutes against `TimeEstimate`.

| S3 criterion | Tests |
|---|---|
| 1. Header | `header_weekOneWednesday_readsTheDateAndLowerA` ("Wednesday, September 16", "Lower A", the gear), `header_otherLocaleAndZone_formatsWithThem` (de_DE; Los Angeles, where the same instant is Tuesday and a rest day), `card_byTheCalendar_followsTheDecisionTable` (six moments: the title beside the card), `noProgram_cardAndTitle`, `blockComplete_whenWeekIndexPastTheBlock` ("Today") |
| 2. Week strip | `weekStrip_weekOneWednesday_isMondayToSunday` (body criterion 1: M14 to S20, the marks, the seven spoken dates), `weekStrip_marksDoneTodayPlannedAndRest`, `weekStrip_todayDone_saysTodayInItsLabel`, `weekStartSunday_stripRunsSundayToSaturday` (body criterion 11), `weekStrip_everyWeekStart_beginsOnItAndHoldsToday` (seven week starts), `misalignedWeekStart_stripLooksUpEachDate` (a block begun on Wednesday: one strip, two program weeks), `weekStrip_dayOf23Or25Hours_isOneDay` (Santiago, Cairo, Havana, Kiritimati, Pago Pago; every day of the week at 01:30, 12:30 and 23:30), `weekStrip_workoutAroundASkippedMidnight_marksItsStartDay`, `noProgram_stripHasNoPlannedMarks` |
| 3. Up next | `upNext_weekOneWednesday_isLowerAWithFourRows` (body criterion 1: "Week 1 of 8 · ~38 min", four rows, `.startWorkout(program, 0, Lower A)`), `upNext_everyWeek_rowsAreTheWeeksPrescriptions` (weeks 1 to 8), `upNext_minutes_areTimeEstimateMinutes`, `upNext_deloadWeek_metaAndLoads` (body criterion 6: "Week 8 of 8 · Deload · ~28 min", the squat at 240), `upNext_kilograms_loadsAreInKilograms`, `upNext_missedLastWeek_rowIsHeld` |
| 4. A live workout | `live_todaysSession_showsResumeWithItsStart` (body criterion 3: "Resume · 3:00", `.resumeWorkout`, the start), `live_elapsed_isClockText`, `live_otherDay_takesOverTheCard`, `live_onARestDay_takesOverTheCard`, `live_startedYesterday_takesOverTheCard`, `live_blockCompleteOrNoProgram_takesOverTheCard`, `live_notASessionOfTheProgram_hasNoMeta`, `live_swappedExercise_showsTheWorkoutsRows`, `live_anyDayOfTheBlock_neverOffersStart` (63 days around the block), `live_discarded_offersTheSessionAgain` |
| 5. Logged | `logged_todaysSessionFinishedToday_showsItsNumbers` (body criterion 4: "LOGGED · WEEK 1", "24:22", "15 of 15 sets · 30,370 lb moved", `.openWorkout`, "Next: Friday · UB"), `logged_partlyDoneInKilograms_readsDoneOfTotalAndKilograms`, `logged_nextLine_laterThisWeekNextWeekOrNone`, `logged_emptyWeeksAhead_followTheNextSessionNotTheWeekNumber`, `logged_nextDayNotInTheProgram_hasNoNextLine`, `live_finishes_flipsToLoggedInOneUpdate` (the session's own workout, then history's: counted once), `logged_doneEarlierThisWeek_isOfferedAgain` (Pete's decision 2), `logged_otherSource_isNotTodaysSession` (another day, week or program, no source, not finished), `logged_twiceToday_showsTheNewest` |
| 6. Rest day | `restDay_nextUp_nextWeek` (body criterion 5), `restDay_nextUp_laterThisWeek`, `restDay_lastWeekOfBlock`, `restDay_noSessionLeft_followsTheNextSessionNotTheWeekNumber`, `restDay_beforeBlockStart_speaksOfTheFirstWeek`, `offSchedule_listsEveryDayOfTheProgram` (four days, "5 exercises · ~39 min" …, a `.startWorkout` each), `offSchedule_deloadWeek_estimatesAreTheWeeks`, `offSchedule_dayDoneThisWeek_readsLogged`, `offSchedule_exerciseCount_isTheRowsCount`, `offSchedule_weekMissing_listsNoDays` |
| 7. Block complete, no program | `blockComplete_whenWeekIndexPastTheBlock` (body criterion 7: the card, `.openProgram`, and the strip, tiles and list still filled), `noProgram_cardAndTitle`, `noProgram_stripHasNoPlannedMarks`, `noProgram_tilesReadZero` (body criterion 8: "0" "/0", "0" "k"), `make_emptyInput_isTheEmptyToday` |
| 8. Tiles | `stats_twoOfFourSessions_readTheBriefsExample` (body criterion 9: "2" "/4", "24.2" "k" "lb moved" "+8%", both spoken texts), `stats_delta_positiveNegativeHidden` ("−3%" with U+2212; no previous week; a zero one), `stats_delta_withinHalfAPercent_readsZero`, `stats_delta_beyondInt_isClamped`, `stats_kilograms_convert`, `zeroVolume_readsZeroK`, `stats_offScheduleSessions_canReadFiveOfFour`, `stats_twoSessionsOnOneDay_countTwice`, `stats_oneSessionPlanned_isSingular`, `weekStartSunday_tilesCountSundayToSaturday` (body criterion 11), `stats_workoutOutsideTheStrip_isNotCounted`, `stats_volume_isSummedExactly` |
| 9. Recent | `recent_fiveNewestFirst_todayLabel` (body criterion 10: seven workouts, five rows, "Today · 24:22 · 8,120 lb", "Mon · 58 min · 24,180 lb", an `.openWorkout` each), `recent_none_showsTheEmptyCopy`, `recent_minutes_areRoundedDown`, `recent_kilograms_convert`, `recent_todayLabel_followsTheZone`, `recent_olderThanAWeek_readsItsWeekday`, `recent_finishedSession_joinsTheListByItsStart` |
| 10. Copy | `TodayCopyTests`: `plainTexts_areTheBriefs`, `textsWithValues_areTheBriefs`, `unitTexts_readPoundsAndKilograms`, `change_readsSignNumberAndPercent`, `countedTexts_haveOneAndSeveral`, `countedTexts_formFollowsTheCountedNumber`, `numbers_followTheGivenLocale`, `catalog_neverNamesTheProduct`. That the catalog and the code agree, and that no copy stands outside the copy files: the gate's string-catalog step and `ModuleCopyTests` (runs below) |
| 11. Purity | `FeatureTodaySourceTests`: `sources_neverReadTheClockOrTheCurrentCalendar` (seventeen spellings, in every file of the module), `presentation_neverNamesDouble` (the presentation, the copy and the model name neither `Double`, `Float`, `CGFloat` nor `TimeInterval`), `check_findsASpellingInCodeOnly`; `make_sameInput_givesTheSameModel`. Coverage below |
| 12. What the body leaves open | `upNext_missingExercise_rowIsOmitted`, `restDay_emptyWeekBetween_stillSaysNextWeekday`, `stats_offScheduleSessions_canReadFiveOfFour`, `logged_lateNightWorkout_belongsToItsStartDay` (decision #26: the card, the strip and the recent row) |
| Every row of the decision table | row 1: the `live_*` tests; rows 2, 3, 5, 6 and "before the block": `card_byTheCalendar_followsTheDecisionTable`; row 4: the `logged_*` tests; an edited program: `card_programEditedAfterValidation_isARestDay`, `upNext_slotIDTwice_doesNotTrap`; any `Date`: `make_momentOutsideTheCalendar_doesNotTrap` |
| The invariants, seeded | `TodayPresentationPropertyTests.make_randomInput_keepsTheInvariants`: 200 seeds of four inputs (ten zones, every week start, pounds and kilograms, a block begun on any day of 2026 with weeks emptied, a moment from two weeks before it to two weeks after, up to eight finished workouts, a session absent, live, finished or discarded). Against a reference written with Foundation's calendar alone: the card is the decision table's and resumes exactly when a workout is live; seven strip days from the week start, each spoken as its own date, today among them; the sessions tile, the done marks and the volume are those of the workouts that started in the seven days; every start or edit route names the active program and one of its weeks; at most five recent rows, and the empty copy exactly when there is none |

### The catalog's keys

`F09-today.md:48` is the body's "Copy (exact)" paragraph (one line of the file); `:73` is its Non-functional
line. "Split" means the brief's key is cut where standards §7 requires it.

| Key | From the brief | Note |
|---|---|---|
| `Today` | `:48` ("Today" for today), `:178-180` (the title with no program or a complete block) | one key for both |
| `Rest day`, `Settings` | `:48` | |
| `Today, %@` | not in the brief | written: see below |
| `UP NEXT`, `Start workout`, `Resume · %@`, `%lld × %lld @ %@` | `:48` | |
| `Week %lld of %lld`, `Deload`, `~%lld min` | `:48`, "Week %lld of %lld · ~%lld min" and its deload form | split; `~%lld min` is counted |
| `LOGGED · WEEK %lld`, `View session`, `Next: %@ · %@`, `Next: week %lld` | `:48` | |
| `%@ of %lld sets`, `%@ lb moved`, `%@ kg moved` | `:48`, "%lld of %lld sets · %@ lb moved" ("kg moved" for kg) | split; counted on the total, the sets done as text |
| `SCHEDULED REST`, `No session today`, `Edit this week`, `Train off-schedule` | `:48` | |
| `Nothing scheduled for %@ in week %lld. Next up is %@.`, `… Next up is next %@.`, `… This is the last week of the block.` | `:48` | |
| `Pick a day from week %lld.`, `Logged`, `Cancel` | `:48` | |
| `%lld exercises` | `:48`, "%lld exercises · ~%lld min" | split; counted; its second half is `~%lld min` |
| `No program yet`, `Set up a program to see your next session here.`, `Set up program` | `:48` | |
| `Block complete`, `%lld weeks done. Start the next block from Program.`, `Open Program` | `:48` | the sentence is counted |
| `/%lld`, `sessions this week` | `:48`, "%lld/%lld" + "sessions this week" | split (deviation 5) |
| `%@ of %lld sessions this week` | `:73`, "2 of 4 sessions this week" | counted on the sessions planned |
| `k`, `lb moved`, `kg moved` | `:48`, "%@k" + "lb moved · %@" or "lb moved" ("kg moved") | split (deviation 5) |
| `+%lld%%`, `−%lld%%` | `:48`, delta "+8%" / "−3%" | the minus is U+2212 |
| `%lld%%` | not in the brief | written: "0%" |
| `RECENT`, `No sessions yet. Your first workout lands here.` | `:48` | |
| `%lld min`, `%@ lb`, `%@ kg` | `:48`, "%@ · %lld min · %@ lb" | split; `%lld min` is counted; kilograms by analogy |

**Texts the brief did not give, which I wrote.**
- `Today, %@`, the spoken label of today's cell once it is trained ("Today, Wednesday, September 16").
  Orchestrator decision 11 says the feature's summary "says "Today" when today's mark is done" and gives no
  wording. Untrained, the cell's label is the date alone and the component's own value says "Today".
- `%lld%%`, "0%" for a change within half a percent (deviation 12).
- The singular forms the catalog rule requires: "%@ of %lld set", "%lld exercise", "%lld week done. Start the next
  block from Program.", "%@ of %lld session this week". "~%lld min" and "%lld min" read the same in both forms.
- The volume tile's spoken text has no key of its own: it is `%@ lb moved` with the whole number, then ", " and
  the change ("24,180 lb moved, +8%"). The brief gives a spoken text for the sessions tile only.
- The kilogram forms `%@ kg` and `%@ kg moved`, by analogy with the brief's "kg moved".
- The translators' comments.

### Code lines (added lines of `git diff -U0 4abfb8f`, new files whole, blank and whole-line comment lines excluded)

| Path | Added | Removed |
|---|--:|--:|
| `FeatureToday/TodayPresentation+Card.swift` (new) | 195 | 0 |
| `FeatureToday/TodayPresentation.swift` (new) | 140 | 0 |
| `FeatureToday/TodayCopy+Cards.swift` (new) | 117 | 0 |
| `FeatureToday/TodayModel.swift` (new) | 104 | 0 |
| `FeatureToday/TodayCopy.swift` (new) | 79 | 0 |
| `FeatureToday/TodayPresentation+Stats.swift` (new) | 50 | 0 |
| `FeatureToday/TodayPresentation+OffSchedule.swift` (new) | 36 | 0 |
| `FeatureToday/TodayPresentation+Recent.swift` (new) | 34 | 0 |
| `FeatureToday/TodayPresentation+WeekStrip.swift` (new) | 29 | 0 |
| `FeatureToday/TodayInput.swift` (new) | 14 | 0 |
| `FeatureToday/TodayRoute.swift` (new) | 10 | 0 |
| `FeatureToday/FeatureToday.swift` (deleted) | 0 | 3 |
| `LedgerKit/Package.swift` | 6 | 1 |
| `scripts/coverage-thresholds.json` | 1 | 1 |
| **Product** | **815** | **5** |
| Tests (`TodayPresentationTests` in eight files 1,280, `TodayPresentationPropertyTests` 212, `Support/TodayTesting` 210, `TodayCopyTests` 118, `FeatureTodaySourceTests` 45; the placeholder's test, 9 lines, deleted) | 1,865 | 9 |

Not counted: the catalog (592 lines of JSON) and this section.

**The slice is 815 product lines, over the task's stop line of about 750** (planned: about 570). I counted only
when the tree was built and tested, so this is reported at the end and not at the line; nothing was compressed
to come under it. Where the plan's estimate fell short: the copy file is 196 lines (49 lookups of three to eight
lines each; the plan counted the catalog out and the lookups too) and the model's declarations are 104. The
logic, `TodayPresentation*`, is 484 lines.

**The plan's split ("strip, stats, recent" / "cards"), as it would cut this tree.** Not done; the orchestrator
decides (open question 1).
- **First PR, the frame, about 408 lines**: `TodayRoute`, `TodayInput`, `TodayModel` without `card` and the card
  types, `TodayPresentation.swift` (`make` without the card; the header; `Context`; `Day`, which the header's
  title needs), `+WeekStrip`, `+Stats`, `+Recent`, `TodayCopy.swift` (20 keys), `Package.swift`, the thresholds.
- **Second PR, the cards, about 407 lines**: `TodayModel`'s `card`, `Card` and the card types (its "The cards"
  extension), `+Card`, `+OffSchedule`, `TodayCopy+Cards.swift` (29 keys), and one line of `make`.
- The plan's objection ("a half model would need stubs") does not hold as the code fell out: the day's
  resolution goes with the header, and the first model simply has no card. `Session.source`, which only the
  cards read, would move to the second PR.
- The tests cut less cleanly. `+WeekStrip`, `+Stats`, `+Recent`, the source tests and the support file are the
  first PR's; `+UpNext`, `+Live`, `+Logged` and `+RestDay` the second's. About a dozen tests assert on both
  sides of the seam and would be cut in two or wait for the second PR (`card_byTheCalendar_…`,
  `blockComplete_…`, `live_finishes_…`, `logged_doneEarlierThisWeek_…`, `logged_lateNightWorkout_…`,
  `misalignedWeekStart_…`, the seeded suite's card check), and `TodayCopyTests` splits by copy file.
- Not verified: the first half was never built or tested by itself.

### Runs (final tree; no product file changed after the first of them)

| Run | Command | Result |
|---|---|---|
| Host, the slice's tests | `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter 'FeatureTodayTests\|ModuleCopyTests'` | exit 0. `FeatureTodayTests`: 89 tests in 4 suites passed (parameterised: 200 seeds, 8 weeks, 7 week starts, 6 moments twice, 5 zone weeks). `ModuleCopyTests`: 6 tests passed, with `FeatureToday` among the 10 audited modules and one of the 2 whose built bundle resolves every key |
| Host, static | `scripts/check.sh --lint-only` | exit 0, `check.sh (--lint-only) OK`, 72 s (format, lint `--strict`, package graph and pins, every script suite); run again after this section was written |
| Simulator, one locked session | `/usr/bin/python3 <sim-lock> <scratch>/sim-run.sh`: `check.sh`'s step 3 with the same arguments (`build-for-testing`, then `scripts/check-string-catalogs.sh`, then `test-without-building` of the PR plan with `-only-testing:FeatureTodayTests -only-testing:LedgerAppKitTests`), iPhone 17, iOS 27.0 | exit 0; the lock was free; 19 GB free before, 17 GB after. Build: status 0. Catalog step: status 0, "string catalog matches the code: LedgerKit/Sources/FeatureToday/Resources/Localizable.xcstrings (keys: 49)", and LedgerAppKit's (keys: 7); "2 checked, each matches its module's code". Tests: status 0; the result bundle holds 297 tests, 297 passed, none failed, skipped or expected to fail: `FeatureTodayTests` 89, `LedgerAppKitTests` 208. The bundles were read and deleted |

The build log's only warnings are the three S2's notes already list, in other targets' test files
(`PayloadVersionAdversarialTests.swift:29`, `LedgerDesignTests/PreviewTests.swift:90`, a `@Test` expansion); none
names a file of this slice. `git status --short` lists the files under "What landed", these notes, and nothing
else. No build wrote to the catalog: after the runs it is byte for byte the file the copy files generate
(`cmp` against a copy written again from them by the scratch script that wrote it).

**Not run, and so not verified:** the full gate (`scripts/check.sh`: the other iOS test targets, watchOS, the
coverage gate over the whole plan), which is the orchestrator's on the final tree; CI; anything on a device.
`FeatureToday` is not built for watchOS by any scheme, and I did not build it there.

### Coverage of `TodayPresentation*`

From the simulator session's result bundle (`xcrun xccov view --report --json`), where the module's files are
measured under `FeatureTodayTests`; the host run (`--enable-code-coverage`, `llvm-cov report` on the test binary)
gives the same lines and no missed region.

| File | Lines |
|---|--:|
| `TodayPresentation.swift` | 126 / 126 |
| `TodayPresentation+Card.swift` | 241 / 241 |
| `TodayPresentation+OffSchedule.swift` | 43 / 43 |
| `TodayPresentation+WeekStrip.swift` | 40 / 40 |
| `TodayPresentation+Stats.swift` | 55 / 55 |
| `TodayPresentation+Recent.swift` | 30 / 30 |
| **`TodayPresentation*`** | **535 / 535, 100 %** |
| `TodayCopy.swift`, `TodayCopy+Cards.swift`, `TodayModel.swift`, `TodayInput.swift` | 75 / 75, 114 / 114, 5 / 5, 3 / 3 |
| **`FeatureToday`**, as `scripts/coverage-gate.sh` reads that bundle | **732 / 732, 100 %** (threshold 70 %) |

**Mutants.** 65 one-statement changes to the presentation, each run against the final tests on the host by a
scratch script that restores the file and checks its SHA-256 afterwards: the two rules each way, the card's
order, every clamp, every unit, every "+ 1", the marks' precedence, the strip's days, the merge of the session's
workout, the recent list's limit and rounding. 64 failed a test at once. One survived, "the live card takes its
title from the program's day": every fixture's workout carried its day's name. `live_swappedExercise_…` now
renames the workout, and the mutant fails. Set aside: one change that turned out to change nothing (a "Next:"
line withheld in the last week when the next session is in a later week, which cannot be), and one that does not
compile.

### Open questions (each with a recommendation)

0. **One PR of 815 lines, or the plan's split** ("Code lines" above). The task says to stop and propose the
   split above about 750, so this is the orchestrator's to rule before anything is committed. For what it is
   worth from the implementer: 300 of the lines are declarations and lookups with no branch in them, the rest
   is one decision table whose parts are held together by one `Context` and by tests that assert the card, the
   strip and the tiles in the same breath, and standards §10 asks for a split above about 1,000. The split is
   mechanical on the product side and costs a second gate, test and review cycle and the rework of about a
   dozen tests.
1. **Pete's decisions 1 and 2** are built as their defaults. Each other answer is one function
   (`workoutTakingOver(_:)`, `loggedWorkout(for:_:)`) and its tests. Recommend asking before S4's screenshots.
2. **The wording before the block begins** (deviation 8): "Nothing scheduled for Sunday in week 1. Next up is
   Monday." Recommend keeping it; a sentence of its own ("Your block starts Monday.") would be Pete's copy and
   one more key.
3. **"This is the last week of the block." in a week that is not the last** (deviation 7), when every later week
   is empty. Recommend keeping it until F11 can make such a block; then a sentence such as "Nothing else is
   scheduled in this block." would be Pete's.
4. **"UP NEXT" over a workout that is running** (deviation 11). Recommend keeping it for S4's screenshots and
   asking Pete there; another eyebrow is one key and one line.
5. **"0%"** (deviation 12). Recommend keeping it. Hiding a zero change is one line in `change(_:_:)`.
6. **Minutes rounded down** in RECENT (deviation 14). Recommend keeping it, and F13's list doing the same.
7. **RECENT says "Mon" for a workout of any age**: the brief's format has no date. Recommend leaving it; the
   list holds five workouts and History has the dates.
8. **The spoken texts** ("Today, …", "24,180 lb moved, +8%"). Recommend S4's accessibility pass reads them aloud
   once on a device; "+8%" is read "plus eight percent".
9. **"Resume · %@" is looked up here as a `String`**, with the elapsed time at the model's moment. S4's ticking
   label is the copy file's timer form with the same key (standards §7). Recommend S4 keeps this `String` as the
   button's accessibility label, so that VoiceOver does not re-read a label that changes each second.

### Inputs for S4 (what each view is handed)

Views take the model's parts and call nothing in `TodayPresentation` or `TodayCopy`, except the one timer `Text`
S4 adds to the copy file.
- **Header**: `model.header.date`, `.title` (the heading that keeps the identifier `today.title`), and
  `.settings`: its `title` is the gear's label, its `route` what the tap emits.
- **Strip**: `WeekStrip(days: model.weekStrip)`, as it is.
- **Card**: `switch model.card`.
  - `.upNext(card)`: `Eyebrow(card.eyebrow, tint: .accent)`, `card.meta` (optional), `card.title`, `card.rows`
    (`name`, `scheme`; no ids, so draw by offset), and `card.action`: `.start(action)` is a `PrimaryButton` with
    `action.title`; `.resume(action, startedAt:)` is the timer label counting from `startedAt`, with
    `action.title` ("Resume · 3:00") as what a frozen preview and VoiceOver read. Both emit `action.route`;
    `card.action.action` gives the pair without a `switch`.
  - `.logged(card)`: `eyebrow`, `elapsed`, `title`, `stats`, `action`, and `next` (optional).
  - `.restDay(card)`: `eyebrow`, `title`, `body`, `editWeek` (an action) and `offSchedule`: its `title` is the
    second button and the sheet's title, then `subtitle`, `days` (`name`, `detail`, `logged` when not nil, and
    `route` for the row's tap) and `cancel`.
  - `.noProgram(message)` and `.blockComplete(message)`: `title`, `body`, `action`.
- **Tiles**: `StatTile(value:unit:caption:delta:accessibilitySummary:)` from `model.stats.sessions` and
  `.volume`, field for field.
- **Recent**: `model.recent.eyebrow`; `rows` (`name`, `meta`, `route`); `emptyMessage` when it is not nil.
- **Previews and snapshots**: build a model with `TodayPresentation.make(TodayInput(…))` from fixed values.
  `Fixtures.seedProgram()` starts 2026-08-17; re-date it as `FeatureTodayTests/Support/TodayTesting.swift` does.
  `Fixtures.catalogByID()` is internal to `LedgerFakes`; the exercises come from `ExerciseCatalog.seed()`.

### Inputs for S5 (what the store fills in `TodayInput`)

| Field | From |
|---|---|
| `program` | `ProgramRepository.observeActive()` |
| `exercises` | `ExerciseRepository.observeAll()`, keyed by id |
| `settings` | `SettingsRepository.observe()` |
| `weekWorkouts` | one `WorkoutRepository.workouts(in:)` over the stats week joined with the program week: from the earlier lower bound to the later upper bound of `WeekCalendar.week(containing: now)` and `bounds(ofWeek: max(0, weekIndex(for: now)))`. With no program, or after the block, the stats week alone. More than these workouts does no harm: the presentation counts by date and by source |
| `recentWorkouts` | `WorkoutRepository.observeRecent(limit: 5)` |
| `previousWeekVolume` | `StatsQueries.weeklyVolume(in: WeekCalendar.previousCompleteWeek(before: now))`; zero and nil both hide the change |
| `session` | nil in S5; in S6 `WorkoutSessionUpdate.state` as it arrives (live, finished or discarded) |
| `now`, `calendar`, `locale` | `@Dependency(\.date)`, `\.calendar`, `\.locale` |

- The `WeekCalendar` is `WeekCalendar(startDate: program.startDate, weekStart: settings.weekStart, calendar:)`;
  with no program any start date gives the same stats week.
- The model is `Equatable`, so the store can skip a publish that changes nothing. `Loadable<TodayModel>` has no
  `Equatable` (S2's notes).
- "Resume" does not tick in the model: one model serves until an input changes.

### S3 — orchestrator rulings after G1 (2026-10-05)

- **One slice, one PR.** 815 product lines is over the 500 target and under the ~1,000 line at which standards §10
  asks for a split; the code is one pure function and its words. The split the implementer laid out stays a
  description of the files; the PR body declares the overage. (The stop at about 750 was the orchestrator's
  caution.)
- **A live workout comes before "no program" and "block complete"** (the decision table's first row): accepted, for
  the reason given: Today must always be a way back to a running workout.
- The other deviations (only `TodayRoute` public; the brief's keys split as standards §7 asks; rest and "Next:" copy
  following `nextScheduledDay`; a day before the block speaking of week 1; every program day in the off-schedule
  list; minutes rounded down; six lines in `Package.swift`; the two planned catalog tests not written; the texts
  the brief did not give) go to the reviewer and the tester to judge. The invented texts are listed in the PR for
  Pete.
- The orchestrator's full gate on the tree exited 0 before this entry was written.

## Slice S3 — fix round 1 (G1 implementer, 2026-10-05)

On `feat/F09-s3-presentation` at `1d1b550` (the tester's files, the findings and the review). No commits. The
specification is the brief's "Plan amendments — slice S3 after round 1" (criteria 13 to 18). Product code and my
own tests only: `git status --short` lists no file under `FeatureTodayTests/Adversarial/`.

### What changed, by finding

- **Criterion 13 (F9-S3-1, n1, F9-S3-7): the order of `weekWorkouts` is not assumed.** `Context.init` orders the
  week's finished workouts once, after the session's own workout is merged in: `newestFirst(_:)`
  (`TodayPresentation.swift`) is the repository's order, newest start first and of two that started together the
  smaller id first. So `loggedWorkout`'s "the first that matches" is the one that started last, and of two that
  started at the same instant the same one every time. The order is total: a start that is not a number sorts
  after every moment, so a list that holds one still comes out the same from any order.
  `TodayInput.weekWorkouts` says that any order is accepted. `recentWorkouts` is still "newest first" by
  contract and is shown as handed in (the tester's `sameStart_listsBoth` pins that).
  Tests: `logged_twiceToday_showsTheNewest` now takes both orders;
  `logged_twoAtTheSameInstant_showTheSameOneInAnyOrder`; `make_weekWorkoutsInAnyOrder_giveTheSameModel` (six
  workouts, two that tie, two whose start is not a number, 40 shuffles); the seeded suite hands the workouts
  shuffled, gives one in four the start and the session of the one before it, checks that a Logged card shows
  one of today's that started last, and that the reversed list gives an equal model.
- **Criterion 14 (F9-S3-2, R1): the volume tile's spoken line is copy.** `TodayCopy.movedThisWeek(_:units:locale:)`
  and `movedThisWeek(_:change:units:locale:)`, a key per unit each. The `", "` in `TodayPresentation+Stats.swift`
  is gone; the one literal left outside the copy files is `separator`, " · ".
- **Criteria 15 to 17 (F9-S3-3 to -5, R4, n2, n7): one value for the next session.** `NextSession`
  (`TodayPresentation+Card.swift`): the scheduled day, its weekday's name, and whether its date is one of the
  strip's seven days; `nextSession(_:_:)` gives it, or nil when the block has none left. Both readers use it:
  - `restBody(_:_:)`: before the block, "Your block starts on {date}." and nothing else (16); from then on the
    day and its program week, then "Next up is {weekday}." when the session is on the strip and "Next up is next
    {weekday}." when it is not, whichever program week it is in (15); with none left, "This is the last week of
    the block." in the last week and "No sessions are left in this block." in any earlier one (17).
  - `nextLine(_:_:)`: unchanged in what it says; it still compares the program week, so "Next: week n" never
    names the week the lifter is in (15).
  Tests: `restDay_nextWord_followsTheStripNotTheProgramWeek` (a Sunday and a Monday week start, both ways round),
  `restDay_blockBegunMidweek_tomorrowIsNotNext` (the tester's 11-03 case),
  `logged_nextLine_followsTheProgramWeekNotTheStrip`, `restDay_beforeBlockStart_saysWhenTheBlockStarts`,
  `restDay_beforeABlockThatOpensWithARestDay_namesTheBlocksFirstDay`,
  `restDay_noSessionLeftBeforeTheLastWeek_saysNoneAreLeft`. The two tests that pinned the old sentences
  (`restDay_beforeBlockStart_speaksOfTheFirstWeek`, `restDay_noSessionLeft_followsTheNextSessionNotTheWeekNumber`)
  are the last two of these, renamed.
- **R2: the source test.** `FeatureTodaySourceTests.ambient` gains `Date.init()`, `Calendar(identifier:`,
  `.dateTime`, a bare `.formatted()`, `DateFormatter(`, `NumberFormatter(` and `DateComponentsFormatter(` (24
  spellings); `inexact` gains `.doubleValue` and `.floatValue`. The check now reads the code inside string
  interpolations too, and its comment says what it does not read. `check_findsASpellingInCodeAndInInterpolations`
  has the interpolated cases and finds every spelling of both lists in code.
- **R3:** `live_afterTodaysSessionIsLogged_takesOverTheCard`: Lower A finished today, then Lower B live: Resume,
  the title "Lower A", today's mark done, "1" session.
- **n3:** the Logged card keeps the program's day name; the comment at the line says so and why. **n4:** the
  comment on `workoutTakingOver` says the other answer also changes its signature and its one call. **n5:** every
  key with two or more values has a translator's comment naming them in order, in the code and the catalog
  together (below). **n6:** the seeded check compares the "/N" unit with the reference's count of planned days
  for every input, and holds every planned mark to a planned day and no planned day to a rest mark.
- **Not changed: F9-S3-6** (criterion 18).

### New and changed keys (for Pete)

The catalog has 55 keys (49 before).

| Key | Reads | Where |
|---|---|---|
| `%@ lb moved this week, %@ from last week` (new) | "24,180 lb moved this week, +8% from last week" | VoiceOver, the volume tile, when there is a change to draw |
| `%@ kg moved this week, %@ from last week` (new) | "10,968 kg moved this week, +8% from last week" | the same, in kilograms |
| `%@ lb moved this week` (new) | "24,180 lb moved this week" | VoiceOver, the volume tile, with no previous week |
| `%@ kg moved this week` (new) | "10,968 kg moved this week" | the same, in kilograms |
| `Your block starts on %@.` (new) | "Your block starts on Monday, September 28." | the rest-day card's whole body on a day before the block begins |
| `Nothing scheduled for %@ in week %lld. No sessions are left in this block.` (new) | "Nothing scheduled for Sunday in week 2. No sessions are left in this block." | the rest-day card, no session left, in a week before the last |

Used differently, text unchanged:
- `… Next up is %@.` and `… Next up is next %@.`: the word "next" now follows the strip's seven days.
- `… This is the last week of the block.`: only in the block's last week.
- `%@ lb moved`, `%@ kg moved`: the Logged card only; the tile no longer speaks them.

With a change that is a fall or nothing, the spoken line reads "21,728 lb moved this week, −3% from last week"
and "22,400 lb moved this week, 0% from last week": the change is the text the tile draws.

Translators' comments, new or reworded (no text changes): `Week %lld of %lld`, `%lld × %lld @ %@`,
`%@ of %lld sets`, `Next: %@ · %@`, the four `Nothing scheduled for …` bodies, `%@ of %lld sessions this week`,
and the six new keys.

### Code lines

Product, counted as before (blank and whole-line comment lines excluded): **917** (815 before), in `FeatureToday`
910 and the two shared files 7.

| File | Now | Before |
|---|--:|--:|
| `TodayCopy+Cards.swift` | 151 | 117 |
| `TodayCopy.swift` | 115 | 79 |
| `TodayPresentation+Card.swift` | 214 | 195 |
| `TodayPresentation.swift` | 151 | 140 |
| `TodayPresentation+Stats.swift` | 52 | 50 |
| the other six files | 227 | 227 |

70 of the 102 new lines are the copy files': six lookups, and the comments of n5, each of which turns a one-line
lookup into six. The logic grew by 32. My tests are 2,135 lines in fourteen files (1,865 in twelve): the seeded
suite's reference is its own file now, and the order tests have one.

### Runs (final tree; no source changed after the first of them)

| Run | Result |
|---|---|
| Host: `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter 'FeatureTodayTests\|ModuleCopyTests'` | exit 1. `FeatureTodayTests`: 193 tests in 16 suites, **187 pass, 6 fail** (15 issues), each a tester's pin listed below. My 97 pass (89 before), the tester's 96: 90 pass. `ModuleCopyTests`: 6 pass; `FeatureToday` is audited and its built bundle resolves the 55 keys |
| Host, my suites alone, with coverage (`--filter 'FeatureTodayTests\.(TodayPresentation(Property)?Tests\|TodayCopyTests\|FeatureTodaySourceTests)'`) | exit 0, 97 tests in 4 suites |
| `scripts/check.sh --lint-only` | exit 0, `check.sh (--lint-only) OK`, 78 s |
| Simulator, one locked session, as in the first round (`build-for-testing`, `scripts/check-string-catalogs.sh`, `test-without-building -only-testing:FeatureTodayTests -only-testing:LedgerAppKitTests`; iPhone 17, iOS 27.0) | lock free; 13 GB free before and after. Build: status 0. Catalog step: status 0, "string catalog matches the code: LedgerKit/Sources/FeatureToday/Resources/Localizable.xcstrings (keys: 55)", LedgerAppKit's (keys: 7), "2 checked, each matches its module's code". Tests: `xcodebuild` status 65; the bundle holds 401 tests, **395 passed, 6 failed**: `FeatureTodayTests` 193 with the same six failing, `LedgerAppKitTests` 208, all passing. The bundles were read and deleted |

**Coverage of `TodayPresentation*`**, from the simulator's bundle and the same on the host from my suites alone
(no missed region there): `TodayPresentation.swift` 148 / 148, `+Card` 264 / 264, `+OffSchedule` 43 / 43,
`+WeekStrip` 40 / 40, `+Stats` 58 / 58, `+Recent` 30 / 30: **583 / 583**. The module: 850 / 850.

**Mutants of the new code**, 20, each against my own suites on the host (the files restored and their SHA-256
checked): no ordering, oldest first, ties by the larger id, ties left to the input, an order that is not total,
the oldest logged, "next" by the program week again, always on the strip, the "Next:" line by the strip, no
sentence before the block, the wrong date in it, the three ways to get the last week wrong, the spoken line
without its change, in thousands and in the wrong unit, the week off by one, today's weekday for the next. 19
failed a test at once. One survived, the order that is not total: the fixture's ids rose with its starts. The
fixture now sets ids against starts, and the mutant fails.

**Not verified.** The full gate (the other targets, watchOS, the coverage gate over the whole plan): not run, as
told; expect it red at its iOS test step on the six tests below until the tester updates them. CI. Nothing on a
device. How VoiceOver speaks the new line.

### The tester's tests that need the tester

Six tests fail, on the host and on the simulator alike, and no other. Each pins a text or a count that a ruling
changes. I did not edit them.

| Test (`FeatureTodayTests/Adversarial/`) | Ruling | It expects | It now gets |
|---|---|---|---|
| `TodayWeeksAdversarialTests.blockBegunOnWednesday_usesEachDaysOwnWeek(_:)`, the row of 2026-11-03 (`TodayWeeksAdversarialTests.swift:102-110`); its other five rows pass | 15 | "Nothing scheduled for Tuesday in week 7. Next up is next Wednesday." | "Nothing scheduled for Tuesday in week 7. Next up is Wednesday." |
| `TodayTilesAdversarialTests.straddlingWeek_keepsTheTwoWeeksApart()` (`+Logged.swift:79`); its other expectations pass | 15 | "Nothing scheduled for Tuesday in week 1. Next up is next Wednesday." | "Nothing scheduled for Tuesday in week 1. Next up is Wednesday." |
| `TodayWeeksAdversarialTests.beforeTheBlock_isARestDayOfWeekOne(_:)`, both arguments (`+Edited.swift:94-95`); the route, the sheet, the marks and the unit still pass | 16 | a body that begins "Nothing scheduled for Wednesday in week 1. Next up is " and ends " Friday." or " Monday.", with or without "next" | "Your block starts on Friday, September 18." (2 days before) and "Your block starts on Monday, September 28." (12 days before) |
| `TodayWeeksAdversarialTests.nothingLeftBeforeTheLastWeek_saysSo()` (`+Edited.swift:63-79`) | 17 | "Nothing scheduled for Sunday in week 1. This is the last week of the block." | "Nothing scheduled for Sunday in week 1. No sessions are left in this block." |
| `TodaySpokenAdversarialTests.volumeTile_speaksTheWholeNumberAndTheChange(_:)`, all seven rows (`:103`, the line ends with the drawn change; `:106`, the line is the whole number alone) | 14 | "24,180 lb moved, +8%"; "10,968 kg moved, +8%"; "21,728 lb moved, −3%"; "22,400 lb moved, 0%"; "24,180 lb moved"; "0 kg moved, −100%"; "0 lb moved" | "24,180 lb moved this week, +8% from last week"; "10,968 kg moved this week, +8% from last week"; "21,728 lb moved this week, −3% from last week"; "22,400 lb moved this week, 0% from last week"; "24,180 lb moved this week"; "0 kg moved this week, −100% from last week"; "0 lb moved this week" |
| `TodayPurityAdversarialTests.lookups_takeTheInjectedLocale()` (`:127`); its two other expectations pass. Not in the orchestrator's list: it counts the lookups | 14, 16, 17 | `calls.count == 49` | 55 lookups: the six new keys |

The three that failed in round 1 pass unedited: `TodayCardAdversarialTests.sessionDoneTwice_showsTheLaterOne(_:)`
(both cases), `TodayCardModelAdversarialTests.seededInputsInAnyOrder_showWhatTheSpecificationGives(_:)` (all
eight batches) and `TodayPurityAdversarialTests.joiner_isTheMiddleDot()`.

### For the next slices

- S5: `weekWorkouts` may be filled in any order, so two reads appended are as good as one read over the union.
- S4: the rest-day body before the block is one sentence with a date in it, longer than the others at large
  text sizes ("Your block starts on Wednesday, September 30.").

## Slice S4 — the views (G1 implementer, 2026-10-08)

Branch `feat/F09-s4-views` at `a00584e` (the specification). No commits. Paths that start with a module name are
under `LedgerKit/Sources/`; test paths are under `LedgerKit/Tests/`. "The specification" is the brief's last
section ("Plan amendments — slice S4, the views"); "the task" is the orchestrator's message that started this
slice. v2 is `design/prototype/Ledger v2.dc.html`.

### The intended VoiceOver trees

Written before the views. One list per state, in reading order, in the form of "The shell's intended VoiceOver
tree": what each stop reads, and its traits. They are read from `TodayPage`, which is what `TodayScreen` scrolls
(testing-strategy §2.6), and from the sheet's parts. Nothing decorative is a stop: the rules, the strip's dots,
the button's arrow, a row's chevron, the gear's symbol. No stop stands in a labelled container.

**What every loaded state has, around its card.** The examples are the brief's criterion 1 (Wednesday
2026-09-16, week 1 of the seed program).

1. **The date**: "Wednesday, September 16", text.
2. **The title**: "Lower A", a heading (`today.title`). It is no button: the Debug long press adds no trait.
3. **The gear**: "Settings", a button.
4. **The strip**: seven stops, one per day, in the strip's order. Each reads the model's spoken date as its
   label ("Monday, September 14") and the component's word for its mark as its value ("Done", "Today",
   "Planned", "Rest day"), as F06 pinned it; text. (Corrected after the first read: I had written "no
   trait"; F06's cell is static text, `AccessibilityTreeSlice3Tables.swift:151-157`.)
5. **The card**: one of the five lists below.
6. **The sessions tile**: one stop, the model's spoken text ("2 of 4 sessions this week"), text.
7. **The volume tile**: one stop, the model's spoken text ("24,180 lb moved this week, +8% from last week"),
   text.
8. **"RECENT"**: a heading.
9. **The recent workouts**: one button per row, reading the name and the meta line ("Lower A — Squat focus,
   Mon · 58 min · 24,180 lb"); or, with none, the empty message as text.

**The cards.** Each card has one heading, its first stop: the eyebrow where it has one (F06's `Eyebrow` is a
heading), the title where it has none. A card's title under an eyebrow is text, so the rotor stops once per
card (the plan's Risks).

- **Up next**: "UP NEXT", a heading; the meta line ("Week 1 of 8 · ~38 min"), text, absent when the model has
  none; the title ("Lower A — Squat focus"), text; one text stop per exercise, the name and the scheme
  ("Back Squat, 5 × 5 @ 250"); "Start workout", a button.
- **A live workout**: as Up next, and the button reads the model's "Resume · 3:00": the label at the model's
  moment, fixed, so VoiceOver does not read it again each second.
- **Logged**: the eyebrow ("LOGGED · WEEK 1"), a heading; the elapsed time ("24:22"), text; the title, text;
  the stats line ("15 of 15 sets · 30,370 lb moved"), text; "View session", a button; the "Next:" line, text,
  absent when the model has none.
- **Rest day**: "SCHEDULED REST", a heading; "No session today", text; the body, text; "Edit this week", a
  button; "Train off-schedule", a button.
- **No program** and **Block complete**: the title ("No program yet"), a heading; the body, text; the action
  ("Set up program"), a button.

**The off-schedule sheet** (from the sheet's title and its page): "Train off-schedule", a heading; "Cancel", a
button; "Pick a day from week 1.", text; one button per day, reading the name, the detail and, on a day done
this week, "Logged" ("Lower B — Hinge focus, 3 exercises · ~29 min, Logged"). VoiceOver's escape gesture from
any of them cancels, as `SheetChrome` gives it.

**Loading**: no stop. **Failed**: "Can't show today right now", a heading; "Your workouts are still on this
iPhone. Open the app again to try once more.", text.

### What landed

**FeatureToday (product), under `FeatureToday/Views/` unless named.** Every view takes its part of the model and
one closure, `send: (TodayAction) -> Void`; none decides which card, formats anything or reads a clock.
- `TodayAction.swift`: what a tap asks for: `.route(TodayRoute)`, `.pickOffScheduleDay`, `.titleLongPress`; and
  the environment value `todayTimerPause` (nil in the app; the moment the resume time stands still at, in
  previews and tests).
- `TodayScreen.swift`: `TodayScreen(state: Loadable<TodayModel>, onRoute:, onTitleLongPress:)`: a `ScrollView`
  around `TodayPage`, on the ground, and the `.sheet` of the off-schedule list. Nothing is pinned.
- `TodayPage.swift`: everything that scrolls. Loaded: `TodayHeader`, `WeekStrip` over a rule, the card,
  `StatsRow`, `RecentList`. Loading and idle: nothing. Failed: F06's `EmptyState` with the two new texts.
- `TodayHeader.swift` (date, title with `today.title`, the gear), `CardEyebrowLine.swift` (an eyebrow with a
  note beside it, shared by two cards), `UpNextCard.swift`, `LoggedCard.swift`, `RestDayCard.swift`,
  `MessageCard.swift` (no program and block complete), `StatsRow.swift`, `RecentList.swift`,
  `OffScheduleSheet.swift` (`SheetChrome` around a `ScrollView`) and `OffSchedulePage.swift` (what it scrolls).
- `Today+Previews.swift`: the registry `TodayPreview`, eleven cases, each a model made by
  `TodayPresentation.make` from a fixed input (`TodayPreviewData`): the eight states, the sheet, and two states
  that carry an open product question.
- `TodayCopy+Cards.swift`: `resume(since:pausedAt:) -> Text`, the timer form of the key `Resume · %@`
  (standards §7, form 2). `TodayCopy.swift`: `failedTitle`, `failedBody`. The catalog: two keys (below).

**LedgerDesign.** `PrimaryButton(label:accessibilityLabel:icon:action:)`, a label that is a `Text`, with the
fixed line VoiceOver reads for it; `IconPillButton(_:systemImage:action:)`, an SF Symbol drawn in the square a
`LedgerIcon` takes. Each has a gallery (`PrimaryButtonTimerGallery`, `IconPillButtonSymbolGallery`) and a
`DesignPreview` case.

**Shared one-line files.** `Package.swift` (`snapshotTestTargets` gains `"FeatureToday"`),
`LedgerTestSupport/Previews/PreviewScan.swift` (`registeredModules` gains `"FeatureToday"`; three lines, since
one would be over 120 columns).

**Tests.** `FeatureTodayTests`: `PreviewTests`, `TodaySnapshotTests`, `TodayAccessibilityTests` with
`TodayAccessibilityTrees`, `TodayScreenTests`, `Support/TodayParts.swift`; `TodayCopyTests` gains the two texts.
`LedgerDesignTests`: `ButtonAdditionsTests` (two suites) and four rows of `AccessibilityTreeTests`' table.

**The two new texts (for Pete).** Decision 5's default wording, added on the orchestrator's ruling of
2026-10-08, the one sanctioned change to the copy in this slice:

| Key | Where |
|---|---|
| `Can't show today right now` | the title in place of the screen when Today's data cannot be read |
| `Your workouts are still on this iPhone. Open the app again to try once more.` | under it |

The catalog has 57 keys (55 before).

### Decisions and deviations

1. **The whole screen scrolls; nothing is pinned.** v2 puts the header inside the scrolling column
   (`Ledger v2.dc.html:68-69`, `overflow:auto` around everything from the date down), and the tab bar is the
   shell's. So "pinned parts plus `ScrollView { TodayPage }`" is the scroll view alone, and the test target's
   `TodayParts` is the page alone. The plan's row calls the page `TodayContent`; it is `TodayPage`, as the
   specification and the convention name it.
2. **`TodayPage` takes the `Loadable`, not a model**, and so holds the one `switch` over the load state; the
   screen holds the scroll view and the sheet, and nothing else. This way all eight states are read and drawn
   from one view that is never a scroll view. With `TodayPage(model:)` the loading and failed states would exist
   only inside the scroll view, where the reader cannot read them. `.idle` draws as `.loading` does.
3. **Loading draws nothing** (the orchestrator's ruling of 2026-10-08): the ground alone, no spinner and no
   word. Its tree is empty and its reference is the screen at an iPhone 17's size.
4. **Failed is F06's `EmptyState` with two new texts**, looked up by `TodayPage` from `TodayCopy` (criterion 1's
   "a `TodayCopy` lookup the model does not carry"): `Loadable.failed` carries an error and no words. The task
   said to change no copy; the orchestrator ruled the two keys in (2026-10-08). The failed state has no header,
   so no `today.title` (Inputs for S5).
5. **One closure, `send: (TodayAction) -> Void`, not one closure per control.** Every view sends
   `.route(model's route)`; the rest-day card's second button sends `.pickOffScheduleDay`, which the screen
   answers by presenting the sheet; the title's Debug long press sends `.titleLongPress`. The plan's
   `onTitleLongPress` (orchestrator decision 17) is built now and not in S5, because the long press sits on
   the element whose traits the tree pins (the plan's Risks): the tree is pinned with the gesture in place.
6. **The sheet is presented with `.sheet(isPresented:)` and its content comes from the model on screen**, not
   from a copy taken when it opened: it always shows the current list, and when the card stops being a rest day
   (a workout began elsewhere, the day rolled over) the screen takes the sheet away. A pick closes the sheet and
   then hands the route on. This is the one piece of state in the views, and it is presentation state.
7. **The frozen time is an environment value, `todayTimerPause`**, as the review's "What S4 must be told" asks
   ("a preview or a snapshot that freezes the timer passes its own `pauseTime`"); the model does not hold its
   moment. Nil, the app's default, counts. Passing it down as a parameter would thread a test's concern through
   three views.
8. **The resume button's VoiceOver label is the model's `action.title`, fixed** ("Resume · 3:00" as it read when
   the model was made), as S3's open question 9 recommends. SwiftUI marks an element that holds a timer `Text`
   as `updatesFrequently` (measured: traits 513 on the first run); `PrimaryButton(label:accessibilityLabel:…)`
   removes that trait, since what VoiceOver reads there does not update. The spoken time is therefore as old as
   the model (open question 3).
9. **`PrimaryButton`'s new initializer is `init(label:accessibilityLabel:icon:action:)`**, with one more
   parameter than the plan's `PrimaryButton(label:icon:action:)`: a `Text` that changes by itself must come
   with the line VoiceOver reads, or every caller would have to remember to add it from outside.
10. **The two `LedgerDesign` additions have galleries of their own** (`PrimaryButtonTimerGallery`,
    `IconPillButtonSymbolGallery`), each a `DesignPreview` case with six references, as `PillButtonStatesGallery`
    was added in F08 S2. They are not added to `PrimaryButtonGallery`, `IconPillButtonGallery` or the Debug
    menu's `DesignGallery`, so **no existing reference changed**. Adding them to `DesignGallery`'s sections
    would re-record its one reference and the twelve of the two galleries.
11. **The SF Symbol is drawn in the square a `LedgerIcon` takes** (`resizable`, `scaledToFit`, the `button`
    role's scaled size), so the gear's button is exactly as big as the swap button at every text size
    (`symbolButton_isAsBigAsAnIconButton`). The gear is a 44 pt circle, where v2's avatar is 40 px: a tap needs
    44 points.
12. **Cards are flat and have no accessibility container**, against the brief's non-functional line "cards are
    grouped containers with a heading". Every F06 tree and onboarding's pin "no container"; a card's heading
    is its first stop, which gives the rotor the same stops. The title under an eyebrow is text, not a second
    heading (the plan's Risks).
13. **The exercise rows and the recent rows are F06's `HairlineRow`**, as its gallery draws these very lines
    (`HairlineList.swift:38-43`), so the card's rows are 15 pt `body` in full ink with 16 pt above and below,
    where v2 has 14 px at 72 % with 13 px (`v2:95-98`). Tokens and components only: the feature holds no literal
    colour, font, radius or spacing but `0`.
14. **"Set up program" and "Open Program" are the orange `PrimaryButton`**: on those two cards it is the
    screen's one main action (spec §8.4). "View session", "Edit this week" and "Train off-schedule" are
    outlined pills, flush with the leading edge. The Logged eyebrow is grey (Pete's decision 3).
15. **The preview registry has eleven cases, not eight**: the eight states, the sheet alone (the rest-day
    state's second half), and the two states the review asked for ("What S4 must be told"): a workout live on a
    rest day, and a Monday with "0" "k" "−100%". The third it asked for, "1/0", is the block-complete case
    itself: after the block no day is planned, so one session reads "1/0".
16. **`Today+Previews.swift` builds its inputs itself** (`TodayPreviewData`, 100 lines): the test target's
    `TodayFixtures` cannot be reached from product code, and `LedgerFakes` has no finished workout dated in
    week 1 of a re-dated program. The tests draw the previews' states, so there is one set of fixtures for
    what is drawn.
17. **Snapshot matrix: the specification's, not the plan's.** Criterion 3 says "at the sizes
    `docs/testing-strategy.md` gives for a screen", which is light and dark at `.large`, `.xLarge` and
    `.accessibility3`; the plan (orchestrator decision 8) had `.large` and `.xLarge` with three AX3 images, 39
    PNG. Recorded: 55 references in `FeatureTodayTests` and 12 in `LedgerDesignTests` (listed below).
18. **Two of the tester's files are edited, one line of logic each**
    (`FeatureTodayTests/Adversarial/TodayPurityAdversarialTests.swift`): the count of lookups, 55 to 57, for the
    two ruled keys; and its two scans for words outside the copy files now leave `*+Previews.swift` unread, as
    standards §7 does for the audit (`ModuleCopyTests`): a preview's name is a literal by the registry's
    convention. Those scans read the module's top folder only, so they do not read `Views/`; the views are
    read by `ModuleCopyTests`' audit and by `FeatureTodaySourceTests`. For the tester to confirm.
19. **`FeatureOnboarding/Views/…`, "the model to copy" (testing-strategy §2.6), is not on `main`** at `a00584e`
    (`LedgerKit/Sources/FeatureOnboarding/` holds the placeholder alone). I read it from the branch
    `feat/F08-s2-onboarding-ui` with `git show`, and followed its split, its `…Parts` view and its tree test.
20. **A tree is never handed to `#expect` whole.** `firstDifference(found:expected:)` gives one short line for
    the first stop that differs, and the test expects that to be nil.
21. **Tokens: what v2 has that the scale lacks.** No token was added. v2's 30 to 34 px gaps are `xxl` (32);
    26 to 30 px above a rule is `xl` (24); 20 px inside a card is `l` (16); 10 px between the date and the
    title is `s` (8); the 25 px card title is `heading` (27). Missing, if exactness is wanted: a 20 pt spacing
    step and a 25 pt title role.

### Dynamic Type

Read from the references at `.accessibility3` (every loaded state, both themes) and `.accessibility5` (the live
workout, dark): nothing is clipped, truncated or overlapping, and the page is as tall as its text needs, since
it scrolls.

- **The header**: the date wraps to two lines beside the gear; the title wraps under it. VoiceOver's order is
  date, title, gear at every size (a sort priority on the two texts: without it the gear was read second at
  `.accessibility3`, found on the first run).
- **The strip** stays seven columns at every size: its letters and dates shrink rather than wrap (F06's
  component, `minimumScaleFactor`); at `.accessibility5` "20" is visibly smaller than "14".
- **A card's first line**: the note ("Week 1 of 8 · ~38 min", "24:22") moves under the eyebrow at accessibility
  sizes (`CardEyebrowLine`), and wraps there.
- **The exercise rows and the recent rows**: the scheme and the chevron move under the name (F06's
  `HairlineRow`); names wrap.
- **The orange button** grows with its label, which wraps to two lines at `.accessibility5` ("Resume ·" over
  "3:00").
- **The rest day's two pills** stand one under the other at accessibility sizes.
- **The tiles** stand one under the other at accessibility sizes (F06's `StatTileRow`); a value shrinks rather
  than breaks.
- **The sheet**: "Cancel" moves under the title (F06's `SheetChrome`), "Logged" under a day's detail.

### The design regions used

`design/prototype/Ledger v2.dc.html`: 66-129, the whole Today screen: the scrolling column and its padding
68, the header 69-75, the strip 77-85, Up next 87-106 (the eyebrow line 88-91, the title 92, the rows 93-100,
the button 101-104), the tiles 108-117, RECENT 119-126, the tab bar 128 (the shell's). `docs/product-spec.md`
§3.10 "Today (v2)" (line 368). v1 was not opened: the states v2 lacks are drawn in v2's type from the brief's
copy (Pete's decision 3), not from v1's cards.

### Criteria → tests

`FeatureTodayTests` unless another target is named. The iOS-only suites run on the simulator.

| S4 criterion | Tests |
|---|---|
| 1. Drawn from the model only | `TodayAccessibilityTests.tree_isExactlyTheTable` (every text read is the model's, in eleven states); `FeatureTodaySourceTests.sources_neverReadTheClockOrTheCurrentCalendar` and the tester's `TodayPurityAdversarialTests.sources_reachForNothingOfTheirOwn` (no clock, calendar or locale in any file, the views included in the first); `ModuleCopyTests` (`LedgerAppKitTests`: no literal and no lookup outside the copy files, `Views/` included); `TodayCopyTests.plainTexts_areTheBriefs` (the two new texts). Not a test: that no view branches on anything but the model's own cases and optionals, which is for review |
| 2. The screen scrolls as the convention says | `TodayScreenTests.screen_isOneScrollView` (eleven states), `loadedPage_atAnAccessibilitySize_scrolls` (taller than the screen at `.accessibility3`, never wider), `sheet_isOneScrollView`; the trees and references are taken from `TodayParts` and `OffScheduleParts`. The nightly UI test is S5's |
| 3. Eight states, previews and snapshots | `PreviewTests.registry_listsEveryPreview`, `preview_renders` (eleven), `preview_showsItsState`; `TodaySnapshotTests`, twelve tests, 55 references |
| 4. Matches the dark design with tokens and components only | The references, read against v2:66-129, and the screenshots; lint's four `ledger_raw_*` rules (`scripts/check.sh --lint-only`); for review (standards §7) |
| 5. The resume time ticks from the model's start and is frozen in tests | `LedgerDesignTests/ButtonAdditionsTests.timerLabel_followsItsPauseTime` (the same moment draws the same picture, a second later another); `TodaySnapshotTests.resume_matchesReferences` (the label reads "Resume · 3:00" for a start three minutes before the frozen moment); `PreviewTests.preview_showsItsState` (the model's start and title). Not verified by a test: that it counts in the app, where `todayTimerPause` is nil (open question 6) |
| 6. Actions; 44 points | `TodayAccessibilityTests`: `upNext_buttons_sendTheirRoutes`, `resume_button_sendsResume`, `logged_buttons_sendTheirRoutes`, `restDay_buttons_sendTheirActions`, `messageCards_buttons_sendTheirRoutes`, `offSchedule_buttons_sendTheirRoutes` (a logged day too; Cancel and the escape gesture), `loadingAndFailed_sendNothing`; `buttons_haveA44PointTarget` (eleven states, two text sizes). Not verified by a test: that `TodayScreen` presents the sheet on `.pickOffScheduleDay`, closes it on a pick, and that the long press sends `.titleLongPress` (open question 5) |
| 7. VoiceOver | `TodayAccessibilityTests.tree_isExactlyTheTable` against `TodayTrees` (eleven tables: stops, order, labels, values, traits), at `.large` light and `.accessibility3` dark |
| 8. The two `LedgerDesign` additions | `LedgerDesignTests`: `ButtonAdditionsTests` (`timerButton_isOneLabelledButton`, `symbolButton_isOneLabelledButton`, `symbolButton_isAsBigAsAnIconButton`, `timerLabel_followsItsPauseTime`), `ButtonAdditionsSnapshotTests` (12 references), four rows of `AccessibilityTreeTests`' table, `PreviewTests` (the two new `DesignPreview` cases render and are registered). No existing reference changed: the 140 of `LedgerDesignTests` compare unchanged |
| 9. Wiring | `LedgerDesignTests/PreviewTests.everyModuleWithPreviews_isRegistered`; the build (`__Snapshots__` excluded from the target); the gate's string-catalog step (57 keys); coverage is the gate's and was not measured here |

### References

**Added, 67. Changed, none. Removed, none.** Recorded on the PR plan's iPhone 17 (iOS 27.0) through the
simulator lock, in swift-snapshot-testing's default mode (a missing reference is written and its test fails;
`git status` shows no existing PNG modified), then compared green in a second and a third run. Not with
`scripts/check.sh --record-snapshots`: that re-records every reference of both plans and is the full gate's
run, which the task reserves for the orchestrator.

- `Tests/FeatureTodayTests/__Snapshots__/TodaySnapshotTests/`, 55 PNG, 3,645,273 bytes:
  - six each (`light`, `dark` × `large`, `xLarge`, `accessibility3`): `upNext_matchesReferences`,
    `resume_matchesReferences`, `logged_matchesReferences`, `restDay_matchesReferences`,
    `offSchedule_matchesReferences`, `noProgram_matchesReferences`, `blockComplete_matchesReferences`,
    `failed_matchesReferences` (48);
  - two each (`light-large`, `dark-large`): `loading_matchesReferences`, `resumeOnRestDay_matchesReferences`,
    `mondayVolume_matchesReferences` (6);
  - `resume_largestTextSize_matchesReference.dark-accessibility5.png` (1).
- `Tests/LedgerDesignTests/__Snapshots__/ButtonAdditionsTests/`, 12 PNG, 73,997 bytes:
  `primaryButtonTimer_appearance_matchesReference-_.*` and `iconPillButtonSymbol_appearance_matchesReference-_.*`,
  six each.

The rest day's two `accessibility3` references were recorded twice: after the first recording I gave the
stacked pills 8 pt between them, deleted those two files and recorded them again.

**Screenshots for Pete**, `tasks/features/F09-today/screenshots/s4/`, 24 PNG, 1.3 MB, copies of the references
at 1×: `01` to `11`, each state dark and light at the default text size (up next, live workout, logged, rest
day, off-schedule sheet, no program, block complete, loading, failed, live workout on a rest day, Monday with
nothing moved), `12` the live workout at the largest text size, `13` the rest day at `accessibility3`.

### Code lines (added lines of `git diff -U0 a00584e`, new files whole, blank and whole-line comment lines excluded)

Counted when the cards were done (622) and at the end (631).

| Path | Added | Removed |
|---|--:|--:|
| `FeatureToday/Today+Previews.swift` (new) | 189 | 0 |
| `FeatureToday/Views/TodayScreen.swift` (new) | 43 | 0 |
| `FeatureToday/Views/TodayPage.swift` (new) | 40 | 0 |
| `FeatureToday/Views/UpNextCard.swift` (new) | 37 | 0 |
| `FeatureToday/Views/RestDayCard.swift` (new) | 27 | 0 |
| `FeatureToday/Views/TodayHeader.swift` (new) | 26 | 0 |
| `FeatureToday/Views/LoggedCard.swift` (new) | 25 | 0 |
| `FeatureToday/Views/OffSchedulePage.swift` (new) | 25 | 0 |
| `FeatureToday/Views/RecentList.swift` (new) | 25 | 0 |
| `FeatureToday/Views/StatsRow.swift` (new) | 23 | 0 |
| `FeatureToday/Views/CardEyebrowLine.swift` (new) | 22 | 0 |
| `FeatureToday/Views/MessageCard.swift` (new) | 20 | 0 |
| `FeatureToday/Views/OffScheduleSheet.swift` (new) | 15 | 0 |
| `FeatureToday/Views/TodayAction.swift` (new) | 9 | 0 |
| `FeatureToday/TodayCopy.swift` | 14 | 0 |
| `FeatureToday/TodayCopy+Cards.swift` | 7 | 0 |
| `LedgerDesign/Components/PrimaryButton.swift` | 38 | 3 |
| `LedgerDesign/Components/IconPillButton.swift` | 35 | 3 |
| `LedgerDesign/Components/Components+Previews.swift` | 10 | 0 |
| `LedgerKit/Package.swift` | 1 | 1 |
| **Product** | **631** | **7** |
| Tests (`TodayAccessibilityTrees` 190, `TodayAccessibilityTests` 124, `ButtonAdditionsTests` 91, `TodaySnapshotTests` 62, `TodayScreenTests` 47, `PreviewTests` 42, `Support/TodayParts` 34, `AccessibilityTreeTests` 24, and one to five lines in `TodayCopyTests`, `TodayTesting`, the tester's `TodayPurityAdversarialTests` and `LedgerTestSupport/Previews/PreviewScan.swift`) | 629 | 5 |

631 against the plan's 610. The views are 337 lines in thirteen files, none over 43; the previews' registry
and its fixtures are 189. Not counted: the catalog (22 lines of JSON), the PNGs, this section.

### The runs (final tree; no source changed after the first of them)

| Run | Result |
|---|---|
| Host: `swift test --package-path LedgerKit --only-use-versions-from-resolved-file --filter 'FeatureTodayTests\|ModuleCopyTests'` | exit 0. `FeatureTodayTests`: 231 tests in 21 suites passed (the iOS-only suites do not run there). `ModuleCopyTests`: 6 passed |
| Host: `scripts/check.sh --lint-only` | exit 0, `check.sh (--lint-only) OK`, 78 s |
| Simulator, three locked sessions (`/usr/bin/python3 <sim-lock> <scratch>/sim-run.sh`: `check.sh`'s step 3 with the same arguments: `build-for-testing`, `scripts/check-string-catalogs.sh`, `test-without-building` of the PR plan with `-only-testing:`; iPhone 17, iOS 27.0). The lock was free each time; 14 GB free before the first, 12 GB after the last | Run 1 (`FeatureTodayTests`, `LedgerDesignTests`): recorded the references; 19 tests failed: 14 for a reference just written, 2 trees (the strip's trait, the header's order at `.accessibility3`, a timer's `updatesFrequently`), 3 of the tester's scans on `Today+Previews.swift` (decision 18). Run 2, after the fixes: 1 failed, the rest day's two references just recorded again. **Run 3, the final tree** (`FeatureTodayTests`, `LedgerDesignTests`, `LedgerAppKitTests`): build status 0; catalog step status 0, "string catalog matches the code: … FeatureToday … (keys: 57)", "3 checked, each matches its module's code"; tests status 0, **791 tests, 784 passed, none failed, 1 skipped, 6 expected failures**: `FeatureTodayTests` 243 passed; `LedgerDesignTests` 305 passed, 1 skipped and 6 expected failures (none of them this slice's); `LedgerAppKitTests` 236 passed. The bundles were read and deleted |

The preview step of the gate is the three targets' `PreviewTests`, which ran in run 3
(`everyModuleWithPreviews_isRegistered`, the three registries, every case rendering).

**Not run, and so not verified:** the full gate (the other iOS test targets, watchOS, the coverage gate, so
`FeatureToday`'s coverage figure); CI; anything on a device; VoiceOver itself (the trees are UIKit's, read in
a test process); the app, which does not show this screen until S5. `LedgerDesign` is built for watchOS by the
watch scheme, and I did not build it there: the two new initializers use `Text(timerInterval:)` and
`Image(systemName:)`, which watchOS has. On the host, `LedgerDesignTests`' font suites fail (Archivo is not
found there; fonts need the simulator, as the task says), so the host run above leaves the target out; I did
not run it on `main` to compare.

### Open questions (each with a recommendation)

1. **Pete, from the screenshots: the four states v2 never drew** (logged, rest day, no program, block
   complete) and the sheet. Recommend he reads `03` to `07` and says what to change; each card is one file of
   20 to 40 lines.
2. **Pete: "Set up program" and "Open Program" in orange** (decision 14). Recommend keeping them: each is the
   one action its screen offers. The other answer is `PillButton` in `MessageCard`, one line.
3. **VoiceOver reads the resume time as of the model's moment** ("Resume · 3:00" ten minutes later, until an
   input changes). Recommend accepting it for S5 and asking the device pass: the alternatives are a label
   without the time (a new key, "Resume workout", and a model field), or letting VoiceOver read the live timer
   (drop the fixed label; the element is then marked as updating frequently).
4. **Spoken forms the model lacks**: "~38 min", "5 × 5 @ 250", "24:22", "Mon · 58 min · 12,243 lb" are read as
   drawn. The review says a spoken form is a new key and a new model field, never a label in a view; none was
   added. Recommend the device pass listens once, as S3's open question 8 asks.
5. **Three wirings no test reaches**: the screen presenting the sheet, a pick closing it, and the Debug long
   press. The hosted reader cannot activate a control inside the screen's scroll view. Recommend S5's nightly
   UI test of the scrolling screen covers the sheet (open, pick, cancel) and `LedgerUITests/DebugMenu` the long
   press, as the plan already has it.
6. **That the time counts in the app** is `Text(timerInterval:)`'s own behaviour with no pause time; no test
   waits a second (no sleeps). Recommend S6's manual check (the brief's DoD) is where it is seen.
7. **"UP NEXT" over a workout that is running, and "Rest day" above it** (S3's open question 4, Pete's
   decision 1): screenshot `10`. For Pete.
8. **"−100%" on a Monday morning, and "1/0" after the block**: screenshots `11` and `07`. For Pete. Hiding the
   change until something has moved this week would be a rule of the presentation.
9. **The tester's two scans** (decision 18): confirm the `*+Previews.swift` exemption, and decide whether they
   should read `Views/` (they forbid any `Text(`, which a view needs, so not as written).
10. **The matrix costs 3.6 MB** against the plan's estimate of about 3.2 MB for 39 images (decision 17).
    Recommend keeping the specification's matrix: the `accessibility3` images are where the layout changes.

### Inputs for S5 (how the root builds the screen)

- **The screen**: `TodayScreen(state: Loadable<TodayModel>, onRoute: (TodayRoute) -> Void, onTitleLongPress:
  () -> Void = {})`. `TodayRoot` draws it with `store.state`, hands `onRoute` to the store's intent (one pending
  route, a second tap dropped: the views do not debounce, a double tap calls `onRoute` twice), and passes its
  own `onTitleLongPress` through. It sets nothing else: `todayTimerPause` stays nil, so the time counts.
- **The sheet is the screen's**, state and all. The root and the store do not know it exists: a picked day
  arrives as an ordinary `.startWorkout` route through `onRoute`, after the sheet has been told to close. When
  a new model's card is no longer a rest day, the screen closes the sheet itself.
- **`.idle` and `.loading` draw the ground; `.failed` draws the two texts and no header.** So `today.title`
  exists only once a model is loaded: `LedgerUITests/Smoke.test_launchesToToday` and the Debug menu's long
  press wait for the first load, and on a failed load neither finds it. The store never shows the error
  itself; the screen ignores `failed`'s payload.
- **The model is all the screen reads.** A new `TodayModel` redraws it; the resume time needs no publish, it
  counts from the model's `startedAt`. Its VoiceOver label is the model's `action.title`, so a store that
  wants the spoken time fresher must rebuild the model (open question 3).
- **The tab's root hides the navigation bar** (S1's decision 8): the page draws its own header and its own 26 pt
  inset below the safe area. The screen's ground is `LedgerColor.ground`, set with `.background` on the scroll
  view. Not looked at in a running app: how it meets the status bar and the tab bar.
- **Previews of the root**: `TodayPreview`'s cases draw the screen from fixed models; a store-driven preview
  would show "Block complete" after 2026-11-08 (the plan's Risks). Remove nothing: S5 deletes
  `LedgerAppKit`'s placeholder case, not these.
- **The nightly UI test** of the scrolling screen (criterion 2): the stops of "The intended VoiceOver trees"
  in their order inside the real scroll view at an accessibility text size, and the sheet's open, pick and
  cancel (open question 5).

## Slice S4 — fix round 1 (G1 implementer, 2026-10-08)

On `feat/F09-s4-views` at `3bc7a53` (the slice as `398ec9a`, then the tester's files, the findings and the
review). No commits. The specification is the brief's "Plan amendments — slice S4 after round 1" (criteria 10 to
13). Product code and my own tests only: `git status --short` lists no file under `Adversarial/`.

### What changed

- **Criterion 10 (F9-S4-1, review S1): the resume button speaks without a time.** `TodayCopy.resumeWorkout`
  ("Resume workout", `TodayCopy+Cards.swift`) and its catalog key; `UpNextCard` hands it to the button as its
  spoken label in place of the model's `action.title`. It is looked up by the view, as the failed state's two
  texts are (S4's criterion 1: "a `TodayCopy` lookup the model does not carry"); the presentation and the model
  are unchanged, as the coordinator's instruction has it, where the review's rule would add a model field. The
  drawn label still counts. `PrimaryButton(label:accessibilityLabel:icon:action:)`: `accessibilityLabel` is now
  `String? = nil`; with nil the label is read as drawn and the element keeps `updatesFrequently`, with a line the
  trait is removed as before. `PrimaryButtonTimerGallery`'s spoken line is "Resume workout" (not drawn: its
  references are unchanged).
- **Criterion 11 (F9-S4-4): the recent list at the accessibility sizes.** `RecentList` reads the text size: at
  an accessibility size a row has no chevron (F06's `HairlineRow` moves an accessory under the title there, and
  the chevron alone made a line of its own), and the gap under "RECENT" is `m` (12) instead of `xs` (4). At the
  other sizes nothing changed. `HairlineRow` itself is untouched, so no `LedgerDesign` reference changed; the
  off-schedule sheet's "Logged" still moves under its day, where it is a word and not an ornament.
- **Review S3's one test:** `PreviewTests.timerPause_isNilByDefault`.

### New text (for Pete)

| Key | Reads | Where |
|---|---|---|
| `Resume workout` (new) | "Resume workout" | VoiceOver, the button of a live workout; the button still draws "Resume · 3:00", counting |

The catalog has 58 keys (57 before). `Resume · %@` is still looked up twice: by the model's `action.title`,
which nothing draws or speaks now but tests and S3's contract hold, and by the timer form.

### The reviewer's nits

| Nit | Done or declined |
|---|---|
| n1, a blank sheet while it leaves | Declined: it would change how the sheet is presented (`.sheet(item:)` over a held copy), behaviour beyond the criteria, for a cosmetic case no reference or test can show here. For S5, with the UI test that opens the sheet |
| n2, layout by size class, not by fit | Declined as a change, settled by a test: `TodayAccessibilityTests.restDayPills_narrowPhoneLargestStandardSize_fit` hosts the rest day 375 pt wide at `.xxxLarge` and holds the two pills side by side, apart, inside the insets (result under "Runs"). `ViewThatFits` would also change which layout the six accessibility references show wherever a line happens to fit ("LOGGED · WEEK 1" beside "24:22"), which no criterion asks |
| n3, `systemImage:` takes any string | Declined: the signature is the plan's (orchestrator decision 9), and a mistyped name already fails: the gear is in every loaded reference and in `iconPillButtonSymbol`'s. A typed list of symbols is a design-system decision for the slice that uses a second one |
| n4, the two galleries are not in `DesignGallery` | Declined now, as the reviewer says: with the next slice that re-records that page |
| n5, `os(iOS)` guards over Debug-only types | Done: `#if os(iOS) && DEBUG` in `TodayScreenTests`, `TodayAccessibilityTests`, `TodayAccessibilityTrees` |
| n6, "`<Screen>Page(model:)`" in the two documents | Not mine: the orchestrator's, when it next edits them |
| n7, `TodayAction.titleLongPress` in release builds | Done: the case and the screen's branch for it are inside `#if DEBUG` |
| n8, the tester's scan reads the top folder only | The tester's, and answered by its new `TodayViewsSourceAdversarialTests` |
| n9, "30,370" and "lb moved" part at a line break | Declined: a change to the copy (a no-break space in a key), for a later slice, as the reviewer says |

Not changed, as ruled: criterion 12's rows and headings.

### Inputs for S5, added (the brief's "For S5")

- **The nightly UI test of Today opens the off-schedule sheet, picks a day and cancels, and checks the route.**
  Open and cancel: the sheet is gone and nothing was routed. Open and pick: the sheet is gone and the
  destination of that day's `.startWorkout` is on screen (the screen closes the sheet and hands the route on in
  the same turn; if the app's presentation is refused while the sheet leaves, hand the route on from the
  sheet's `onDismiss`: review, "Could not settle" 1). Nothing in the package tests reaches
  `TodayScreen.handle`.
- **Once it has loaded, the store never returns to `.loading`.** A refresh replaces `.loaded(old)` with
  `.loaded(new)`, and a store test pins it. The sheet's list is read from the state on screen, so the sheet
  closes whenever the state is not a loaded rest day: a pass through `.loading` (or `.idle`, or `.failed`)
  would close it under the lifter's finger and blank the page.
- Also changed for S5 by this round: the resume button's spoken label no longer depends on the model's age, so
  the store need not rebuild the model for VoiceOver's sake.

### References re-recorded (13), and why

Criterion 11 changes every loaded page at an accessibility size: the recent rows lose their chevron line, and
"RECENT" stands 8 pt further from the first rule (in "no program", from the empty sentence). Each file was
deleted, then written by one locked run of `FeatureTodayTests` in the library's missing-reference mode (the
coordinator's ruling: not `--record-snapshots`), then compared green in the final run. I looked at each of the
thirteen: no row ends in a chevron, "RECENT" clears its rule, nothing else moved but the page's height.
`git status` shows no other PNG under `__Snapshots__` changed.

`Tests/FeatureTodayTests/__Snapshots__/TodaySnapshotTests/`:
- `upNext_matchesReferences.light-accessibility3.png`, `.dark-accessibility3.png`
- `resume_matchesReferences.light-accessibility3.png`, `.dark-accessibility3.png`
- `logged_matchesReferences.light-accessibility3.png`, `.dark-accessibility3.png`
- `restDay_matchesReferences.light-accessibility3.png`, `.dark-accessibility3.png`
- `noProgram_matchesReferences.light-accessibility3.png`, `.dark-accessibility3.png`
- `blockComplete_matchesReferences.light-accessibility3.png`, `.dark-accessibility3.png`
- `resume_largestTextSize_matchesReference.dark-accessibility5.png`

Unchanged: every `large` and `xLarge` reference, `failed`, `offSchedule`, `loading`, the two open-question
states, and all of `LedgerDesignTests`' (152). Screenshots refreshed: `12-live-workout-largest-text-dark.png`
and `13-rest-day-accessibility3-dark.png`; the other 22 show sizes that did not change.

### The tester's tests that need the tester

Nine tests of `FeatureTodayTests/Adversarial/` fail, on the simulator, and no other test of the three targets.
Each pins the old spoken label, the count of 57 texts, or the three copy members a view may ask for. I did not
edit them. No file of the tester's stopped compiling.

| Test | Ruling | It expects | It now gets |
|---|---|---|---|
| `TodayPurityAdversarialTests.lookups_takeTheInjectedLocale()` (`:135`) | 10 | `calls.count == 57` | 58 lookups: the new `Resume workout` |
| `TodayViewsSourceAdversarialTests.views_copyLookups_areTheThreeRuledIn()` (`:70`) | 10 | the views' `TodayCopy` members are `failedBody`, `failedTitle`, `resume` | those and `resumeWorkout` |
| `TodayViewsLayoutAdversarialTests.resumeButton_isReadAsTheModelsTitle()` (`:224-230`) | 10 | one stop labelled "Resume · 3:00", a button that does not update frequently | none with that label; the button reads "Resume workout" (still a button, still not updating frequently) |
| `TodayViewsLayoutAdversarialTests.resumeButton_spokenTime_isTheModelsMoment()` (`:237-242`), the characterisation of F9-S4-1 | 10 | twenty minutes on, the button reads "Resume · 3:00" | "Resume workout" |
| `TodayViewsLayoutAdversarialTests.page_rightToLeft_readsTheSameTree(_:)`, the two live cases | 10 | live workout, stop 18: "Resume · 3:00"; live workout on a rest day, stop 17: "Resume · 12:34" | "Resume workout" at both |
| `TodayViewsTreeAdversarialTests.page_tree_isTheModels(_:)`, the two live cases | 10 | the same two stops | "Resume workout" at both |
| `TodayViewsTreeAdversarialTests.page_tree_isTheSameAtAccessibility5(_:)`, the two live cases | 10 | the same two stops | "Resume workout" at both |
| `TodayViewsTreeAdversarialTests.page_inconsistentModel_isDrawnAsGiven(_:)`, one case (a rest-day title over an up-next card that resumes with another route) | 10 | stop 16: the model's own title, "Spoken resume" | "Resume workout": the button no longer speaks the model's title |
| `TodayViewsTreeAdversarialTests.primaryButton_emitsTheBriefsRoutes()` (`:115-139`), its live case | 10 | a stop labelled "Resume · 3:00" to activate | none; the stop is "Resume workout" (its route is pinned by my `resume_button_sendsResume`) |

The tester's trees take the resume stop from the model's `action.title`
(`TodayViewsAdversarialSupport.swift:172`); under criterion 10
that stop is the fixed text. The contradiction case is worth its eye: the model's title for a resume action is
now drawn nowhere and spoken nowhere.

### Code lines

Product, counted as before: **642** (631 before): `PrimaryButton.swift` +3, `TodayCopy+Cards.swift` +3,
`RecentList.swift` +4, `TodayAction.swift` +2, `TodayScreen.swift` +2 (the two `#if DEBUG` pairs), and the
changed lines counted once. Not counted: the catalog (11 lines of JSON). My tests grew by about 35 lines (the
two new tests, a tree row, the three guards).

### Runs (final tree; no source changed after the recording run)

| Run | Result |
|---|---|
| Host: `swift test … --filter 'FeatureTodayTests\|ModuleCopyTests'` (before the recording) | `ModuleCopyTests` 6 passed; `FeatureTodayTests` 242 tests, 2 failed, both on the list above (the two that run on the host) |
| Simulator, locked, recording: `sim-run.sh` (`check.sh`'s step 3, `-only-testing:FeatureTodayTests`), iPhone 17, iOS 27.0; 7.9 GB free before, 7.6 GB after | build 0; catalog step 0 (FeatureToday: 58 keys); 298 tests, 16 failed: the 7 snapshot tests whose 13 references were just written, and the 9 above |
| **Simulator, locked, final**: the same script, `FeatureTodayTests`, `LedgerDesignTests`, `LedgerAppKitTests`; 7.6 GB free before, 7.8 GB after the bundle was deleted | build status 0; catalog step status 0, "3 checked, each matches its module's code" (FeatureToday keys: 58); `xcodebuild` status 65: **846 tests, 830 passed, 9 failed, 1 skipped, 6 expected failures**. `FeatureTodayTests` 298: 289 passed, 9 failed, exactly the nine above. `LedgerDesignTests` 312: 305 passed, 1 skipped, 6 expected failures. `LedgerAppKitTests` 236 passed. n2's test (`restDayPills_narrowPhoneLargestStandardSize_fit`) and `timerPause_isNilByDefault` passed. The bundles were read and deleted |
| Host: `scripts/check.sh --lint-only` (after the final run) | exit 0, `check.sh (--lint-only) OK` |

**Not verified:** the full gate, coverage, watchOS, CI; a device, and how VoiceOver says "Resume workout" or
anything else; the app (S5); that `PrimaryButton` with no spoken line reads a live, unfrozen timer sensibly
(its hosted tree is pinned frozen: "12:48", a button that updates frequently); a release build of the
`#if DEBUG` case (no lane builds one); n2 at any width but 375 pt and any size but `.xxxLarge`.

### Fix round 2 (2026-10-08): F9-S4-6

- `PrimaryButton(label:accessibilityLabel:…)`: a spoken line that is empty or only white space is treated as
  absent (decided once, in the initializer), so the button reads its drawn label and keeps SwiftUI's own traits;
  the parameter's doc comment says so. The tester's `textButton_emptySpokenLine_isStillNamed` is unedited.
- My test: `LedgerDesignTests/ButtonAdditionsTests.blankSpokenLine_readsTheDrawnLabel(_:)` (four blank lines, a
  plain label and a timer's). No reference changed. Runs: see below.
- Runs, final tree: one locked simulator session (`build-for-testing`, the catalog step, `FeatureTodayTests`
  and `LedgerDesignTests`; iPhone 17, iOS 27.0): build 0, catalog step 0, tests status 0: 625 tests, 618 passed,
  none failed, 1 skipped, 6 expected failures (`FeatureTodayTests` 312 passed; `LedgerDesignTests` 306 passed,
  1 skipped, 6 expected failures). `scripts/check.sh --lint-only` exit 0. `git status` lists no PNG beyond fix
  round 1's thirteen references and two screenshots. Not run: `LedgerAppKitTests`, the full gate, a device.

## Slice S5 — the store, the wiring and the live workout (G1 implementer, 2026-10-09)

The plan's S5 and S6 as one slice (`feat/F09-s5-store-wiring`, cut from `main` at f9a57ef). Today is on screen
in the app: the Today tab draws `TodayRoot`, whose store follows the stores and the live workout's session, and
its routes start and resume workouts through F10's launcher. The contract is "Plan amendments — slice S5" in
the brief (criteria 1–13).

### What landed

`FeatureToday` (new unless marked):

- `TodayStore.swift` — `@MainActor @Observable final class TodayStore`: `state: Loadable<TodayModel>`,
  `pendingRoute`, the intents `send(_:)` and `deliverRoute(to:)`, and `run()`, the one piece of work, which
  `TodayRoot`'s task runs. `TodayStoreError.observationEnded`, `TodayPendingRoute`.
- `TodaySources.swift` — what one `run()` knows of its five sources, and the two plain reads for as long as
  nothing they depend on has changed (`forgetHistory()`, `keep(_:readSince:)`, `known`).
- `TodayHistory.swift` — the two plain reads: `ranges(program:settings:now:calendar:)` (pure) and
  `read(_:workouts:stats:)`; `recentLimit` (5).
- `TodayRoot.swift` — `public struct TodayRoot`, `init(onRoute:onTitleLongPress:)`.
- `TodayInput.swift` (edited) — the comment on `weekWorkouts` says each workout is handed in once, and how.

`LedgerAppKit`:

- `Routes+Today.swift` (new) — `AppRouter.resolve(_: TodayRoute, workout: WorkoutLauncher)`.
- `AppTabs.swift` — the Today tab draws `TodayRoot`; new `onTodayRoute`. `MainRoot.swift` — hands it
  `router.resolve($0, workout: workout)`.
- `UITestClock.swift` (new) and `AppComposition.swift` — the UI tests' own date (deviation 1).
- Deleted: `TodayPlaceholder.swift`, its `AppPreview` case and `#Preview`,
  `LedgerAppKitTests/TodaySnapshotTests.swift` and its two references.

Tests (new): `FeatureTodayTests/TodayStoreTests.swift`, `TodayStoreLiveTests.swift`,
`TodayStoreFailureTests.swift`, `TodayHistoryTests.swift`, `TodayRootTests.swift`, `Support/TodayScene.swift`;
`LedgerAppKitTests/TodayRouteMappingTests.swift`, `UITestClockTests.swift`;
`LedgerPersistenceTests/Performance/TodayQueriesPerformanceTests.swift` (nightly);
`Apps/LedgerUITests/Today.swift` (nightly; the folder is a synchronized group, so the project file is
unchanged). Edited: `LedgerAppKitTests/AppTabsTests.swift` (mine, S1), `ModuleCopyTests.swift` (the module's
own exemptions entry), and three of the tester's files ("Sanctioned edits" below).

### How the store works

- **Five sources, two reads.** `run()` opens a task group with one child per source: the active program, the
  settings, the exercises, the five workouts finished last (each a store's observation) and
  `workoutSession.updates()`. Each child keeps the source's last value in `TodaySources` and marks one
  `AsyncStream<Void>` that keeps only the newest mark; the group's body is the one loop that rebuilds the
  model. So a finish that moves three sources costs one or two rebuilds, never two at a time.
- **The first model waits for all five.** Until each source has spoken in this run nothing is published, so
  the screen never shows "No program" for the instant before the program arrives.
- **The plain reads** (`workouts(in:)` over the week's stretch, `weeklyVolume(in:)` of the week before) are
  made again only when a source they depend on has changed: the program, the settings, the finished workouts,
  an update that ends the session's workout, or a new run. A set logged under the cover is an update of a live
  workout: it reads nothing, and the model it gives is equal to the one on screen, which is not published
  again. A read that a change overtook is used for that turn's model and not kept; the change has marked the
  channel, so the next turn reads again.
- **A new run** (the scene's phase changed, or the tab came back) forgets what the sources said and reads
  everything again at the injected moment, while the model on screen stays until the new one is ready. That is
  how a new day arrives.
- **The session's workout** is handed to the presentation as each update gives it, live or ended; S3's
  presentation counts a finished one as today's workout at once and by its id, whichever of the session and the
  history says so first. Today never calls the session, and never plays an update's haptics.
- **Routes.** `send(_:)` keeps one route waiting and drops a tap that arrives while one waits;
  `TodayRoot`'s `.task(id: store.pendingRoute)` calls `deliverRoute(to: onRoute)`, which hands it on once and
  forgets it when the app's handler has returned.

### Decisions and deviations

1. **A test-only way to fix the app's date: `-LEDGER_UITEST_NOW <ISO 8601 instant>`** (asked for by me,
   approved by the orchestrator on 2026-10-09 with four conditions; **for Pete, and a text for the pull
   request**). Criterion 11 could not be met as written: a UI test's database holds the catalog and no
   program; the only program a running app can get today is the Debug menu's sample workout's, the seed
   program of 8 weeks from Monday 2026-08-17, which ends on Sunday 2026-10-11. From Monday 2026-10-12 Today
   shows "Block complete" on every run, and on any given day only one of "rest day" and "session day" can be
   reached. So: beside `-LEDGER_UITEST`, and only then, the argument moves the app's clock by a constant
   offset so that the launch happens at the instant named; time still runs. It moves
   `AppComposition.Environment.now` (the session's host stamps with it), the process start it is compared
   with (so launch-to-first-frame is unchanged) and the `date` dependency bound at launch. The calendar, the
   time zone and the locale stay the device's. `UITestClock.offset(arguments:launch:)` is the pure function,
   with host tests; without `-LEDGER_UITEST` the argument is ignored (a test pins it); a value that is no ISO
   8601 instant stops the launch with `fatalError` naming the argument (there was no earlier form for a bad
   UI-test set-up to follow: `-LEDGER_UITEST` takes no value that can be wrong). 35 product lines
   (`UITestClock.swift` 24, `AppComposition.swift` 11); no change in `FeatureWorkout` or `LedgerDependencies`.
   **The wart:** a time the system counts by itself is not moved. The workout cover's elapsed time and
   Today's "Resume · m:ss" are drawn by SwiftUI's timer from the device's clock, so under an offset they read
   the offset as well (hundreds of hours for a launch moved three weeks back). The `Today` UI tests do not
   read those times; a test that does (`Smoke`) launches without the argument. **For F15:** when the UI tests
   are centralised, either give the timer views the injected clock (a `TimelineView` schedule from
   `@Dependency(\.date)`), or keep the rule "a test that reads a running time uses the real date" written in
   one place; and replace the Debug-menu seeding below with a seed argument once F08's onboarding is the way
   a program is made.
2. **The UI tests make their program through the Debug menu**: start the sample workout (which saves the seed
   program), then Finish and Discard. It is slow and depends on F10's Debug row, which
   F10's notes say "can go once Today starts workouts". It must stay until a UI test can get a program
   another way (F08's onboarding, or a seed argument).
3. **Criterion 11 is three UI tests in one new file, not one test**: a rest day (sheet: open, cancel, open,
   pick, cover, minimize, Resume, discard), a session day ("Start workout", Settings, minimize, Resume), and
   the session day at an accessibility text size (the stops in order down the real scroll view, and the
   button at the card's end starts the workout: S4's "Inputs for S5"). One launch has one date.
4. **Unbuilt screens go to what the shell has, with no new text** (criterion 13): a past workout selects the
   History tab; the week editor, "Open Program" and "Set up program" select the Program tab; Settings is
   pushed on Today's stack, once however often it is asked for. The plan's table had placeholders named
   "Workout" and "Set up program"; those would be two new texts for screens that F13 and F08 replace.
5. **A read that fails is shown even over a loaded model.** Criterion 3 ("never back to loading") is about
   loading; a day that looks current and is stale seemed worse than "Can't show today right now". The failure
   is logged, the next change of a source reads again, and so does the next run. An observation that ends by
   itself (GRDB's bridge ends a stream when its read fails) is shown the same way
   (`TodayStoreError.observationEnded`); only a new run recovers it, since the source is gone.
   A session whose updates end is not a failure: it is the key's stub, and Today works without a session.
6. **The store's task restarts on every change of the scene's phase** (`.task(id: scenePhase)`), not only on
   becoming active: that costs one more set of reads on the way to the background, and needs no state of the
   root's own. A restart never shows loading.
7. **The route is delivered by `.task(id:)`, as the plan says**, so the second tap of a double tap is dropped
   only while the first waits for that task, which is one turn of the main actor. What makes a double tap on
   "Start workout" one workout in every case is the launcher (it takes no request while it answers one or
   while the cover is up), and for Settings the router's "once" (decision 4); both are tested.
8. **The first load's duration is not logged** (the plan's Risks said S5 would). It needs a clock the purity
   scans rightly refuse in this module; the launch already logs first frame. Left to F26's Diagnostics line.
9. **No identifier was added to Today's views.** Only `today.title` exists; the UI tests find the rest by
   their texts ("Start workout", "Train off-schedule", "Resume workout", a sheet row by the start of its
   label). The plan's `today.upNext.startButton` and the others are a change to S4's views; F15 centralises
   identifiers.
10. **Size**: about 280 lines were planned; 356 product lines landed. The overage is the clock argument
   (35) and the store's split into the store, its sources and its reads, which SwiftLint's limits on a type
   and a function asked for and which reads better than one long class.
11. **Two slips of mine against the brief's git rules, neither with an effect on the tree:** I ran
   `git reset -q` once (after `git add -N .` for a line count; it only emptied the index) and
   `git checkout -- LedgerKit/Tests/LedgerAppKitTests/ModuleCopyTests.swift` once (to take back a debugging
   line I had just added to that file). No other file was touched by either. After that I restored
   temporary edits by writing the bytes back.

### Sanctioned edits to the tester's files

Asked by message before any edit; both approved by the orchestrator on 2026-10-09 ("this slice's tester
audits every edit").

**(A) `FeatureTodayTests/Adversarial/TodayPurityAdversarialTests.swift`** — the two scans refuse every string
literal in the module's top-level sources outside the copy files; `TodayStore.swift` logs with a category and
two messages, as `WorkoutStore` does (standards §8), which standards §7's audit allows.

| Line | Edit |
|---|---|
| 52–58 (new) | `static func isLoggerCall(_ line: String) -> Bool`: the line begins with a call on a logger (`^\s*\w*[Ll]ogger(\.log)?\.\w+\("`), with its comment |
| 94 (`words_liveInTheCopyFiles`) | `return hasWords ? …` became `return hasWords && !Self.isLoggerCall(line) ? …` |
| 109 (`joiner_isTheMiddleDot`) | `return rest.contains("\"") ? …` became `return rest.contains("\"") && !Self.isLoggerCall(line) ? …` |

A planted literal still fails both: with `let planted = "Rest day"` added to `TodayStore.rebuild()`, both
tests failed (mutant M9 below).

**(B) `LedgerAppKitTests/Adversarial/AppTabsAdversarialTests.swift`** and **`AppRootAdversarialTests.swift`** —
they hosted the shell with no dependency bound and read the Today tab as the placeholder's one heading.

| File, line | Old | New |
|---|---|---|
| AppTabs, 2 and 6 | — | `import Dependencies`, `import LedgerTestSupport` |
| AppTabs, 22–29 (new) | — | `rootHeaders(of:)`: `[]` for Today (the shell pins no element on Today's root: no heading of its own, no navigation bar; all of it is inside Today's scroll view), the tab's title for a placeholder tab |
| AppTabs, `hosting` | `AppTabs(router:).withLiveAccessibilityElements(appearance, body)` | the same inside `withTestDependencies { $0.inMemoryStores(); $0.workoutSession = FakeWorkoutSessionClient() }`, read with `outsideScrollViews: true` |
| AppTabs, `launch_showsTodaysPlaceholderAlone` | labels `== ["Today"]`, headers `== ["Today"]` | labels `== []`, headers `== rootHeaders(of: .today)`; display name reworded |
| AppTabs, `eachTab_showsThePlaceholderThatNamesIt` | labels and headers `== [root.title]` for all four | `== rootHeaders(of: root.tab)`: the three placeholder tabs unchanged, Today `[]`; display name reworded |
| AppTabs, `open_inAnotherTab_…` | `rootTop` read on Today's root; back on Today, headers `== ["Today"]` | `rootTop` read on History's root (Today's has no element to measure); headers `== rootHeaders(of: .today)`; every other expectation unchanged (Settings under a bar, both stacks kept, one pop of two pushes, the root hides the bar again) |
| AppTabs, `randomSequences_…` | `headers == [expected]`, the root's title at depth 0 | `headers == expected`, `rootHeaders(of: selected)` at depth 0; the walk and "Settings" at depth above 0 unchanged |
| AppRoot, 5 | — | `import LedgerTestSupport` |
| AppRoot, `root_idleAndReady_readToVoiceOver` | ready root: labels `== ["Today"]`, first is a header | `composition.state == .ready`; the root hosted inside `withTestDependencies { composition.bind(&$0) }` (the composition's own stores and session) and read with `outsideScrollViews: true`: labels `== []` |

**What these five no longer pin, for the tester.** By its elements a ready root no longer differs from an idle
one in `root_idleAndReady_readToVoiceOver` (both read as nothing outside a scroll view); the state is asserted
instead, and the running app's ready root is read by the `Today` and `Smoke` UI tests. I would rather the
tester decide what that test should pin now than invent more. That the Today tab really holds Today's root is
pinned in my `AppTabsTests.todayTab_isTodaysScrollingRoot` (one hosted scroll view on Today, none on a
placeholder tab).

No UI-test file of the tester's was edited.

### Open findings from the nightly UI run (not fixed here, by the orchestrator's ruling)

1. **`TabsAdversarial.test_everyTabRoot_passesTheSystemsAccessibilityAudit` fails.** The system's audit now
   reads the real Today on a fresh database (the "No program yet" state, real date Friday 2026-10-09, light,
   default text size) and reports, word for word:
   - `Today: Contrast nearly passed [9 "Set up program"]`
   - `Today: Dynamic Type font sizes are partially unsupported [48 "RECENT"]`
   - `Today: Text clipped [9 "Set up program"]`
   - `Today: Text clipped [48 "Friday, October 9"]`

   (9 is a button, 48 a static text.) They concern `PrimaryButton`, the `Eyebrow` and the header's date:
   `LedgerDesign` and S4's views, which this slice does not change. I have not judged which are real. This
   slice's tester judges each, and the fix round fixes or excludes each one (testing-strategy §2.7); the slice
   does not merge with that test failing. The PR plan does not run it.
2. **`WorkoutConflictAdversarial.test_conflict_itsTree_bothWaysOut_andOneWorkoutAfterReplacing`** exceeded one
   minute in my first run of all UI tests. **The one-minute limit was my run's own setting**
   (`-default-test-execution-time-allowance 60`), not the Nightly plan's, whose
   `maximumTestExecutionTimeAllowance` is 600 s. Run again under the plan's allowance it passed in 57.9 s; on
   `main` it had passed in 54.9 s (`f10s4-g2/run3.log`). It is a long test, a few seconds longer now that
   Today is the real screen; no edit proposed.

### Criteria → tests

| Criterion | Tests |
|---|---|
| 1 The store | `TodayStoreTests.run_scheduledDay_showsUpNext` (idle until run; the model from the stores at the injected moment), `run_noProgram_inAnotherZoneAndLanguage` (calendar, zone, locale injected), `run_sessionWithoutUpdates_stillShowsToday`; the tester's purity scans (no clock, calendar, locale or zone of the module's own); no `Task {` and no stored task in the module, by reading; intents are synchronous by their signatures |
| 2 Each workout once | `TodayStoreTests.run_overlappingWeeks_readsEachWorkoutOnce` (a block begun on a Wednesday: one read of Mon 14 to Tue 22, two sessions, 2,000 lb); `TodayHistoryTests` (the stretch in six cases; `read_handsInEachWorkoutOnce`); the comment on `TodayInput.weekWorkouts` |
| 3 Never back to loading | `TodayStoreTests.loaded_neverReturnsToLoading` (on a rest day, with a read held at a gate: during a change and during a new run the state is loaded and the sheet's list is the same), `newRun_onTheNextDay_showsThatDay` |
| 4 It follows what changes | `workoutMaterialised_showsLogged`, `programSaved_rebuildsTheModel`, `settingsChange_rebuildsTheModel` (kilograms and a Sunday start) |
| 5 The live workout | `TodayStoreLiveTests.liveWorkout_showsResume_withoutReadingPerSet` (Resume · 3:00 from its start; two sets and a minute later nothing was read; the discard reads once), `liveWorkout_showsResume_thenLoggedOnFinish`, `startedElsewhere_showsResume_discardedShowsStart`; UI `Today` (Resume after Minimize, in the running app) |
| 6 A read that fails | `TodayStoreFailureTests.readFails_showsFailed_thenRecovers`, `streamEndsBeforeAValue_showsFailed`, `cancelledWhileReading_showsNothing` (2 cases) |
| 7 Routes, once each | `TodayStoreLiveTests.route_isHandedOnOnce` (7 routes), `secondTapWhileRouting_isDropped`, `offSchedule_pick_handsOnTheStartOfThatDay`; `TodayRootTests.root_handsARouteOnOnce`; `TodayRouteMappingTests.startWorkout_twice_isOneRequest` |
| 8 `TodayRoot` | `TodayRootTests.root_runsTheStore`, `root_handsARouteOnOnce`; `AppTabsTests.todayTab_isTodaysScrollingRoot`; the Debug menu from the title: UI `DebugMenu`, `Smoke`, `Today` (every one opens it by the long press) |
| 9 Wiring | `TodayRouteMappingTests` (6 tests, every `TodayRoute`); `PreviewTests` (the registry without `.today`); UI `Today` (Start, Resume, Settings in the running app) |
| 10 A refused start | no code in Today: `Routes+Today.swift` only calls the launcher, whose refusals are F10's tests (`WorkoutLauncherRefusalTests`, `WorkoutLauncherConflictTests`); UI `WorkoutConflictAdversarial` |
| 11 The nightly UI test | `Apps/LedgerUITests/Today.swift`, 3 tests |
| 12 The timing test | `LedgerPersistenceTests/TodayQueriesPerformanceTests.everyRead_underBudget` |
| 13 No new text | none added: `TodayCopy` and both catalogs are unchanged; `ModuleCopyTests`, the gate's catalog step |
| The clock argument | `UITestClockTests` (7 tests, 11 cases) |

**Broken on purpose** (each mutant alone, host `swift test`, then restored):

| Mutant | Tests that failed |
|---|---|
| M1 a new run sets `loading` again | `loaded_neverReturnsToLoading` |
| M2 the week read twice and joined | `run_overlappingWeeks_readsEachWorkoutOnce`, `read_handsInEachWorkoutOnce`, and two more |
| M3 `send` without its guard | `secondTapWhileRouting_isDropped` |
| M4 the session's update dropped | the three criterion-5 tests |
| M5 a failed read not shown | `readFails_showsFailed_thenRecovers` |
| M6 a change does not make the reads stale | `loaded_neverReturnsToLoading`, `workoutMaterialised_showsLogged`, `liveWorkout_showsResume_withoutReadingPerSet`, `readFails_showsFailed_thenRecovers` |
| M7 Settings pushed every time | `settings_isPushedOnce` |
| M8 the argument honoured without `-LEDGER_UITEST` | `offset_withoutTheUITestArgument_isNil` |
| M9 a literal `"Rest day"` planted in `TodayStore` | both of the tester's edited purity tests |
| M10 an observation that ends is ignored | `streamEndsBeforeAValue_showsFailed` |
| M11 the model made at a clock of the store's own | at least seven tests of `TodayStoreTests`, `run_scheduledDay_showsUpNext` among them |

M6 first hung instead of failing: the tests' read gate waited on a continuation no cancellation could end. The
gate is now two `AsyncStream`s, which end when the test's task is cancelled at the suite's time limit.

### Product lines (added lines of `git diff -U0 f9a57ef`, new files whole, blank and whole-line comment lines excluded)

| File | Lines |
|---|---|
| `FeatureToday/TodayStore.swift` | 165 |
| `FeatureToday/TodaySources.swift` | 54 |
| `FeatureToday/TodayHistory.swift` | 36 |
| `FeatureToday/TodayRoot.swift` | 31 |
| `LedgerAppKit/UITestClock.swift` | 24 |
| `LedgerAppKit/Routes+Today.swift` | 21 |
| `LedgerAppKit/AppComposition.swift` | 11 |
| `LedgerAppKit/MainRoot.swift` | 11 |
| `LedgerAppKit/AppTabs.swift` | 3 |
| **Total** | **356** |

38 lines removed from `Sources` (the placeholder, its preview case, the lines `MainRoot` and `AppTabs`
replaced). `MainRoot`'s 11 include 6 lines the formatter re-indented when the call above them became
multi-line. `TodayInput.swift` gained a comment only.

### The runs (final tree)

All on the iPhone 17 and Apple Watch Series 12 (46mm) simulators, iOS and watchOS 27.0, Xcode 27.0, every
simulator command through the lock. The source commits are ee47840, 4ea2ac8, a61bc19 and d84de12; only this
section was written after the runs below.

| Run | Result |
|---|---|
| `scripts/check.sh` (full) | exit 0 in 800 s: lint 80 s, iOS build 12 s, iOS tests 415 s, watchOS build 44 s, watchOS tests 244 s. iOS 3,561 tests: 3,533 passed, 15 skipped, 13 expected failures, 0 failed. watchOS 2,263: 2,243 passed, 15 skipped, 5 expected failures, 0 failed. Coverage: `FeatureToday` 98.80 % (1,654 / 1,674; threshold 70 %). Catalog step: `FeatureToday` 58 keys, `LedgerAppKit` 7, both matching the code |
| `scripts/check.sh --fast` | exit 0 in 140 s on the same sources (1,223 Swift Testing tests in 186 suites and 553 in 127 suites, 0 failed); run again after this section was added (the report says how it went) |
| Nightly plan, `LedgerUITests/Today` and `LedgerPersistenceTests/TodayQueriesPerformanceTests`, by themselves | 4 of 4 passed: the rest day 35.3 s, the session day 29.3 s, the accessibility size 17.0 s; the timing test 3.3 s |
| Nightly plan, all of `LedgerUITests` (before the last test-only edits) | 19 tests: 17 passed, 2 failed, both the tester's and unedited ("Open findings"); the conflict test then passed alone |

The timing test's report (95th percentile of 20, budget 50 ms, on the 20,000-set database with the bundled
catalog and the seed program): active program 0.51 ms, settings 0.05 ms, exercises 4.43 ms, recent workouts
2.60 ms, the week's workouts over 13 days 2.39 ms, the previous week's volume 0.16 ms.

Not run: the device; CI (nothing was pushed); the Nightly plan's package tests other than the timing test.

### Screenshots

`tasks/features/F09-today/screenshots/s5/`, from the running app on the iPhone 17 simulator (iOS 27.0), taken
by a UI test that is not committed. At the real date (Friday 2026-10-09, week 8 of the seed program, a
deload), light and dark: `today-no-program-*`, `today-up-next-*`, `cover-from-start-workout-*`,
`today-resume-*`. Under `-LEDGER_UITEST_NOW 2026-09-17T12:00:00Z`, light and dark:
`today-rest-day-fixed-date-*`, `off-schedule-sheet-fixed-date-*` (a rest day cannot be reached at the real
date). I looked at
`today-up-next-light`, `today-resume-dark` and `off-schedule-sheet-fixed-date-light`: the card is Upper B of
week 8 ("Week 8 of 8 · Deload · ~27 min"), Resume reads "Resume · 0:04", and the sheet lists the four days of
week 5 under "Pick a day from week 5." Two things to see there, both S4's and not changed here: the page's
last part (RECENT) sits under the floating tab bar until it is scrolled, and the off-schedule sheet takes the
whole height.

### Text not given by the brief

None that a lifter reads. Two for a developer: the log messages "A store's observation ended while Today was
on screen" and "Today could not be read: …" (category `today`), and the `fatalError` of a UI test's bad date,
"-LEDGER_UITEST_NOW needs an ISO 8601 instant such as 2026-09-17T12:00:00Z: …".

### Not verified

- That SwiftUI cancels and restarts a tab's `.task` when the tab leaves and comes back (the plan's
  "Liveness"). Nothing in this slice writes an older workout, so nothing shows the difference yet.
- The UI tests' rest day in a time zone beyond UTC±11 (the instants are noon UTC).
- VoiceOver by hand on the wired screen; the device.
- `AppComposition.opened`'s binding of the moved `date` runs only in the app (`prepareDependencies`); it is
  exercised by the `Today` UI tests, not by a package test.

### Open questions (each with a recommendation)

1. **The four audit issues on Today** (above). Recommendation: the tester judges each, and the fix round
   fixes or excludes each one with the comment testing-strategy §2.7 asks for. I have no evidence yet for
   which are false positives.
2. **Should a failed read over a loaded model keep the old model?** (decision 5). Recommendation: keep as
   built; it is the honest state and it recovers on the next change or return.
3. **The Debug row "Start sample workout" is now how UI tests get a program.** Recommendation: keep it until
   F08's onboarding lands, then seed by launch argument and drop the row.
4. **`today.*` identifiers.** Recommendation: F15 adds them with the central table; the UI tests' texts are
   English-only until then.
5. **The clock argument's wart** (decision 1). Recommendation: F15 decides between an injected timer schedule
   and the written rule.
6. **`root_idleAndReady_readToVoiceOver`** pins less than it did (above). Recommendation: the tester rewrites
   its ready half, perhaps over the page hosted without its scroll view.

### Inputs for later slices

- **F08's gate.** `MainRoot.content` is still `tabs`; F08 wraps it. While there is no program the Today tab
  shows "No program yet", whose button routes `.setUpProgram`, which today selects the Program tab
  (`Routes+Today.swift`): F08 replaces that case, or removes it if the gate makes it unreachable. When F08's
  save lands, `observeActive` yields and Today shows the day with no call from F08. `Smoke.test_launchesToToday`
  still expects the title "Today" on a fresh database.
- **F13.** `.openWorkout(id)` selects the History tab and drops the id; F13 pushes its detail there (its
  criterion 6). Today re-reads its week when one of the five most recent workouts changes; an edit or a delete
  of an older workout in the current week is seen only by a new run (the tab coming back, the app becoming
  active): verify the tab restart on the simulator when F13's first write lands ("Not verified"). After a
  finish, the session's finished state stays in the store's input until the next update or run, and the
  presentation counts it by id beside the stored one; a workout deleted in History in that same sitting would
  still show as logged until Today's task restarts. If that matters, drop the session's ended state once the
  history holds its id.
- **F14.** `.settings` pushes `AppDestination.settings` on Today's stack, once; F14 replaces the placeholder
  in `AppTabs.screen(for:)`. A saved setting reaches Today through `SettingsRepository.observe()` with no
  call.
- **F10 S6 (the receipt).** `WorkoutRoute.saved` already selects Today; Today shows the day as logged from the
  session's ending update, before the history's observation fires.
- **F11 / F24.** `.editWeek(program:weekIndex:)` and `.openProgram` select the Program tab and drop their
  payload.
- **F15.** The clock argument, the Debug-menu seeding and the identifiers (open questions 3 to 5).

## Slice S5 — review, round 1 (G3 reviewer, 2026-10-09)

Read only: `git diff main...cc0b690`, the files at `cc0b690`, the brief's S5 criteria, the implementer's
section above, standards §4/§7/§8, the M1 conventions, `WorkoutStore`/`WorkoutRoot`/`WorkoutLauncher`/
`Routes+Workout`, and all 12 screenshots. Nothing was built, run or linted by me; every "passes" below is the
implementer's report, not mine. The tester's uncommitted files were not read.

**Verdict: approve with should-fix.** No blocking finding. The store's concurrency is sound by reading; the
should-fixes are one wasteful restart rule, one cache that is not keyed by what it was read for, one test gap,
and a Debug gate on the clock argument. Two things are the product owner's (at the end). The orchestrator's
ruling that the slice does not merge while the audit UI test fails stands outside this verdict.

### Blocking

None.

### Should-fix

- **S-1 The store's task restarts four times per trip to the background, and reads while the app is being
  suspended** (`TodayRoot.swift:41`, deviation 6). `active → inactive → background → inactive → active` is
  four changes of `scenePhase`; each cancels five observations, opens five and makes two reads. Control
  Centre, the app switcher and a system alert each cost two more. Nothing is lost by it (the model stays, an
  equal model is not published, `pendingRoute` is the store's and `isPickingDay` is `TodayScreen`'s `@State`,
  so neither the route nor the sheet goes), so this is cost, not a bug. It still needs no state of the
  root's own to do it once:
  ```swift
  .task(id: scenePhase == .background) {
      guard scenePhase != .background else { return }
      await store.run()
  }
  ```
  One run per return from the background, none on the way out, none for `inactive`. The failure text ("Open
  the app again to try once more") stays true.
- **S-2 No test pins that the root starts a new run at all** (`TodayRootTests.swift`). With `id:` deleted
  from `TodayRoot.swift:41` every test in the diff still passes: `newRun_onTheNextDay_showsThatDay` calls
  `run()` by hand. "A new day arrives" is then pinned in the store and not in the app. Proposed: host
  `TodayRoot` under `.environment(\.scenePhase, …)`, move the scene's clock to the next day, set the phase to
  background and back, expect "Rest day".
- **S-3 The kept reads are not tied to the moment they were read for** (`TodayStore.swift:227-229`,
  `TodaySources.swift:18-34`). `history(for:at:)` returns `sources.history` whenever nothing called
  `forgetHistory()`, whatever `now` is. A rebuild caused by a source that does not forget (the exercises, a
  set logged in a live workout) after midnight builds the new day's model over the old day's reads; across a
  week boundary the "previous week" volume is the week before last until the workout ends or the scene's
  phase changes. Narrow (a workout running over Sunday midnight, seen after Minimize), but it is a wrong
  number on screen. Proposed: keep the `Ranges` beside the read and reuse it only when
  `ranges == kept.ranges`; `followProgram` and `followSettings` then need no `forgetHistory()`, since the
  ranges derive from both. A test: live workout, clock moved past the week's end, one set logged, expect a
  second read.
- **S-4 The clock argument is compiled into release builds** (`UITestClock.swift:38-44`,
  `AppComposition.swift:195-216`). It is honoured only beside `-LEDGER_UITEST` (pinned by
  `offset_withoutTheUITestArgument_isNil`), and a lifter cannot pass launch arguments to an installed app,
  so nothing is reachable in practice. But a shipped binary then carries a path that moves its clock and the
  only `fatalError` in product sources. The `Today` UI tests need a Debug build anyway (they seed through
  the Debug menu), so: `#if DEBUG` around `liveOffset`'s use, `nil` otherwise. With that the `fatalError`
  is acceptable: standards are silent on it, and stopping a mis-set-up test is the right behaviour.
- **S-5 (tester's files) Two edited tests can no longer tell Today from a blank tab.**
  `AppRootAdversarialTests.root_idleAndReady_readToVoiceOver` now expects `[]` for both the idle and the
  ready root, and `AppTabsAdversarialTests` expects `[]` for Today in four tests; `[] == []` holds for an
  empty view too. The implementer said so himself. Proposed for the tester: in the ready half, count the
  hosted scroll views as `AppTabsTests.todayTab_isTodaysScrollingRoot` does (1 ready, 0 idle). The stale
  name `launch_showsTodaysPlaceholderAlone` goes with it.

### Nits

- **N-1** `TodayStore.swift:203`: `rebuild()` has no cancellation check before it writes; the old run's loop
  can run one more turn after SwiftUI cancelled it. I traced it as harmless (it builds from the old run's
  own sources, or finds `known == nil`), but the two runs share `sources` and are kept apart only by five
  `Task.isCancelled` checks (`:162, :185, :191, :234, :240`). `guard !Task.isCancelled else { return }` at
  the top of `rebuild()` makes it true by construction.
- **N-2** `TodayStore.swift:204-207`: once an observation has ended, every later mark logs the same error
  again (each logged set, under a cover). Log when `hasEnded` is set, not on each rebuild.
- **N-3** The notes say a set logged under the cover gives "a model equal to the one on screen, which is not
  published again". The model carries the elapsed title ("Resume · 3:00", from `now`), so it is equal only
  within the same second; in use each logged set publishes. Harmless (Today is under the cover), and
  `liveWorkout_showsResume_withoutReadingPerSet` asserts only that nothing was read. Correct the sentence.
- **N-4** The pending-route machinery (`TodayStore.swift:14-19, 49-51, 77-92`, `TodayRoot.swift:44-46`,
  about 20 lines) drops a second tap only within one turn of the main actor, as deviation 7 says. Passing
  `onRoute` straight to `TodayScreen` would be "exactly once per tap" with none of it. The plan asked for
  `.task(id:)`, so it is the orchestrator's to keep or cut; I would cut it. If the root leaves the screen
  between `send` and the task, the route is delivered when it comes back; I found no way to reach that.
- **N-5** `AppComposition.swift:53-58`: binding `$0.date = DateGenerator(environment.now)` always, not only
  under an offset, makes one clock for the app and removes `Environment.clockOffset`.
- **N-6** The failed state draws no title (`TodayPage.swift:37-38`), so in a Debug build the Debug menu and
  its Diagnostics cannot be opened exactly when a read has failed.
- **N-7** `Today.swift:16-18`: noon UTC is another calendar day in UTC+12 to +14 (New Zealand); the texts
  are English only. Both stated by the implementer; say so in the file's header for whoever runs it abroad.
- **N-8 (for F13)** Every route's destination is idempotent today (a tab selection, the launcher, Settings
  once). When `.openWorkout` becomes a push it needs the same "once" as Settings (`Routes+Today.swift`):
  nothing upstream makes a double tap one push.

### Criteria

| # | Verdict | Evidence |
|---|---|---|
| 1 | met | `TodayStore.swift:45-46` (`@MainActor @Observable`), `:47` (`Loadable<TodayModel>`), `:108-117` (one task group, no `Task {`, no stored task), `:77, :86` (synchronous intents), `:61-63` (date, calendar, locale injected; the zone is the calendar's) |
| 2 | met | `TodayHistory.swift:36-41` (one stretch from the earlier start to the later end), `:53-56` (one read); `run_overlappingWeeks_readsEachWorkoutOnce` asserts one range and 2 sessions / 2,000 lb; comment at `TodayInput.swift:18-21` |
| 3 | met in the store; see deviation 5 | `TodayStore.swift:104-106`; `loaded_neverReturnsToLoading` holds a read at a gate during a change and during a new run. It pins the model's list, not a presented sheet; `TodayScreen.swift:24-33` derives the sheet from that list, so I accept it |
| 4 | met | `workoutMaterialised_showsLogged`, `programSaved_rebuildsTheModel`, `settingsChange_rebuildsTheModel`; waits are `Observations`, no sleep (`TodayScene.swift:282-286`) |
| 5 | met | `TodayStore.swift:160-175`; three tests in `TodayStoreLiveTests`; no timer in the store |
| 6 | met | `TodayStore.swift:204-208, 239-246`; `TodayStoreFailureTests` (three tests, recovery by a change and by a new run) |
| 7 | met | once per tap: `TodayStore.swift:86-92` and `root_handsARouteOnOnce`. One workout per double tap is the **launcher's** guarantee (`WorkoutLauncher.swift:84-90`), pinned by `startWorkout_twice_isOneRequest`; not luck, and not the store (N-4) |
| 8 | met | `TodayRoot.swift:20-25, 39-47`; the sheet is `TodayScreen`'s; the long press is passed through (`:40`) |
| 9 | met, with deviation 4 | `Routes+Today.swift` maps all seven; `AppTabs.swift` draws `TodayRoot`; the placeholder, its preview case and references are deleted |
| 10 | met | no alert in `FeatureToday` or `Routes+Today.swift` |
| 11 | met as three tests (not run by me) | `Apps/LedgerUITests/Today.swift`; fixed dates, `waitForExistence` throughout, no sleep |
| 12 | met by the report (not run by me) | `TodayQueriesPerformanceTests.swift`; six reads, p95 of 20, 50 ms |
| 13 | met | no catalog change; two log lines and one `fatalError` text, for developers |

### The store's concurrency

- **Observed and combined correctly.** Each child writes `sources` on the main actor and then yields a mark;
  the marks' stream keeps the newest one (`:107`), and one loop rebuilds (`:114-116`). A change during a
  rebuild leaves a mark, so no update is lost; marks coalesce, so none is duplicated. All writes are on the
  main actor: there is no data race to have.
- **The stale-reads rule holds.** `staleCount` is taken before the read (`:230`) and the read is kept only if
  no `forgetHistory()` came meanwhile (`TodaySources.swift:30-34`). An overtaken read is still used once,
  with the snapshot taken before it (`known`), so one model from just before the change can be published
  and is replaced on the next turn. Acceptable. Its hole is S-3: "stale" does not include the clock.
- **Cancellation.** The loop and the five children end with the task (AsyncStream iteration ends on cancel);
  nothing outlives `run()`. See N-1 for the one unguarded turn.
- **`Sendable`.** `TodaySources` is not `Sendable` and never leaves the main actor; `TodayHistory`, `Ranges`
  and `TodayPendingRoute` are; the group's closures capture the main-actor store and a continuation.
  Nothing unchecked. Not compiled by me.
- **Three files.** `TodayHistory` earns its file (a pure function of six tested cases and one read).
  `TodaySources` is the lint-driven one, but it gives the stale rule a place and a private setter. I would
  keep the shape.

### Deviations

| # | Judgement |
|---|---|
| 1 clock argument | accept, with S-4 and N-5. Stored data is consistent under an offset: the stores, the session's host and the `date` key all read the moved clock (`AppComposition.swift:44-58, 200`). Only what the system draws itself is unmoved (`Text(timerInterval:)` in `TodayCopy+Cards.swift:60`, `WorkoutTimeline.swift:29`, `PrimaryButton.swift:107`): display only, nothing written |
| 2 Debug row as seeding | accept until F08; it ties three nightly tests to a row F10 meant to remove. F15 input, as written |
| 3 three UI tests | accept |
| 4 unbuilt screens | accept; no button is dead. See "For the product owner" |
| 5 failure over a loaded model | accept as built, but it needs the orchestrator's ruling in the brief: criterion 3's words ("a later change of any input goes from one loaded model to the next") do not allow it, criterion 6's do. What the lifter sees is under "For the product owner" |
| 6 restart on every phase | should-fix, S-1 and S-2 |
| 7 route by `.task(id:)` | accept; honest about where the guarantee is. N-4 |
| 8 first load not timed | accept |
| 9 no identifiers | accept; F15 |
| 10 size | accept. I counted 356 added product lines the same way. One pull request is right: the store has no use without the wiring, and it is under the 1,000-line rule only because tests are not counted (1,919 lines added in all) |
| 11 two git slips | noted; no trace in the tree |

Sanctioned edits: (A) the logger exemption is narrow (a line that starts with a logger call) and M9 shows a
planted literal still fails; accept. (B) lost strength, S-5.

Open questions: 1 the tester's (my reading below); 2 see deviation 5; 3, 4, 5 agree; 6 agree, S-5.

### Screenshots (all 12 opened)

- Dates and weeks are right: Friday October 9 is week 8 of 8; Thursday September 17 is week 5; the sheet
  says "Pick a day from week 5" with four days.
- `today-up-next-*` and `today-resume-*`: "RECENT" and its line sit under the floating tab bar at rest and
  show through it. It scrolls clear; S4's layout, not this slice's.
- `today-up-next-*`: week 8 shows three scheduled days and "0/3" where week 5 shows four. I take it the
  deload week drops Saturday; I did not check the seed program.
- `cover-from-start-workout-*`: the cover is a header over an empty page. That is F10's present state.
- Nothing clipped, no dead-looking button, at the default text size. No accessibility size was captured.

**The four audit issues, from the code and the images (not from a run):**
1. Contrast, "Set up program": white on the accent. By eye from the image about 3.1 : 1, which is the
   large-text line, hence "nearly". The same pill is "Start workout" everywhere. Real and borderline; a
   colour decision in `LedgerDesign`, not this slice.
2. Dynamic Type, "RECENT": `Eyebrow` is 10 pt scaled with `.caption2` (`LedgerFont.swift:90`), which hardly
   moves below the accessibility sizes. It does scale; I read it as the audit's usual complaint about
   `caption2`. Exclude with the comment, or raise the question of a 10 pt label.
3. Clipped, "Set up program": `PrimaryButton` has a minimum height, not a fixed one, and its label wraps
   (`PrimaryButton.swift:62-70`); not clipped in either image. Likely a false positive.
4. Clipped, "Friday, October 9": a caption with no fixed frame (`TodayHeader.swift:17-19`); not clipped in
   either image. Likely a false positive.

### For the product owner, in plain words

1. **"Set up program" opens an empty Program tab, and a recent workout opens an empty History tab**, until
   onboarding (F08, parked) and History (F13) exist. In the running app the only way to get a program today
   is the Debug menu.
2. **If the phone fails to read the database while Today is open, the whole screen is replaced by "Can't
   show today right now"**, the Resume button with it, and the off-schedule sheet closes if it was open. It
   comes back when the app is left and reopened. The alternative is to keep showing the last good day, which
   may be out of date. The implementer chose the first; it should be your choice.
3. **Today does not notice midnight while it is open and in front.** The new day shows when the app or the
   tab comes back. Nobody decided this; say if it matters.
4. **The orange button's white text is at the edge of the contrast rule** (audit issue 1).

### Not checked

Any build, test, lint or simulator run; SwiftUI's restart of a tab's task; the four conditions the
orchestrator set on the clock argument (not in what I read); the seed program's week 8; the watch target;
the tester's uncommitted work.

## Slice S5 — adversarial testing, round 1 (G2 tester, 2026-10-09)

Against `feat/F09-s5-store-wiring` at cc0b690. No product code changed. One real defect, in the test-only
clock argument (F09-S5-5, low); the four issues of the system's audit are judged below (all four are false
positives, each with what makes the system say so); the store held against an oracle over 1,000 seeded walks
once three known limits were stepped around (notes N1 to N3). Four questions.

### What was attacked, and with what

| Area | Tests (new unless marked) | Result |
|---|---|---|
| The system's audit on every reachable state of Today (UI, nightly) | `Apps/LedgerUITests/TodayAuditAdversarial.swift`, 7 tests: no program in light, in dark and at Accessibility Large; a session day (up next, then Resume); the session day in dark; a rest day and its off-schedule sheet; the page scrolled to its end | 6 fail by design in round 1 (nothing is excluded yet: "The audit" below); the scroll test passes |
| The store over sources driven by hand | `FeatureTodayTests/Adversarial/TodayStoreStreamsAdversarialTests` (7 tests, 16 cases), `TodayStoreRestartAdversarialTests` (6 tests, 7 cases), with `TodayStoreAdversarialSupport.swift` and `TodayStoreAdversarialScene.swift` | pass |
| The store against an oracle | `TodayStoreWalkAdversarialTests` (2 tests), with `TodayStoreWalkAdversarialSupport.swift` and `+Steps.swift` | pass, around N1 to N3 |
| Today wired to the router and the launcher, with no view | `LedgerAppKitTests/Adversarial/TodayWiringAdversarialTests` (+`Refusals`, `Support`): 6 tests, 13 cases | pass |
| The clock argument | `LedgerAppKitTests/Adversarial/UITestClockAdversarialTests`, 9 tests | 1 fails (8 cases): F09-S5-5 |
| The sanctioned edits | `TodayPurityAdversarialTests.loggerExemption_coversThreeLinesOfTheStore` (added), `AppRootAdversarialTests.root_idleAndReady_readToVoiceOver` (strengthened), `AppTabsRootAdversarialTests` (new, 10 seeds) | pass |
| The eyebrow's Dynamic Type curve | `LedgerDesignTests/Adversarial/EyebrowDynamicTypeAdversarialTests`, 2 tests (iOS) | pass |

**The store over scripted sources** (`ScriptedScene`: five feeds the test yields into and ends, and a workout
store whose reads each wait until the test lets that one go):

- the five sources first speaking in each of the 120 orders: nothing is read and nothing shown before the
  fifth, then one read and the model;
- each source saying the same thing three times: nothing is published; the exercises cause no read;
- each store's observation ending over a loaded model: `failed(observationEnded)`, which no other source's
  change lifts, and a new run goes from `failed` to `loaded` with no `loading` between;
- the session's stream ending over a loaded model: still loaded, still following the stores;
- ten restarts in a row with the old run not waited for (as SwiftUI restarts a task): one stream of each
  source is listened to afterwards, eleven were opened, the screen showed nothing but the model, and the next
  change costs one read and one publication; a root that went away listens to nothing;
- a read the old run began, let go after the new run's model, failing or not: nothing changes;
- three program changes while a read waits: the last is the one shown, in at most three reads; a workout
  stored and reported while a read of the empty week waits: the week is read again and the workout counted;
- routes asked for with no run, during a read (a double tap), after the task was cancelled and after the run
  ended: each handed on once; a route sent from inside the app's handler is dropped, not delivered twice.

**The store against an oracle.** A walk is 24 bursts of one to four steps taken without waiting for the store:
a setting saved (any of the seven week starts, the units, the same value again), the program renamed, re-dated
(a block that began on any weekday, up to ten weeks ago so that it is over, or up to two weeks ahead), deleted
and saved again, a workout stored (the last sixteen days, of the program or ad hoc) or deleted, a workout
started, logged in, finished (and stored, as the host does) or discarded in the fake session, the task
restarted without waiting, and the clock moved on by an hour to a week with a restart. After each burst the
store must show exactly `TodayPresentation.make` over the stores as they stand, with the week's stretch found
from `Calendar` alone and not from `TodayHistory.ranges`, and must never have shown `loading` or `failed`. In
UTC, Los Angeles, Auckland (clocks change on 2026-09-27, inside the walks) and Kolkata. The PR lane runs 10
walks, the nightly 100; I ran 1,000 once (`LEDGER_PROPERTY_SEED_COUNT=20000`, 78 s): all end at the oracle's
model. A second test compares `TodayHistory.ranges` with the calendar's two weeks for 200 (nightly 2,000)
random moments, week starts, block starts and zones: equal in every case. Criterion 2 holds for a Sunday and a
Monday start and for a block that starts mid-week.

**The wiring.** For each of the five cards a test can make (no program, up next, rest day, logged, block
complete), every route the model's controls carry is tapped alone on a fresh app: `send`, `deliverRoute`,
`AppRouter.resolve`, `WorkoutLauncher.run()`. A start route ends with the cover up over Today and the
session's workout the control's own week and day (all four rows of the off-schedule list); every other route
moves a tab or pushes a screen and starts nothing; no control is dead. "Start workout" twice in one turn, a
third time before the launcher answered and a fourth with the cover up: one request, one `started` in the
session, and Today's card then offers Resume, which starts nothing. Another day picked while a workout is
live: the launcher's `conflict`, the live workout untouched, no tab moved. A start for a day whose program
was deleted after Today drew its button: `failed(.notStarted(.dayNotInProgram))`, nothing live, and the next
tap is answered again. Resume with nothing live: idle, and the launcher free. From every tab, with stacks on
two other tabs, each of the seven routes changes only what its mapping names.

### Findings

| # | Severity | What | Reproducing test |
|---|---|---|---|
| F09-S5-1 | false positive (a question for Pete, Q2) | Audit: "Contrast nearly passed" on the orange button ("Set up program", "Start workout", "Resume · …") | `TodayAuditAdversarial` (5 of its tests), `TabsAdversarial.test_everyTabRoot_passesTheSystemsAccessibilityAudit` |
| F09-S5-2 | false positive | Audit: "Dynamic Type font sizes are partially unsupported" on every eyebrow ("RECENT", "UP NEXT", "SCHEDULED REST") | the same; the cause is pinned by `EyebrowDynamicTypeAdversarialTests` |
| F09-S5-3 | false positive | Audit: "Text clipped" on the orange button's label | the same |
| F09-S5-4 | false positive | Audit: "Text clipped" on the header's date, and on four more texts in other states | the same |
| F09-S5-5 | low, a defect (test-only code) | `-LEDGER_UITEST_NOW` accepts a date that does not exist and text after the instant | `UITestClockAdversarialTests.offset_valueThatIsNoRealInstant_isRefused` (8 cases, failing) |

**F09-S5-5.** `UITestClock` promises that "a value that cannot be read stops the launch: a UI test set up
wrongly must not run on the real date and pass or fail by the weekday". `Date(_:strategy: .iso8601)` reads
more than instants: `2026-02-30T12:00:00Z` is 2 March, `2026-09-31T12:00:00Z` is 1 October,
`2026-09-17T25:00:00Z` is 01:00 on the 18th, `…T12:00:60Z` is 12:01, and `…Z trailing`, `…ZZ`, `…Z\n` and
`…Z;2026-09-18T12:00:00Z` are read as the instant before the extra text. A UI test with a mistyped day so
runs on a day its author did not write, which is what the `fatalError` exists to stop. A fix: format the date
read back with the same style and require the text to match, or check the fields against the calendar. (Also
read, and reasonable: fractional seconds, `+0200`, `+02`.) The other 17 malformed values I tried are refused;
the same moment written with nine zone offsets is one instant; the repeated hour of a clock change is told
apart by the offset written; the offset is one number, so a run that crosses a real clock change keeps real
seconds; given twice, the first is used; without `-LEDGER_UITEST` (or with it in another spelling) nothing
moves, in `offset` and in `Environment.live`.

### The audit: a verdict on each issue

`TabsAdversarial.test_everyTabRoot_passesTheSystemsAccessibilityAudit` fails with the four issues the
implementer listed; I ran it again (`audit1`) and the same four came back. `TodayAuditAdversarial` then ran the
audit on the other states. What the system reports, with each element's frame (iPhone 17, iOS 27.0):

| State | Issues |
|---|---|
| No program, light and dark | Contrast nearly passed: button "Set up program" (26, 363, 350 × 54). Dynamic Type partially unsupported: "RECENT" (52 × 10). Text clipped: the header's date (142 × 12); "Set up program" |
| No program, Accessibility Large | Text clipped: the date (283 × 24), "Set up program". Contrast failed: "RECENT" (y 816) and "No sessions yet. Your first workout lands here." (y 859). No Dynamic Type issue, and no contrast issue on the button |
| Up next, light | The no-program four on "Start workout", "RECENT" and the date, and: Dynamic Type on "UP NEXT"; Text clipped on "Week 5 of 8 · ~38 min" (113 × 12) and "Lower A — Squat focus" (264 × 29); Contrast failed on "No sessions yet…" (y 804) |
| Up next, dark | The same without "Contrast failed" |
| Resume | As up next, on "Resume · 555:29:47" (the moved clock's wart, deviation 1) |
| Rest day | Dynamic Type on "RECENT" and "SCHEDULED REST"; Text clipped on "SCHEDULED REST" (116 × 10), "No session today" (197 × 29) and the date. No contrast issue: "Train off-schedule" is not the orange button |
| Off-schedule sheet | none |

1. **Contrast nearly passed, the orange button: a false positive by the rule the design chose, and the
   thinnest pass in the app.** Measured from the pixels of the element's picture in the run (light and dark,
   both buttons): the fill is (255, 91, 34), the label (255, 255, 255), a ratio of **3.10:1**. The label is
   16 pt at weight 700; WCAG 2.1 counts bold text from 14 pt as large text, whose AA minimum is 3:1, and
   `LedgerFont` says so where the role is defined ("bold: white on accent is 3.1:1"). At Accessibility Large
   the system does not report the button, which fits a threshold by size on its side. Nothing to fix by the
   project's rule; the margin is 0.10, so it is Q2 for Pete. **Exclude:** `.contrast` on the orange button.
2. **Dynamic Type partially unsupported, the eyebrows: a false positive.** The eyebrow is 10 pt on the
   system's Caption 2 curve, and that curve is flat below the default text size (the system's own Caption 2
   is 11 pt from Extra Small to Large). So the eyebrow does not shrink below the default and grows at every
   size above it: 10 pt up to Large, larger at each of the eight sizes above, at least 20 pt at the largest
   (`EyebrowDynamicTypeAdversarialTests`, which also shows that the caption, which the audit does not report,
   does shrink below the default). In the run the same "RECENT" is 10 pt tall at the default and 22 pt at
   Accessibility Large, where the system no longer reports it. **Exclude:** `.dynamicType` on the eyebrows.
3. **Text clipped, the orange button, and 4. Text clipped, the header's date: false positives; nothing is
   cut on screen.** The pictures of the screen show every letter whole, descenders and the comma included
   (`att1`: "Wednesday, September 16", "Set up program", "Lower A — Squat focus"). What the system measures
   is the text's frame, and for these roles the frame is shorter than the font: `.ledgerFont` sets the line
   height to the role's multiple of the size (1.0 for the caption, the button, the eyebrow and the title; 1.08
   for the heading), and Archivo's own ascent plus descent is 1.088 of the size (0.878 and 0.210, read from the
   font file with Core Text), so the frame of a 12 pt date is 12 pt tall and its descenders are drawn below it. The picture of the element alone, cropped
   to that frame, shows them cut; the screen does not, because SwiftUI does not clip a text to its frame. It
   is F06's native line height (Pete, 2026-09-29, decision 1), whose own tests note ink outside the frame
   (`LedgerFontSizingAdversarialTests`). The roles with a taller line (body 1.2, bodyLight 1.6) are never
   reported, which fits; but the system does not report every text with a short frame either (the 32 pt title
   and the eyebrows "RECENT" and "UP NEXT" are not, "SCHEDULED REST" is), and I do not know its rule. **Exclude:** `.textClipped` on Today's texts in those roles. A fix at the root (a
   frame as tall as the font where the role's line is shorter) would move every screen's layout and
   references; not for this slice.
5. **Also reported, on other states: "Contrast failed" on the page's last lines. A false positive.** While
   the page rests at its top the floating tab bar is drawn over its end ("RECENT" and the line under it),
   and the system measures the bar's glass. `TodayAuditAdversarial.test_sessionDay_theLastLineScrollsClearOfTheTabBar`
   scrolls to the end at the default size and at Accessibility Large: the last line then stands whole above
   the bar. **Exclude:** `.contrast` on an element whose frame meets the tab bar's.

**For the fix round:** nothing in the views. **For round 2** (the exclusions, in `TabsAdversarial` and
`TodayAuditAdversarial`, each with the comment testing-strategy §2.7 asks for): the four kinds above. Today
has no identifiers but `today.title` (deviation 9), so an exclusion can only name an element by its label or
its frame; `today.*` identifiers on the button and the eyebrows would make them exact (Q4).

### The sanctioned edits

- **`TodayPurityAdversarialTests` (A).** `isLoggerCall` leaves a whole line out of both scans, so a second
  literal on a logger's line, or a fourth logger line anywhere in the module, would pass unseen. Added
  `loggerExemption_coversThreeLinesOfTheStore`: the exempt lines are exactly three, all in `TodayStore.swift`
  (the category `"today"` and two `logger.log.error` messages), each holds one literal, and a message prints
  nothing but `String(describing: error)` marked public. The two scans are otherwise as strong as before (the
  implementer's M9 stands).
- **`AppRootAdversarialTests.root_idleAndReady_readToVoiceOver` (B).** It should pin what tells a ready root
  from an idle one, which its elements no longer do. It now also hosts both in a window and counts SwiftUI's
  page scroll views: none in the idle root, one in the ready root over the composition's own stores. What
  Today reads to VoiceOver stays with `TodayAccessibilityTests` (the page) and the `Today` UI tests.
- **`AppTabsAdversarialTests` (B).** No check was removed, but four tests now expect "no header" on Today,
  which an empty screen would satisfy too. `AppTabsRootAdversarialTests` restores it: over ten seeded walks
  of selections, opens and resets, the shell shows one page scroll view exactly when Today is selected with
  an empty stack, and none on a placeholder tab or under a pushed Settings. The edited file is unchanged.

### Mutation

Each alone, host `swift test --filter 'FeatureTodayTests|LedgerAppKitTests'`, restored from a scratchpad copy.

| Mutant | Tests that failed |
|---|---|
| A1 a store's value is kept after its run was cancelled (`follow` without its guard) | **none** |
| A2 a read that ends after cancellation is used and kept | the implementer's `cancelledWhileReading_showsNothing`; `routes_whateverTheRunDoes_areHandedOnOnce` |
| A3 a read that a change overtook is kept (`keep` without its count) | first run: **none**; then `readOvertakenByAFinish_isMadeAgain`, written for it |
| A4 the update that ends the session's workout reads nothing | the implementer's `liveWorkout_showsResume_withoutReadingPerSet` |
| A5 an equal model is published again | `sameValueTwice_publishesNothing`, `restarts_leaveOneObservationPerSource` |
| A6 a new run keeps what the sources said in the old one | `oldRunsRead_endingLate_changesNothing`, `storeStreamEnds_overALoadedModel_failsUntilANewRun` |
| A7 a change of the finished workouts reads nothing | the implementer's `workoutMaterialised_showsLogged`; `sameValueTwice_publishesNothing`, `readFails_overTheRestDay_…`, `walks_endAtTheOraclesModel` |
| A8 the program week is not joined to the stats week | `run_overlappingWeeks_readsEachWorkoutOnce` and four of `TodayHistoryTests` (the implementer's); `ranges_areTheCalendarsWeeks` |
| A9 before the block, the program week is the negative one | one of `TodayHistoryTests`; `ranges_areTheCalendarsWeeks` |
| A10 "Set up program" goes nowhere | the implementer's `programRoutes_selectProgram`; `everyControl_ofEveryState_doesSomething`, `routes_changeOnlyWhatTheyName` |
| A11 the clock argument given twice uses the last | `offset_givenTwice_usesTheFirst`, `offset_malformedValue_isRefused` |
| A12 the route is forgotten before the handler runs | `route_sentFromInsideTheHandler_isKeptForTheNextDelivery` |
| A13 a session whose updates end is a failure | the implementer's `run_sessionWithoutUpdates_stillShowsToday`; `sessionStreamEnds_overALoadedModel_staysLoaded`, `sessionStreamEnds_whileLive_keepsResume` |
| A14 the exercises make the reads stale | `sameValueTwice_publishesNothing` |
| A15 a failed read after cancellation is shown | the implementer's `cancelledWhileReading_showsNothing` |

Before this round's tests, A1, A3, A5, A6, A11, A12 and A14 passed every test (read from which tests failed:
none of the implementer's). **A1 is still missed**, and I could not make it show: a value an old run's stream
still holds when the run is cancelled is taken in before the new run empties what the sources said, so the
guard in `follow` is a second line of defence with nothing observable behind it in these tests. A2 and A15,
its neighbours in the reads, are caught. (`UITestClockAdversarialTests`' finding fails in every run, mutant or
not, and is left out of the table.)

### Notes (limits the walks found; no failing test)

- **N1. The store's sign that the history changed is the five workouts finished last.** A delete (or, later,
  an edit) of a workout behind them is seen by a new run only: the implementer's "Inputs for F13" says so.
  Seed 269263 found it (the sixth workout of the week, deleted, stayed counted: 6 sessions for 5). New here:
  the same holds for a workout that *arrives* behind them. Seed 380129: stored with a start in last week
  behind five newer ones, it left "−86% from last week" where −90% was true. The app stores a workout when it
  ends, which makes it the newest, so nothing reaches this today; a workout that arrives late will (the
  watch's, in M2). The union stretch is up to thirteen days, and before the block's first day it runs to the
  end of week 1, so more than five workouts in it is ordinary.
- **N2. The session's ended workout stays in the store's input until the task restarts** (also in "Inputs
  for F13"): finished, stored and then deleted in the same sitting, it still counts as today's (seed 55450).
- **N3. A finished session's workout is counted whenever it started.** `TodayPresentation.withFinishedSession`
  adds it without asking whether it started in the two weeks, while the history's read holds only those. Seed
  475157: a workout left live for eleven days, its program re-dated under it, then finished, is marked
  "Logged" in the off-schedule list until the next run and not after it. `TodayInput.weekWorkouts` says "a
  workout outside both weeks is not counted anywhere". S3's code, reached through S5's store; it takes a
  re-dated program to see.
- **N4. A rebuild after midnight mixes the new day with the old reads** (by reading, no test). The store reads
  `date.now` on every rebuild and keeps the two reads until a source they depend on changes. With the app in
  front across midnight, a set logged under the cover gives a model with the new date and the old week's
  reads; on a Monday the volume's change is then against the week before last. It lasts until the next change
  of the history or the next run, and needs the phone unlocked across midnight.

### Questions

- **Q1 (Pete; the implementer's open question 2).** Deviation 5 shows a failed read over a loaded model.
  `TodayScreen` closes the off-schedule sheet when the state stops offering the list, so one failed read
  closes the sheet under the lifter's finger, which is what criterion 3 kept `loading` away for. Pinned as
  built: `TodayStoreStreamsAdversarialTests.readFails_overTheRestDay_takesTheListAway_untilTheNextChange`
  (it also shows that the failure recovers with the next change of any source, the exercises included).
  Keep, or keep the last model while a read fails?
- **Q2 (Pete).** White on the accent is 3.10:1, AA for bold text of 14 pt and more and 0.10 above the line.
  Accept and exclude, or darken the fill for the button?
- **Q3 (orchestrator).** A session whose updates end while its workout is live keeps "Resume" until a new
  run (`sessionStreamEnds_whileLive_keepsResume`, as built). The app's host never ends its stream. Leave?
- **Q4 (orchestrator).** Identifiers on Today's button and eyebrows now (for exact exclusions in round 2), or
  exclusions by label until F15?

### Not attacked

- `TodayRoot` hosted: the restart on a change of the scene's phase and SwiftUI's restart of a tab's task
  (the store's side of a restart is attacked; the view's is not), and a double tap through the real
  `.task(id:)`. The implementer's `TodayRootTests` are the only hosted tests of the root.
- The store over GRDB (the in-memory stores and scripted sources only); the timing test.
- The UI tests in a zone beyond UTC±11, on a device, with VoiceOver by hand.
- The audit at text sizes other than the default and Accessibility Large, with Bold Text or Increase
  Contrast, and on the logged and block-complete cards (no UI test can reach them without a seed argument).
- `MainRoot` and `AppComposition.opened`'s binding of the moved `date` (the app only).
- watchOS: nothing of this slice builds there.

### The runs

| Run | Result |
|---|---|
| `scripts/check.sh --lint-only` (final tree) | exit 0 |
| `scripts/check.sh --fast` (final tree) | exit 0: 553 and 1,223 tests, 0 failed |
| Host, `swift test --filter 'FeatureTodayTests\|LedgerAppKitTests'` | every test passes but the 8 cases of F09-S5-5 |
| Host, the walks at `LEDGER_PROPERTY_SEED_COUNT=20000` (1,000 walks) with the scripted suites | 12 tests passed in 78 s (before `readOvertakenByAFinish_isMadeAgain` was added) |
| Simulator (iPhone 17, iOS 27.0, through the lock), PR plan, the ten suites this round wrote or edited (`sim2`) | 53 tests: 52 passed, 1 failed (F09-S5-5). Among them the iOS-only ones: `AppTabsAdversarialTests`, `AppTabsRootAdversarialTests`, `AppRootAdversarialTests`, `EyebrowDynamicTypeAdversarialTests` |
| Simulator, Nightly plan, `LedgerUITests/TodayAuditAdversarial` (6 tests) and `TabsAdversarial/test_everyTabRoot_…` (`audit1`) | 7 of 7 failed, as "The audit" lists; 121 s |
| Simulator, Nightly plan, `TodayAuditAdversarial/test_sessionDay_theLastLineScrollsClearOfTheTabBar` (`scroll1`) | passed, 45.6 s |

The UI file was formatted after its runs (line wrapping only) and not run again. Not run: the full gate, the
watch, the rest of the Nightly plan, CI. Logs and the audit's pictures are in the session's scratchpad
(`f09s5-g2/`), not in the repository.

**Failing on purpose at this commit:** `UITestClockAdversarialTests.offset_valueThatIsNoRealInstant_isRefused`
(PR lane; F09-S5-5), and the six audit tests of `TodayAuditAdversarial` with `TabsAdversarial`'s (nightly;
F09-S5-1 to 4, until round 2's exclusions).

## Slice S5 — fix round 1 (G1 implementer, 2026-10-09)

Criteria 14 to 17 of "Plan amendments — slice S5 after round 1", on d717529. Commits 32e9ef0 (`fix(today)`) and
e888667 (`fix(app)`). No file of the tester's was edited, and none of the tester's tests changed its result
except the one finding, which now passes.

### By item

- **14 (review S-1, S-2). The store runs again only when the app comes back.** `TodayRoot.swift`: the task's
  id is `scenePhase == .background`, and it runs nothing while that is true. So one run per return from the
  background, none on the way there, none for `inactive` (Control Centre, the app switcher, an alert).
  `TodayRootTests.root_backFromTheBackground_runsTheStoreAgain` hosts the root under a scene phase the test
  moves (active, inactive, active, inactive, background, the clock moved to the next day, inactive, active)
  and waits, after each move, until SwiftUI has shown the root that phase: the next day is on screen, and the
  workout store was asked to observe exactly twice (`ProbedWorkouts.observations`, new, in my test support).
  **Found on the way:** a view hosted with no scene, as every package test's window is, is told its phase is
  the background, so the root runs nothing there. My two older root tests timed out on the first simulator
  run for that reason; their helper now hosts in an active scene. The doc comment on `TodayRoot` says so. In
  the running app the `Today` and `Smoke` UI tests pass on the fixed tree (below).
- **15 (review S-3; tester's N4). A read is used only for the days it was read for.** `TodaySources` keeps
  the reads with the `TodayHistory.Ranges` they were made for; `TodayStore.history(for:at:)` finds the
  moment's ranges first and uses the kept reads only when they are equal. `forgetHistory()` stays where it
  was (the program, the settings, the finished workouts, an update that ends the session's workout): the
  reviewer's further step, dropping it for the program and the settings, would change how many reads the
  tester's tests count, and is not needed for the criterion. Tests, in `TodayStoreLiveTests`:
  `rebuild_acrossMidnight_showsTheNewDay` (Wednesday to Thursday with a workout live: the new date and "Rest
  day" over one read, which is still the right one) and `rebuild_acrossTheWeeksEnd_readsTheNewWeeks` (Sunday
  23:50 to Monday 00:10 with a workout live and one set logged: a second read, of Mon 21 to Mon 28; "0" sessions
  and "0 lb moved this week, −100% from last week" against the week that just ended; the next set reads
  nothing).
- **16 (review S-4; F09-S5-5). The clock argument is strict, and read only in Debug builds.**
  - *Strict.* `UITestClock.instant(written:)`: what Foundation read is written out again in the offset the
    text gave and must be the text. Accepted: `yyyy-MM-ddTHH:mm:ss` and then `Z`, `±HH:MM` or `±HHMM`
    (`+00:00` and `+0000` for no offset). Refused now: a date that does not exist, hour 25, second 60, and
    anything after the instant. **Also refused now, which round 0 read:** fractional seconds and an offset
    of hours alone (`+02`); the tester called those "reasonable", the criterion says "written exactly", and
    no test uses them. The tester's `offset_valueThatIsNoRealInstant_isRefused` (8 cases) passes unedited,
    with its eight other tests.
  - *Debug only.* The body of `UITestClock.liveOffset(arguments:)`, the one place the launch reads the
    argument and the one `fatalError`, is inside `#if DEBUG`; otherwise it returns nil. **Not the whole
    type:** `offset(arguments:launch:)` and `instant(written:)` (pure, with no caller in a Release build)
    still compile in Release, because the tester's `UITestClockAdversarialTests` names them outside any
    `#if DEBUG` and would stop compiling in a Release test build. If "compiled only into Debug" must hold
    for the type, that file needs a guard: the tester's edit.
  - *The builds, checked:* the `Ledger` and `LedgerWatch` schemes' `TestAction` is `buildConfiguration =
    "Debug"`; `scripts/check.sh` and the workflows pass no `-configuration` to a test build (the one
    `-configuration Release` in the repository is a script test of the Xcode Cloud post-clone step). So the
    gate's and CI's UI tests keep the argument; an archive (Release) loses it, which is the point.
  - `ModuleCopyTests`' exemptions for `UITestClock.swift` gained `"Z"`.
- **17 (review N-2). An ended observation is logged once**, where `follow` sets `hasEnded`, and no longer by
  each rebuild that finds it. No test: the logger is not observable. The tester's
  `loggerExemption_coversThreeLinesOfTheStore` still counts three logger lines in `TodayStore.swift`, and
  passes.

Not done, by the rulings: N-1 (a cancellation check at the top of `rebuild()`), N-4 and N-5. **A correction
to my round-0 notes (review N-3):** a set logged under the cover does not give "a model equal to the one on
screen"; the model carries "Resume · m:ss" made from the moment, so it is equal only within the same second.
What holds, and what the test pins, is that it reads nothing.

### Broken on purpose

| Mutant | Result |
|---|---|
| R1 the kept reads used whatever they were read for | `rebuild_acrossTheWeeksEnd_readsTheNewWeeks` failed |
| R2 the instant read by Foundation alone | the tester's `offset_valueThatIsNoRealInstant_isRefused` failed |
| R3 the root's task never restarts (`.task { }`) | `root_backFromTheBackground_runsTheStoreAgain` failed (the next day never came; the time limit) |
| R4 the root's task restarts on every phase (round 0's rule) | the same test failed: 7 observations for 2. Its first form counted reads and passed under this mutant; it counts observations since |

### Product lines now: 383 (356 after round 0)

| File | Lines |
|---|---|
| `FeatureToday/TodayStore.swift` | 165 |
| `FeatureToday/TodaySources.swift` | 57 |
| `FeatureToday/TodayHistory.swift` | 36 |
| `FeatureToday/TodayRoot.swift` | 34 |
| `LedgerAppKit/UITestClock.swift` | 45 |
| `LedgerAppKit/Routes+Today.swift` | 21 |
| `LedgerAppKit/AppComposition.swift` | 11 |
| `LedgerAppKit/MainRoot.swift` | 11 |
| `LedgerAppKit/AppTabs.swift` | 3 |

The clock argument is now 56 lines (45 and 11), over the "about 40" of the ruling that approved it at 20: the
21 added are the strict reading criterion 16 asks for.

### The runs (on e888667; only this section was written afterwards)

| Run | Result |
|---|---|
| `scripts/check.sh` (full, through the lock) | exit 0 in 748 s. iOS 3,597 tests: 3,569 passed, 15 skipped, 13 expected failures, 0 failed (419 s). watchOS 2,263: 2,243 passed, 15 skipped, 5 expected, 0 failed (233 s). `FeatureToday` coverage 98.99 % (1,668 / 1,685) |
| `scripts/check.sh --fast` | exit 0 in 148 s. It does not run `FeatureTodayTests` or `LedgerAppKitTests` (its counts, 1,223 and 553, did not move with them); those ran on the host by `swift test --filter` during the work and on the simulator in the full gate |
| Nightly plan, `LedgerUITests/Today` and `Smoke` | 6 of 6 passed (Today 34.4 s, 29.4 s, 18.6 s) |

Not run: the nightly audit tests (red until the tester's round 2, by the ruling), the rest of the nightly
plan, a Release build, the device.
