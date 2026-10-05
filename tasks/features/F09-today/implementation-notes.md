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
