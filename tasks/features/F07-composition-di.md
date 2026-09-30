# F07 — Composition roots, dependency injection, test support

| | |
|---|---|
| Milestone | M0 |
| Status | ready |
| Depends on | F05, F06 (and F03 for seeding) |
| Branch | `feat/F07-composition-di` |
| Design refs | none |
| Spec refs | `docs/architecture.md` §3, §4, §13; ADR-005 (launch-time handler); R2 §4, §6 |

## Goal
Wire the app together once: every Domain protocol has a `@Dependency` key with live, test and preview values; both apps boot with a real database, seed the catalog, register the HealthKit mirroring handler synchronously at launch, activate WatchConnectivity, and show a placeholder Today; and `LedgerTestSupport` gives every later feature fakes and builders so stores are tested without I/O.

## User stories
- As a feature implementer, I write `@Dependency(\.workoutRepository) var repo` and get GRDB in the app, an in-memory repo in tests, and fixtures in previews.
- As the M0 exit reviewer, I launch both apps in the simulator and see "Today" on a real database.

## Scope
**In:** dependency keys, `LedgerAppKit.AppRoot` / `LedgerWatchAppKit.WatchRoot`, launch sequences, `LedgerTestSupport` contents, placeholder Today screens, debug menu with `DesignGallery` and Diagnostics.
**Out:** real HealthKit/transport implementations (F16/F17/F19) — this brief binds `liveValue` to `Unimplemented*` stubs that log and no-op, clearly marked.

## Touches
- `LedgerKit/Sources/LedgerDependencies/{Keys/*.swift, Unimplemented/*.swift}` (target created in F00)
- `LedgerKit/Sources/LedgerAppKit/{AppRoot.swift, AppComposition.swift, Launch.swift, DebugMenu.swift}`
- `LedgerKit/Sources/LedgerWatchAppKit/{WatchRoot.swift, WatchComposition.swift, WatchAppDelegate.swift}`
- `Apps/Ledger/LedgerApp.swift`, `Apps/LedgerWatch/LedgerWatchApp.swift` (call the roots only)
- `LedgerKit/Sources/LedgerTestSupport/{InMemory/*, Fakes/*, Fixtures/*, Snapshots/*, WithTestDependencies.swift}`
- `LedgerKit/Tests/{LedgerDependenciesTests,LedgerAppKitTests,LedgerWatchAppKitTests}/**`

## Domain changes
None. Dependency keys (swift-dependencies 1.17.x), all in `LedgerDependencies`:
```swift
extension DependencyValues {
    var date: DateGenerator; var uuid: UUIDGenerator; var continuousClock: any Clock<Duration>; var calendar: Calendar; var locale: Locale   // from the library
    var deviceID: DeviceID                          // stable per install (Keychain-free: stored in `device` table)
    var exerciseRepository: any ExerciseRepository; var programRepository: any ProgramRepository; var workoutRepository: any WorkoutRepository
    var workoutEventStore: any WorkoutEventStore; var settingsRepository: any SettingsRepository; var statsQueries: any StatsQueries
    var healthStore: any HealthStore; var liveWorkoutTransport: any LiveWorkoutTransport; var companionTransport: any CompanionTransport
    var haptics: any HapticsClient; var notifications: any NotificationsClient; var liveActivities: any LiveActivitiesClient
    var logger: LedgerLogger
}
```
Rules: `liveValue` for repositories is built from one shared `DatabaseQueue` created in `AppComposition`; `testValue` for every key is `unimplemented(...)` (fails the test with the key name); `previewValue` uses `LedgerTestSupport` in-memory implementations seeded with fixtures.

`LedgerTestSupport`:
- `InMemoryExerciseRepository`, `InMemoryProgramRepository`, `InMemoryWorkoutRepository`, `InMemoryWorkoutEventStore`, `InMemorySettingsRepository`, `InMemoryStatsQueries` (actors over dictionaries) — or GRDB in-memory wrappers where simpler; both must satisfy the F05 contract tests (shared `RepositoryContractTests` parameterized over implementations).
- `FakeHealthStore` (scriptable auth state, HR sample stream, recorded calls), `FakeLiveWorkoutTransport` (in-memory bus connecting N endpoints with configurable delay/loss/partition), `FakeCompanionTransport`, `FakeHaptics`, `FakeNotifications`, `FakeLiveActivities` (all record calls).
- `Fixtures`: `.benchPress`, `.upperA` day, `.seedProgram` (spec §6.4), `.seedSession` (§6.3), `.history(weeks:)`, `.settingsLb/.settingsKg`.
- `Snapshots`: `assertLedgerSnapshot(of:named:devices:themes:typeSizes:)` wrapper encoding the F06 matrix.
- `withTestDependencies(_ configure: (inout DependencyValues) -> Void, operation:)` that starts from `previewValue`s.

Launch sequence (iOS, in `AppComposition.boot()` called from `LedgerApp.init`): (1) assign `HKHealthStore().workoutSessionMirroringStartHandler` **synchronously** to a forwarder that hands sessions to `liveWorkoutTransport` (F17 fills it; F07 stores the session and logs); (2) open DB + migrate; (3) seed catalog if needed; (4) load settings; (5) activate `WCSession` delegate; (6) render `AppRoot`. Watch: `WKApplicationDelegate` with `applicationDidFinishLaunching` doing (2)–(5), `handle(_ workoutConfiguration:)` and `handleActiveWorkoutRecovery()` forwarding to `healthStore` (stubs in F07).

## Acceptance criteria
1. Given the iOS app launched in the simulator, when Today renders, then the database file exists in Application Support, the catalog is seeded (≥ 200 rows), and launch-to-first-frame < 600 ms (measured by a `XCTApplicationLaunchMetric` test in `LedgerUITests/LaunchPerformance`, nightly).
2. Given the watch app launched, then the same holds with its own database (`LedgerWatchUITests`).
3. Given a store test using `withTestDependencies`, when it touches a key not configured, then the test fails with a message naming the key (`test_unimplementedDependencyFailsLoudly`).
4. Given `RepositoryContractTests`, when run against GRDB in-memory and the `InMemory*` implementations, then all pass for both.
5. Given `FakeLiveWorkoutTransport` with two endpoints and loss = 0.3, when 100 envelopes are sent, then the receiver gets ≥ 70 and never a duplicate unless configured.
6. Given the iOS launch, when inspected with a breakpoint/log, then `workoutSessionMirroringStartHandler` is assigned before any `await` (asserted by a unit test on `Launch.order` recording).
7. Given the debug menu (Debug builds only, shake or long-press on the title), then `DesignGallery` and a Diagnostics screen (DB path, row counts, device id, health auth state) open.
8. Given `previewValue`s, when every `#Preview` in the package renders (a `PreviewSmokeTests` suite instantiating each preview provider), then none crash.

## Test plan
- Unit: `DependencyKeysTests` (3, 8), `LaunchOrderTests` (6), `FakeTransportTests` (5), `FixturesTests` (fixtures satisfy validation).
- Integration: `RepositoryContractTests` (4), `AppCompositionTests` (boots on a temp directory, seeds once).
- UI: `LaunchTests` on both platforms show "Today" (replace F00 placeholder assertion), `LaunchPerformance` (1, nightly).
- Snapshot: Today placeholder light/dark (temporary; F09 replaces).

## Non-functional
- No `Task.detached`; boot uses structured concurrency from `.task` on the root view where async is needed, but the handler assignment and DB open are synchronous.
- `LedgerTestSupport` compiles for iOS, watchOS and macOS (host `swift test`).

## Risks / unknowns
- swift-dependencies under Swift 6.4 (F32) resolves its default manifest, so IssueReporting is `swift-issue-reporting` 2.x, not `xctest-dynamic-overlay` 1.x: use its `reportIssue` and `unimplemented`.
- Default MainActor isolation in `LedgerDependencies` (nonisolated target) vs `MainActor` UI clients — keep clients `Sendable`.

## Definition of Done
Inherits `docs/engineering-standards.md` §12, plus:
- [ ] M0 exit criteria in `tasks/todo.md` demonstrated with screenshots of both apps.
- [ ] `docs/architecture.md` §13 updated if any key was renamed.

---
_Filled in by agents during delivery:_
- `F07-composition-di/implementation-notes.md`
- `F07-composition-di/test-findings.md`
- `F07-composition-di/review.md`

## Inputs from F05 (2026-09-30)
- `LedgerDatabase.open(at:protection:)` is synchronous: call it off the main actor. It took 4.6 ms on the
  watch simulator. Give the database a directory of its own, e.g. `Application Support/Database/ledger.sqlite`.
- A settings row this app cannot read makes `SettingsRepository.load()` throw, and `observe()` then ends
  without a value (review N2). The row may be in a later payload version (`unknownPayloadVersion`), hold a
  damaged column (`malformedColumn`) or invalid JSON (`DecodingError`). Fall back to `Settings.default` in
  memory, but never save it over the row: a later version, or the lifter, may still read it. Subscribe
  again after the lifter's next deliberate save.
- Seed the catalog before any program is saved (F05 S2): `slot.exercise_id` is a foreign key, so a slot naming an
  exercise the database lacks makes `ProgramRepository.save` throw a `DatabaseError` and store nothing.
  `seedIfNeeded(ExerciseCatalog.seed(), version: ExerciseCatalog.version)` is safe on every launch: it does
  nothing unless the version is higher than the applied one, then inserts every new catalog id (even one named
  like a custom exercise). 214 entries took 9.2 ms on the watch simulator (budget 300 ms), so it need not wait
  for the first frame.
- Criterion 4's `RepositoryContractTests` for exercises and programs exist: run `ExerciseRepositoryContract.clauses`
  and `ProgramRepositoryContract.clauses` (`LedgerTestSupport/Persistence`) against the `InMemory*` fakes, as the
  GRDB suites do. A program clause's repository must accept slots naming `ProgramRepositoryContract.exercises`.
