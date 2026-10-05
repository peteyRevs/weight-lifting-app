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
   `LedgerTestSupport/Previews/PreviewScan.swift` `registeredModules`): add only your module's name. The orchestrator
   resolves the conflicts when it merges `main` into a branch.
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
| 4. Every string the shell shows comes from the catalog, decision #29's two included, wording unchanged; catalog and code agree both ways, by a test | `AppCopyTests.copy_followsTheStandard` (both directions, and no copy outside `AppCopy.swift`), `builtBundle_resolvesEveryKey`, `databaseUnavailable_keepsItsWording`, `tabTitles_areTheSpecs`, `destinationTitles_nameTheScreen`; the pattern itself: `CatalogFixtureTests`, `StringCatalogTests`, `SwiftSourceTests`, `CopyAuditTests` |
| 5. The selected tab's icon and label use the accent; VoiceOver reads each tab as its title with the system's tab traits; stock symbols | Screenshots `s1/` (accent on the selected tab, light and dark; the four symbols); `LedgerUITests/Tabs` (the tab bar's buttons, labelled by title, `isSelected` on the selected one only, after every tap). The accent is `.tint(LedgerColor.accent)` on the `TabView`; no test reads a pixel of the system bar |
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
- The check: add `Text("Hello")` to any file of `LedgerAppKit`, add a key to its catalog, or look up a key the
  catalog lacks, and run `--filter AppCopyTests`: `copy_followsTheStandard` names the file and the line.
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
8. **watchOS is unproven** for catalogs (no watch module has one). Recommend F18 repeats `AppCopyTests`' pair
   for `LedgerWatchAppKit` in its first slice and reports.
9. **A real push through the interface.** Nothing in S1's interface pushes a screen, so "a tab keeps its stack"
   is pinned on the router and on the hosted shell, and was seen once in the running app by the experiment
   under "Gate and coverage". Recommend S5's UI test (the gear opens Settings) adds "switch away and back" to
   its flow.
10. **A copy member that returns `Text`** (the conventions allow one where a line embeds a live view, such as
    S4's "Resume · m:ss"). The audit reads `String(localized:)` lookups only, so a `Text("Resume · \(timer)",
    bundle: .module)` in a copy file would be a finding. Recommend S4 looks up the word ("Resume") as a `String`
    and builds the `Text` from it, the " · " and `Text(timerInterval:)`, which the audit already accepts; extend
    `CopyAudit.copyFile` only if a real format with an embedded view turns up. Standards §7 says it this way.
11. **Tab identifiers.** A tab bar button's identifier is its symbol's name (`chart.bar`) and its label the
    title; the `Tabs` UI test finds tabs by label. Recommend F15, which centralises identifiers, gives each
    `Tab` one (`tab.today`) if it wants tests that survive a renamed tab.

### Inputs for F08's and F10's slices

**`MainRoot.swift`** (26 lines). Its body is `AppTabs(router:onTodayTitleLongPress:)` with the Debug sheet.
- F08 (root gate): branch around `AppTabs(…)` inside `body`, so that `MainRoot` stays in the tree and keeps the
  router (`@State`) while onboarding is shown; the tabs then appear with Today selected and empty stacks. Keep the
  Debug sheet on the tabs: the UI tests open it from `today.title`.
- F10 (cover): apply your exported modifier to `AppTabs(…)` here, after the Debug sheet. iOS-only API
  (`fullScreenCover`) needs `#if os(iOS)`: the package also builds for the Mac host, and `PreviewTests` render the
  shell there.
- Both: `AppRouter` is `@MainActor @Observable`, internal. `router.selectedTab = .program` selects a tab;
  `router.open(.settings, in: .today)` pushes. Map a feature's routes in `Routes+<Feature>.swift` as an
  extension of `AppRouter` (`func handle(_ route: XRoute)`), and pass `router.handle` as the feature root's
  synchronous `onRoute`.
- A new pushed screen: a case in `AppDestination` (`Routes.swift`), its line in `AppTabs.screen(for:)`, and, while
  it is a placeholder, its title in `AppCopy.title(of:)` and the catalog.

**Your own catalog** (the four steps under "The localization pattern as built"):
- `Package.swift`: add `resources: [.process("Resources")]` to your target's line
  (`.target(name: "FeatureOnboarding", dependencies: featureSpine, resources: […], swiftSettings: uiSettings)`).
  Do not touch `defaultLocalization`.
- Copy `LedgerAppKit/Resources/Localizable.xcstrings` for the layout, and `LedgerAppKitTests/Fixtures/
  Localizable.xcstrings` for a counted key's `variations`.
- Your copy file must be named `<Something>Copy.swift` (or `…Copy+<Area>.swift`), anywhere in the module.
- Counts and names go into a key as `Int` and `String` parameters of the member:
  `static func exercises(_ count: Int, locale: Locale) -> String { String(localized: "\(count) exercises",
  bundle: .module, locale: locale) }` looks up `%lld exercises`. A `Double`, a `Weight`, a formatted date: format
  it first and pass the `String`. A literal `%` in copy is `%%` in the catalog key.
- Expect the audit to flag, in files that are not copy files: a `Text("…")`, a string passed to a `LedgerDesign`
  component, a constant holding copy, an enum's display string. It does not flag
  `.accessibilityIdentifier("…")`, `identifier:` arguments, `systemImage:` / `systemName:`, log lines on a logger,
  literals without a letter (" · "), comments, or `*+Previews.swift`. For a file of literals no lifter sees, add
  it to your test's `exempting:` with the reason.
- Your tests: `LedgerTestSupport` is already linked by every test target. Use
  `StringCatalog.resourceBundle(ofModule:)`, not `Bundle.module`, for the built bundle.
- Previews that include the shell or any `NavigationStack` inside a `Tab` render in `PreviewTests` on the
  simulator and on the host (deviation 2).
