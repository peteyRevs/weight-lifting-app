# Ledger — Testing Strategy

Date: 2026-09-16. Companion to `docs/engineering-standards.md` §9 and
`docs/ci-cd.md`. Versions and runner facts come from
`docs/research/R3-tooling-ci.md` (R3). Anything marked **verify in F01** (or
F00/F06) is a fact we could not confirm on 2026-09-16 and must be proven in
that brief before the rest of the plan relies on it.

Frameworks: **Swift Testing** for every unit/integration/snapshot test (Xcode
26.6 / Swift 6.3.3, R3 §2), **swift-snapshot-testing 1.19.5** (R3 §2),
**XCUITest** for UI flows and `performAccessibilityAudit`. XCTest is used only
where Swift Testing has no equivalent: XCUITest and `XCTApplicationLaunchMetric`.

---

## 1. Goals and the test pyramid

Goals, in priority order:

1. A wrong prescription, a lost set, or a divergent phone/watch state is
   caught by a test before a human ever runs the app.
2. Every test is deterministic: same inputs, same result, on any Mac and on
   CI runners (`docs/ci-cd.md`). A flaky test is a P1 bug (standards §9).
3. The PR lane finishes in ≤ 25 min wall-clock; everything slower runs nightly.
4. Design fidelity is enforced mechanically (snapshots), not by eyeballing.

| Layer | Framework | Share | Count at launch (M4) | Lane |
|---|---|---|---|---|
| Domain unit + property | Swift Testing | ~55 % | ~550 tests, ~1,200 parameterized cases | PR |
| Persistence integration | Swift Testing + in-memory GRDB | ~15 % | ~150 | PR (performance suite: nightly) |
| Sync integration + property | Swift Testing + `FakeTransport` | ~10 % | ~90 tests, 200 seeds/PR | PR |
| Health | Swift Testing + `FakeHealthStore` | ~3 % | ~30 | PR |
| Design system snapshots | swift-snapshot-testing | ~5 % | ~50 tests → ~100 PNGs | PR |
| Feature stores + screen snapshots | Swift Testing | ~10 % | ~120 store tests + ~45 snapshot tests → ~170 PNGs | PR |
| UI flows (XCUITest) | XCTest | ~1.5 % | 2 smoke + 12 iOS + 4 watchOS flows | smoke: PR; all: nightly |
| Device protocol | manual, scripted | — | 14 scenarios | device lane, before M2 exit and every release |

≈ 1,000 automated tests. Proportions follow the 70/25/5 rule
(unit / integration+snapshot / UI). Parameterized tests count once.

---

## 2. Layer-by-layer approach

### 2.1 Domain (`LedgerDomainTests`) — target ≥ 95 % line coverage

- Pure functions, so tests are plain `@Test` functions with fixtures from
  `LedgerTestSupport.Fixtures`. No dependencies to inject except
  `Calendar`/`Locale`/`TimeZone` passed as arguments.
- **Parameterized tests** (`@Test(arguments:)`) for every rule table in spec
  §7. Arguments are `Sendable` structs with a `description` so failures name
  the row.
- **Property-style tests** for `WorkoutEngine` (ADR-004) use a seeded RNG
  (`SeededGenerator` in `LedgerTestSupport`) and run `LEDGER_PROPERTY_SEED_COUNT`
  seeds (PR: 200, nightly: 2,000): shuffle → same state (commutativity),
  apply twice → same state (idempotence), `replay(log) == fold(reduce)`.
- **Exit tests** (`#expect(processExitsWith:)`) run only on macOS, not on iOS
  simulators (R3 §2). Domain validates at construction with failable or
  throwing inits (standards §5), so at launch there is nothing to exit-test.
  If a `precondition` is ever added to Domain, its test goes in
  `LedgerDomainTests/ExitTests.swift` under `#if os(macOS)` and runs in the
  nightly `domain-macos` step (`docs/ci-cd.md` §3) — **verify in F01** that
  the package product scheme `LedgerDomain` carries `LedgerDomainTests` for a
  `platform=macOS` destination.

Concrete test names (file = suite = source type; see §6):

| Suite | Tests |
|---|---|
| `ProgressionRulesTests` | `linear_advancesByStepPerCompletedWeek`, `linear_missedWeekHoldsLoad`, `double_repsClimbThenLoadRisesAndRepsReset` (spec §7.2 ex.: 50×10, 50×11, 50×12, 52.5×10), `fixed_loadConstantAcrossBlock`, `deload_loadTimes085RoundedToStep_minusOneSet_minusTwoRPE` (Back Squat W8: 285 → 240 lb, 4×5 @ RPE 6), `deload_floorsAtOneSetAndRPE5`, `held_flagSetWhenPreviousWeekMissed`, `prescribe_kg_usesKgSteps` (2.5/1.25 kg), `prescribe_table` (parameterized over `ProgressionFixtures.rows`) |
| `OneRepMaxTests` | `brzycki_matchesFormula_forReps1Through12` (parameterized 1…12), `brzycki_195x5_is219lb`, `brzycki_returnsNil_above12Reps`, `brzycki_oneRep_returnsWeight`, `brzycki_isMonotonicInWeight` |
| `PlateMathTests` | `perSide_185lb_is45plus25`, `perSide_180lb_is45_2x10_2p5`, `perSide_250lb_is2x45_10_2p5`, `perSide_belowSmallestPlate_isNil`, `perSide_loadBelowBar_isNil`, `perSide_kg_20kgBar_usesKgInventory`, `perSide_inventoryWithout25s_fallsToSmallerPlates`, `perSide_neverExceedsInventoryCount` (property) |
| `SupersetRoundsTests` | `displayOrder_isRoundMajor_A1B1A2B2`, `dropRows_formTheirOwnFinalRound`, `isLastOfRound_trueOnlyForLastMember`, `groupRest_isMaxOfMemberRests`, `unequalSetCounts_shorterMemberLeavesLaterRounds`, `letters_AtoE` |
| `MissTrackingTests` (decision #5) | `workingSetShortOfTargetReps_marksWeekMissed`, `fewerWorkingSetsThanPrescribed_marksMissed`, `shortDropSet_doesNotMarkMissed`, `shortAddedSet_doesNotMarkMissed`, `deloadWeek_neverMarksMissed`, `successfulWeek_removesPriorMiss`, `update_isIdempotent` |
| `WeekCalendarTests` (decision #18) | `weekIndex_fromStartDate` (parameterized incl. year end and DST in `Europe/Berlin` and `America/New_York`), `weekStart_respectsLocaleFirstWeekday`, `weekStart_settingsOverrideWins`, `dayIsOffSchedule_whenNoTemplateForWeekday`, `skippedWholeWeek_isMissForEverySlot`, `blockEnd_isDetectedOnLastWeekPlusOne` |
| `TimeEstimateTests` (decision #14) | `minutes_solo_isSumOf42PlusRestPerSet`, `minutes_superset_countsRestOncePerRound`, `minutes_dropSetCounted` |
| `SessionBuilderTests` | `build_appliesPrescriptionToEverySet`, `build_appendsDropSetAtMinus15PercentRoundedToStep`, `build_snapshotsSlotFieldsSoTemplateEditsDoNotLeak`, `build_lastPerformanceLineFromHistory`, `build_resumesSameWeekAndDay` |
| `PersonalRecordsTests` (decision #3) | `detect_newBestE1RM`, `detect_newBestWeightAtSameOrMoreReps`, `detect_none_whenBelowHistory`, `detect_ignoresE1RMAbove12Reps` |
| `WorkoutEngineTests` | one suite per event: `setLogged_marksDoneAndAdvancesCursor`, `setLogged_lastOfRound_startsGroupRest`, `setUnlogged_neverMovesCursorOrStopsRest`, `restExtended_addsToEndsAt`, `restExtendedAtZero_startsThirtySecondRest` (decision #7), `finished_ignoresLaterEvents`, `effects_setLogged_emitsHapticPersistTransmit` |
| `WorkoutEngineLawsTests` | `replay_isOrderInvariant(seed:)`, `reduce_isIdempotentForDuplicates(seed:)`, `replay_equalsSequentialReduce(seed:)`, `setTargetChanged_lastWriterWinsPerField`, `setAdded_idempotentBySetID`, `restEndsAt_independentOfReceiptTime` |
| `WeightTests` | `pounds_toGrams_exact`, `roundedToStep_table`, `lbKgRoundTrip_displayStable`, `comparable_ordersByGrams` |
| `ExerciseCatalogTests` | `decodes_everyEntry_uniqueIDs_knownEnums_alternativesResolve`, `count_isAtLeast200` |

### 2.2 Persistence (`LedgerPersistenceTests`) — target ≥ 90 %

- Every test opens `try DatabaseQueue()` (in-memory) via
  `TestDatabase.make()` in `LedgerTestSupport`, runs `Migrations.migrator`, and
  seeds with builders. One queue per test; suites are structs, so parallel by
  default.
- **Migration tests** (`MigrationTests`):
  `migrate_fromEmpty_appliesAllInOrder`;
  `migrate_fromEachPriorVersion_toLatest` parameterized over
  `LedgerPersistenceTests/Fixtures/schema-v001.sql … schema-vNNN.sql`.
  Each fixture is the `sqlite3 .dump` of the schema at the merge of that
  migration **plus sample rows**, produced by `scripts/dump-schema.sh` and
  committed in the same PR as the migration. The test loads the dump, runs the
  migrator, asserts `appliedMigrations == Migrations.all`, `PRAGMA
  foreign_key_check` returns nothing, and every fixture row is still readable
  through the repositories. `migrations_areAppendOnly` compares
  `Migrations.all.map(\.id)` to the committed list in
  `Fixtures/migrations.lock`; reordering or renaming a merged migration fails.
- **Repository contract tests**: one generic suite per protocol
  (`WorkoutRepositoryContract`, `ProgramRepositoryContract`, …) executed
  against the GRDB implementation *and* against the in-memory fake in
  `LedgerTestSupport`, so fakes cannot drift from the real semantics.
  Examples: `save_thenFetchByID_roundTrips`, `softDelete_hidesFromListsKeepsRow`,
  `observeWorkouts_emitsOnInsertAndUpdate`, `eventStore_gapSince_returnsOnlyHigherSeq`,
  `eventStore_compactsAfterFinishCommit`.
- **Performance tests** (`StatsQueriesPerformanceTests`, tag `.performance`,
  nightly only): seed via `Seed.largeHistory(sets: 20_000, seed: 42)`
  (~600 workouts over 2 years); for each `StatsQueries` method — last
  performance, best set, e1RM by week, weekly volume + delta, sessions this
  week, PR history — run once to warm up, then `ContinuousClock.measure` five
  times; `#expect(median < .milliseconds(50))` (architecture §15). Budgets
  live in `PerformanceBudget.swift` next to the tests, never inline.

### 2.3 Sync (`LedgerSyncTests`) — target ≥ 90 %

- `SessionPair.make(seed:)` (in `LedgerTestSupport`) builds two
  `WorkoutSessionActor`s (`DeviceID.phone`, `DeviceID.watch`) connected through
  a `FakeTransport` actor. `FakeTransport.Link` is programmable:
  `.deliverImmediately`, `.hold` (queue), `partition()`, `heal()`,
  `reorder(seed:)`, `duplicate(every:)`, `drop(where:)`, `hangSend()` (for the
  watchdog). Time is a `TestClock`; nothing sleeps.
- Scenario tests: `partition_thenHeal_bothConverge`,
  `reorderedDelivery_converges`, `duplicateDelivery_isIdempotent`,
  `droppedEnvelope_isReplayedViaHighestSeqExchange`,
  `finishOnBothWhilePartitioned_yieldsOneCanonicalWorkout`,
  `watchdog_fallsBackToWatchConnectivity_whenMirroringSendHangs`,
  `wcBoostDuplicates_areDedupedByDeviceSeq`,
  `remoteEnvelopesBeforeLocalStart_areBuffered`,
  `programPush_applicationContext_latestWins`,
  `finishedWorkoutPullBack_userInfo_preservesOrder`.
- Property test `randomIntentsAndFaults_converge(seed:)`: random intents on
  both actors interleaved with random link faults; after `heal()` both states
  are equal and equal `WorkoutEngine.replay(union of logs)`.

### 2.4 Health (`LedgerHealthTests`) — target ≥ 80 %

- `HealthStoreContract` runs against `FakeHealthStore` always and against
  `LiveHealthStore` only in the device lane: authorization state machine,
  session states `prepared → running → ended`, `save` idempotent by
  `WorkoutID`, HR stream ordered, `errorAnotherWorkoutSessionStarted` maps to
  `.anotherSessionRunning`.
- Coordinator logic through the fake: `start_waitsForPrepared_beforeMirroring`,
  `recovery_resumesUnfinishedLog`, `save_includesVolumeMetadataAndHR`,
  `phoneOnly_savesViaWorkoutBuilder_withoutHR`.
- Simulator reality (ADR-005, R3 §2): **can run** — authorization prompts,
  `HKWorkoutBuilder` saves on the iOS simulator, `HKWorkoutSession` on the
  watch simulator; **cannot run** — mirroring channel, `startWatchApp`,
  WatchConnectivity `transferUserInfo`/`transferFile`, real heart rate,
  recovery after process kill on a real wrist. Those are device-lane only (§2.8).

### 2.5 Design system (`LedgerDesignTests`) — target ≥ 60 %

- swift-snapshot-testing 1.19.5 with Swift Testing: `@Suite(.tags(.design,
  .snapshot), .snapshots(record: SnapshotConfig.record))` and
  `assertSnapshot(of:as:named:)`. Failures attach diff images to the xcresult
  (1.19.x native attachments, R3 §2) and also write to the
  `SNAPSHOT_ARTIFACTS` directory (set by the test plan).
- Matrix, phone: `{light, dark} × {.large, .xLarge, .accessibility3}` = 6
  images per component/screen state (`SnapshotAppearance.phoneMatrix`; F06
  criterion 3 chose `.xLarge` over `.xxxLarge`), rendered at 1× with
  `assertPhoneSnapshot(of:_:)` (components) or `.device(config:)` (screens).
  The helper wraps `.image(layout: .sizeThatFits, traits:)` and applies
  `snapshotAppearance(_:)`: the text size and scheme also go into SwiftUI's
  environment (the library measures before it applies traits), and the view
  takes its own height (the library proposes a zero size, which cuts
  wrapping text to one line with "…"; F06 review S1). 1.19.6's newest `ViewImageConfig` is
  `.iPhone13ProMax`; there is no iPhone 17 config (checked in F06), so
  components render at `SnapshotConfig.phoneWidth` (402 pt). Watch: always
  dark, fixed sizes 42 mm 187×223, 46 mm 208×248, 49 mm 205×251 pt
  (`WatchSize`) — one watch simulator renders all three. swift-snapshot-testing
  1.19.6 has no image strategy on watchOS (its view and `UIImage` strategies
  are `#if os(iOS) || os(tvOS)`), so watch snapshots go through
  `RenderedImage.render` (`ImageRenderer`, 1×) and the `.png` strategy in
  `LedgerSnapshotTesting`, which applies the same precision and ΔE threshold.
  It measures ΔE as CIE76, which is never smaller than the CIE94 that Core
  Image measures for the library on iOS, so it is at least as strict. Watch
  components go through `assertWatchSnapshot(of:_:)` over
  `WatchAppearance.matrix`: each size at its default text size (`.large` at
  42 mm, `.xLarge` at 46 and 49 mm) and at `.accessibility3`, the largest
  watch text size (HIG, Typography), at the case's width and the view's own
  height = 6 images per component state.
- Precision: `precision: 0.995, perceptualPrecision: 0.98`, set once in
  `SnapshotConfig` and never overridden per test.
- Storage: PNGs in `__Snapshots__/` next to the test file, committed to git
  (~270 images ≈ 15 MB at launch; move to Git LFS if `__Snapshots__` exceeds
  300 MB). Record policy: swift-snapshot-testing's default `.missing` (a
  missing reference is written and the test fails, so CI cannot pass on a
  reference it recorded itself); `scripts/check.sh --record-snapshots` runs
  both plans with `TEST_RUNNER_SNAPSHOT_TESTING_RECORD=all` on the pinned
  simulators (§7), prints `git status --short -- '**/__Snapshots__'` and
  fails; a second, normal run proves the references. References recorded on any other
  device/OS are rejected in review.
- Accessibility (iOS): `View.accessibilityElements(_:)` in `LedgerSnapshotTesting` hosts a view
  in a window at a matrix appearance and returns its elements as UIKit hands them to VoiceOver
  (label, value, traits, frame); `withAccessibilityElements(_:_:)` gives the live elements, to
  activate or adjust them. SwiftUI builds that tree only for an assistive technology, so the
  helper turns on UIKit's accessibility automation (`_AXSSetAutomationEnabled`, private,
  test-only, as KIF and AccessibilitySnapshot do) while it reads. A button's accessibility frame
  is its tappable area, which is how `ComponentAccessibilityTests` checks the 44 pt target.
- Review policy: a PR that changes any PNG lists them under "Screenshots" in
  the PR template with the reason; the reviewer inspects GitHub's image diff
  against the prototype screen label (workflow review point 4); more than 20
  changed PNGs require a dedicated `chore(snapshots):` PR; re-recording to
  make CI green without a stated visual cause is a blocking finding.

### 2.6 Features (`Feature*Tests`, `WatchFeatureWorkoutTests`) — target ≥ 70 %

- Store tests are `@MainActor` suites using `withDependencies` from
  swift-dependencies 1.17.x: `date = .constant(Fixtures.now)`,
  `uuid = .incrementing`, `continuousClock = TestClock`, repositories = the
  in-memory fakes, `healthStore = FakeHealthStore()`. A store constructed
  outside `withDependencies` hits `testValue` and fails loudly (standards §3).
- Examples: `TodayStoreTests.load_scheduledNotLogged_showsUpNextCard`,
  `load_loggedToday_showsLoggedCard`, `load_unscheduled_showsRestDayCard`,
  `ActiveWorkoutStoreTests.logSet_lastOfRound_startsGroupRest`,
  `minimize_keepsElapsedRunning`, `SwapStoreTests.swap_bringsOwnLastLoadWhenHistoryExists`,
  `ProgramBuilderStoreTests.addWeek_copiesPreviousSchedule_notDeload`,
  `SettingsStoreTests.changeUnits_persistsAndReformatsTiles`,
  `WatchWorkoutStoreTests.crownDetent_bumpsWeightByExerciseStep`.
- Snapshot tests: one per screen **state** (the `#Preview` list is the
  contract): Today {upNext, logged, restDay, loading, empty}, Active workout
  {solo, superset, rest, swapSheet}, Receipt, Builder, Day editor, Library,
  Exercise history, Workout list/detail, Settings, Onboarding ×3, Watch
  {idle, ready, rest, list, end, summary}. Same matrix as §2.5.

### 2.7 UI (`LedgerUITests`, `LedgerWatchUITests`)

- Critical flows, iOS: `Smoke.launchesToToday`, `Onboarding.threeStepsGenerateProgram`,
  `Workout.startLogThreeSetsRestFinishReceipt`, `Workout.swapExercise`,
  `Workout.minimizeAndResume`, `Builder.addDayAddExerciseChangeProgression`,
  `Library.searchOpensHistoryChart`, `History.editThenDeleteWorkout`,
  `Settings.switchUnitsToKg`, `Settings.exportCSV`, `Onboarding.dynamicTypeXL`,
  `Accessibility.auditEveryTabRoot`, `Launch.coldLaunchUnder600ms`
  (`XCTApplicationLaunchMetric`, nightly). watchOS: `Smoke.launchesToIdle`,
  `Watch.startFromIdleToSetReady`, `Watch.doneSetRestSkipReady`,
  `Watch.listEndSaveSummaryDone`, `Watch.accessibilityAuditEveryMode`.
- `performAccessibilityAudit(for: .all)` (iOS 17+ / watchOS 10+, R3 §2) runs
  on every tab root and watch mode; known false positives are excluded in
  the issue handler with a comment naming the element and the radar/issue.
- Identifiers: `.accessibilityIdentifier` uses `<feature>.<screen>.<element>[.<index>]`
  in lowerCamelCase, e.g. `today.upNext.startButton`, `workout.active.setRow.2`,
  `watch.ready.doneSetButton`. Each feature exposes `public enum <Feature>ID:
  String`; the UI test targets link `LedgerAppKit` / `LedgerWatchAppKit` and use
  the same enums, so a rename breaks compilation, not a run (**verify in F01**
  that XCUITest bundles link the umbrella products cleanly).
- UI tests launch with `-LEDGER_UITEST 1` and a fixed seed so the app opens
  the in-memory database seeded by `LedgerTestSupport.Seed.uiTest`.

### 2.8 Device protocol (manual, scripted) — `tasks/features/F20-device-protocol/`

Physical iPhone + Apple Watch, both on the build under test. Required before
the M2 exit and before every release tag (workflow gate G6). Scenarios:

| # | Scenario | Pass when |
|---|---|---|
| D1 | Phone "Start workout" | watch app launches into set-ready ≤ 5 s (`startWatchApp`) |
| D2 | Wrist start, phone locked in pocket | phone shows the live workout on next unlock |
| D3 | Log set on watch (reachable) | phone reflects ≤ 1 s |
| D4 | Log set on phone (reachable) | watch reflects ≤ 1 s |
| D5 | Airplane mode on phone mid-workout; 3 sets on watch, 2 on phone; reconnect | both show the union, cursor and rest agree |
| D6 | Force-quit watch app mid-workout, relaunch | recovery resumes with all sets |
| D7 | Force-quit phone app mid-workout, relaunch | mirroring handler fires; state resumes |
| D8 | Finish on watch while partitioned; reconnect | one workout in phone History with avg/max HR |
| D9 | Finish on phone while partitioned; watch reconnects | watch shows summary, no duplicate workout |
| D10 | Start rest on phone; "+30s" on watch | both countdowns agree within 1 s |
| D11 | Rest reaches zero with phone backgrounded | watch haptic fires; `watchBuzz` off → no haptic |
| D12 | Apple Workout running, then start Ledger | "another session" state shown, nothing lost |
| D13 | Edit program on phone | watch idle shows the new day ≤ 30 s (`updateApplicationContext`) |
| D14 | Full workout on watch with phone powered off; power on | workout appears in History, saved to Health (`transferUserInfo`) |

Recording: copy `runs/_TEMPLATE.md` to `runs/YYYY-MM-DD-b<buildNumber>.md`;
fill device models, OS versions, build number, pass/fail per scenario, notes,
and attach screenshots for failures. A run with any failure blocks the tag.

---

## 3. Determinism rules

1. Time, UUIDs, clocks come from `@Dependency(\.date)`, `\.uuid`,
   `\.continuousClock`; tests use `.constant(Fixtures.now)`
   (`2026-09-16T05:20:00Z`), `.incrementing`, and `TestClock`/`ImmediateClock`.
2. No `Task.sleep`, no `XCTWaiter`, no polling. Await the `AsyncStream`, advance
   the `TestClock`. Every async suite carries `.timeLimit(.minutes(1))`.
3. No network, no real HealthKit, no WatchConnectivity, no file system outside
   `FileManager.temporaryDirectory`, no `UserDefaults.standard`.
4. Locale/calendar/time zone are fixed: test plans set `TZ=UTC`, language `en`,
   region `US`; `Fixtures.calendar` is Gregorian, UTC, `en_US`, `firstWeekday = 1`.
   Tests about other zones pass them explicitly.
5. Randomness is seeded (`SeededGenerator(seed:)`); a failing seed is printed
   and added as a fixed regression case.
6. Builders in `LedgerTestSupport` (`Fixtures.exercise(.benchPress)`,
   `.program(weeks:daysPerWeek:)`, `.slot(...)`, `.workoutState(...)`,
   `EnvelopeBuilder(device:)` with auto-incrementing `seq`,
   `Seed.largeHistory(sets:seed:)`) are the only way to construct fixtures.
7. Test execution order is random (`testExecutionOrdering: random` in every plan).

---

## 4. Coverage

- Measured from the result bundles: `xcrun xccov view --report --json
  <bundle>.xcresult` (verified on 26.6, R3 §2). `scripts/coverage-gate.sh
  <ios.xcresult> <watchos.xcresult>` reads both, normalises target names
  (strips `.o`/`.framework`/`.app`), takes the higher value when a target
  appears in both, recomputes per-target coverage from `files[]` after
  exclusions, and compares with `scripts/coverage-thresholds.json`.
  PR CI's `check.sh --ios-only` passes `--ios-only` and the iOS bundle alone
  (Pete, 2026-09-30). Only a required module listed in `watchOnly` may then be
  unmeasured; without the flag, `watchOnly` changes nothing.
- Thresholds (line coverage): `LedgerDomain 95`, `LedgerPersistence 90`,
  `LedgerSync 90`, `LedgerHealth 80`, `LedgerActivityKit 70`, every
  `Feature*`/`WatchFeatureWorkout` 70, `LedgerDesign 60`, overall 80 (sum of
  covered / executable lines across included targets). Thresholds are only
  ever raised; raise when a module beats its threshold by ≥ 3 points for two weeks.
- Exclusions: `LedgerTestSupport`, `*Tests`, `*UITests`, app shells (`Ledger`,
  `LedgerWatch`, `LedgerWidgets`, `LedgerWatchWidgets`), umbrella targets,
  files matching `*+Previews.swift` (all `#Preview` bodies live there),
  `Generated/`.
- Gate failure: the script prints a Markdown table (also to
  `$GITHUB_STEP_SUMMARY`), exits 1, the `test-ios` job fails, `pr-gate` fails,
  the PR cannot merge. "Coverage did not decrease" (PR template) is checked by
  the reviewer against the latest `main` job summary.

---

## 5. Flaky-test policy

- Definition: fails, then passes with no code change. CI never uses
  `-retry-tests-on-failure`; flakes must surface.
- On first flake: rerun once (`gh run rerun --failed`), open a P1 issue titled
  `flaky: <Target>/<Suite>/<test>` with the xcresult artifact link.
- Within 1 working day: quarantine by adding
  `.quarantined(issue: "#123", until: "2026-10-01")` (custom trait in
  `LedgerTestSupport`). It tags `.quarantined`, disables the test only when
  `LEDGER_TEST_LANE == "pr"`, still runs nightly, and **fails the test after
  `until`** so quarantine cannot be forgotten. Never `.disabled` (standards §11).
- Within 5 working days: root-cause fix (usually an un-injected clock or
  shared fixture); delete the trait in the fixing PR. Retries, sleeps, and
  widened tolerances are not fixes.

---

## 6. Naming, organisation, tags, lanes

- One test target per source target (`LedgerKit/Tests/<Target>Tests`), one
  suite per source type, file name = suite name (`ProgressionRulesTests.swift`).
- `@Suite("ProgressionRules") struct ProgressionRulesTests`; test functions read
  `subject_condition_expectation` with no `test` prefix; `@Test("…")` display
  names are full sentences. (The brief template's `test_…` examples predate
  this convention; use the form above.)
- Tags in `LedgerTestSupport/Tags.swift`: `.domain, .persistence, .sync,
  .health, .design, .feature, .snapshot, .performance, .slow, .ui, .device,
  .quarantined`. Every suite carries its layer tag; add `.slow` (> 2 s),
  `.performance`, or `.device` where applicable.
- Lanes are selected by **test plan** (target/suite granularity) and confirmed
  by the `LEDGER_TEST_LANE` env var read by traits: `.performance`/`.slow`
  suites are listed under `skippedTests` in the PR plans; `.device` suites are
  `.enabled(if: TestLane.isDevice)`. A single `.slow` test inside a PR suite
  carries `.enabled(if: TestLane.runsSlowTests)` instead, which is true only
  when `LEDGER_TEST_LANE` is `nightly` (F06: LedgerDesignTests' full
  bare-font matrix; the PR lane runs a representative subset).

| Lane | Plans | Runs |
|---|---|---|
| PR | `PR`, `PR-Watch` | all unit/integration/snapshot suites minus `.slow`/`.performance`; `LedgerUITests/Smoke`, `LedgerWatchUITests/Smoke` |
| Nightly | `Nightly`, `Nightly-Watch` | everything except `.device`; full XCUITest; performance; 2,000 property seeds |
| Device | `Device`, `Device-Watch` | `.device` suites (`HealthStoreContract` against `LiveHealthStore`) plus the §2.8 manual checklist |

---

## 7. `scripts/check.sh` contract (written in F00)

Runs from the repo root, `set -euo pipefail`, stops at the first failure,
prints a per-step timing table. Flags: `--fast` (skip step 4 and the UI
smoke), `--lint-only`, `--record-snapshots` (delegates to
`scripts/snapshots-update.sh`). Simulator names below are the Xcode 26.6
defaults for the 26.5 runtimes — **verify in F00** with `xcrun simctl list`.

```bash
# 0 tools (fails if mise or pinned versions are missing)           ~2 s
mise install --quiet && mise x -- swiftformat --version && mise x -- swiftlint version
# 1 format
mise x -- swiftformat --lint --swift-version 6.3 LedgerKit Apps        ~5 s
# 2 lint
mise x -- swiftlint lint --strict --quiet --config .swiftlint.yml     ~20 s
# 3 iOS build + PR plan (package tests, feature snapshots, UI smoke)  ~5–7 min warm
rm -rf .derivedData/Results/PR-iOS.xcresult
xcodebuild test -project Ledger.xcodeproj -scheme Ledger -testPlan PR \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -derivedDataPath .derivedData -clonedSourcePackagesDirPath .derivedData/SourcePackages \
  -resultBundlePath .derivedData/Results/PR-iOS.xcresult \
  -parallel-testing-enabled YES -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 60 -quiet | mise x -- xcbeautify
# 4 watchOS build + PR-Watch plan                                     ~3–4 min warm
rm -rf .derivedData/Results/PR-watchOS.xcresult
xcodebuild test -project Ledger.xcodeproj -scheme LedgerWatch -testPlan PR-Watch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.5' \
  -derivedDataPath .derivedData -clonedSourcePackagesDirPath .derivedData/SourcePackages \
  -resultBundlePath .derivedData/Results/PR-watchOS.xcresult \
  -parallel-testing-enabled YES -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 60 -quiet | mise x -- xcbeautify
# 5 coverage gate                                                     ~10 s
scripts/coverage-gate.sh .derivedData/Results/PR-iOS.xcresult .derivedData/Results/PR-watchOS.xcresult
```

Expected runtime on an M-series Mac: ~9–12 min warm, ~15 min cold;
`--fast` ~5 min. CI runs the identical commands (`docs/ci-cd.md` §2) with
`--renderer github-actions` on xcbeautify. `.derivedData/` is git-ignored and
shared between local and CI so cache keys match.

---

## 8. Test plans (`TestPlans/*.xctestplan`, attached to the schemes in F00)

Common `defaultOptions`: `codeCoverage: true` with the coverage `targets`
list from §4, `testExecutionOrdering: random`, `testTimeoutsEnabled: true`,
`maximumTestExecutionTimeAllowance: 60` (nightly: 600), `language: en`,
`region: US`, environment `TZ=UTC`, `LEDGER_TEST_LANE`,
`LEDGER_PROPERTY_SEED_COUNT`, `SNAPSHOT_ARTIFACTS=$(PROJECT_DIR)/.derivedData/SnapshotArtifacts`
(**verify in F01** that `$(PROJECT_DIR)` expands in test-plan environments; else pass
`TEST_RUNNER_SNAPSHOT_ARTIFACTS` on the xcodebuild command line).

| Plan | Scheme | Test targets | Skipped | Env |
|---|---|---|---|---|
| `PR` | `Ledger` | LedgerDomainTests, LedgerPersistenceTests, LedgerSyncTests, LedgerHealthTests, LedgerDesignTests, LedgerActivityKitTests, Feature*Tests, LedgerUITests | `StatsQueriesPerformanceTests`, every `.slow` suite, `LedgerUITests/*` except `Smoke` | lane=pr, seeds=200 |
| `PR-Watch` | `LedgerWatch` | LedgerDomainTests, LedgerDesignTests, WatchFeatureWorkoutTests, LedgerWatchUITests | `LedgerWatchUITests/*` except `Smoke` | lane=pr, seeds=200 |
| `Nightly` | `Ledger` | as `PR` | nothing | lane=nightly, seeds=2000 |
| `Nightly-Watch` | `LedgerWatch` | as `PR-Watch` + LedgerSyncTests | nothing | lane=nightly, seeds=2000 |
| `Device` | `Ledger` | LedgerHealthTests | all but `HealthStoreContract` | lane=device |
| `Device-Watch` | `LedgerWatch` | LedgerHealthTests | all but `HealthStoreContract` | lane=device |

`PR.xctestplan` skeleton (the others differ only in the table above):

```json
{
  "version": 1,
  "configurations": [{ "id": "8D6D0F3C-0000-4000-8000-000000000001", "name": "Default", "options": {} }],
  "defaultOptions": {
    "codeCoverage": { "targets": [ { "containerPath": "container:LedgerKit", "identifier": "LedgerDomain", "name": "LedgerDomain" } ] },
    "environmentVariableEntries": [
      { "key": "TZ", "value": "UTC" },
      { "key": "LEDGER_TEST_LANE", "value": "pr" },
      { "key": "LEDGER_PROPERTY_SEED_COUNT", "value": "200" },
      { "key": "SNAPSHOT_ARTIFACTS", "value": "$(PROJECT_DIR)/.derivedData/SnapshotArtifacts" }
    ],
    "language": "en", "region": "US",
    "testExecutionOrdering": "random",
    "testTimeoutsEnabled": true, "maximumTestExecutionTimeAllowance": 60
  },
  "testTargets": [
    { "target": { "containerPath": "container:LedgerKit", "identifier": "LedgerDomainTests", "name": "LedgerDomainTests" } },
    { "target": { "containerPath": "container:LedgerKit", "identifier": "LedgerPersistenceTests", "name": "LedgerPersistenceTests" },
      "skippedTests": [ "StatsQueriesPerformanceTests" ] },
    { "target": { "containerPath": "container:Ledger.xcodeproj", "identifier": "LedgerUITests", "name": "LedgerUITests" },
      "selectedTests": [ "Smoke" ] }
  ]
}
```

Package test targets are added to app-scheme test plans through Xcode's
"container:LedgerKit" reference (**verify in F00**; if Xcode 26.6 refuses,
F00 adds a `LedgerKit` aggregate scheme and `check.sh` runs it as a third
`xcodebuild test` invocation with the iOS destination).
