# F16 — HealthKit adapter (`LedgerHealth`)

| | |
|---|---|
| Milestone | M2 |
| Status | ready |
| Depends on | F04, F07 |
| Branch | `feat/F16-healthkit` |
| Design refs | `design/prototype/LedgerWatch.dc.html` → screen labels: `Watch — set ready` (HR · BPM row), `Watch — summary` (AVG BPM); `design/prototype/Ledger.dc.html` → `Settings` ("Apple Health" row) |
| Spec refs | `docs/product-spec.md` §4.3, §5.1 (`hr`), §9 (HealthKit gaps); `docs/product-decisions.md` #16, #20; `docs/architecture.md` §9; ADR-005; R1 §2.1–2.5, §3.1–3.4, §5.3–5.4 |

## Goal
After this ships, the watch runs a real `HKWorkoutSession` for every Ledger workout (heart rate on the wrist, workout saved to Apple Health with volume metadata), the phone can ask the watch to start, both apps recover a session after a crash, and every other feature talks to HealthKit only through a `HealthStore` protocol with a fake that is contract-tested against the live actor's behaviour.

## User stories
- As a lifter, I can see my live heart rate on the watch during a set so that I know when I have recovered.
- As a lifter, I can tap "Start workout" on my phone and have the watch app open with the session running so that I do not have to touch the watch to begin.
- As a lifter, I get the workout in Apple Health (rings credited, HR + active energy) so that Ledger integrates with the rest of my fitness data.
- As a lifter, if the watch app dies mid-workout, reopening it resumes the same HealthKit session so that HR history is not split.

## Scope
**In:** `HealthStore` protocol finalisation in `LedgerDomain`; `LiveHealthStore` actor in `LedgerHealth` for both platforms (`#if os(watchOS)` / `#if os(iOS)` sections); authorization; watch session + live builder + HR stream + end/save; phone mirroring-start handler, session retention, `startWatchApp(toHandle:)`, phone-only `HKWorkoutBuilder` save; recovery hooks on both; `errorAnotherWorkoutSessionStarted` surfaced as a typed event; `RemoteSessionChannel` (raw `Data` in/out of the mirroring session) for F17; `FakeHealthStore` in `LedgerTestSupport` + contract tests; Info.plist strings and background modes on both targets.
**Out (explicitly):** envelope encoding, batching, watchdog, WC fallback (F17); any watch UI (F18); program push / workout pull-back (F19); Live Activity started inside the mirroring handler (F21 — F16 only exposes the hook); HR zones (`HKWorkoutZoneConfiguration`, iOS 27+, not needed).

## Touches
- `LedgerKit/Sources/LedgerDomain/Health/HealthStore.swift` (protocol + value types below)
- `LedgerKit/Sources/LedgerDomain/Health/RemoteSessionChannel.swift`
- `LedgerKit/Sources/LedgerHealth/LiveHealthStore.swift` (actor, shared surface)
- `LedgerKit/Sources/LedgerHealth/Watch/WatchWorkoutSession.swift` (session + builder + delegates)
- `LedgerKit/Sources/LedgerHealth/Phone/PhoneMirrorReceiver.swift` (start handler, session retention)
- `LedgerKit/Sources/LedgerHealth/Phone/PhoneWorkoutSaver.swift` (`HKWorkoutBuilder`)
- `LedgerKit/Sources/LedgerHealth/HealthTypeSet.swift` (the three HK types, one place)
- `LedgerKit/Sources/LedgerHealth/DependencyKeys.swift` (`healthStore.liveValue`)
- `LedgerKit/Sources/LedgerTestSupport/Fakes/FakeHealthStore.swift`
- `LedgerKit/Tests/LedgerHealthTests/HealthStoreContractTests.swift`, `LiveHealthStoreStateMachineTests.swift`
- `LedgerKit/Tests/LedgerDomainTests/HealthTypesTests.swift`
- `Apps/Ledger-Info.plist`, `Apps/LedgerWatch-Info.plist` (usage strings; watch background modes `workout-processing` **and** `audio` — R1 D6 / §3.1: haptics in the background need Audio); entitlements `com.apple.developer.healthkit` on both (human edits in Xcode, ADR-003)
- `Apps/Ledger/LedgerApp.swift` (handler assignment at top of launch), `Apps/Ledger/SceneDelegate.swift` (`shouldHandleActiveWorkoutRecovery`)
- `Apps/LedgerWatch/WatchAppDelegate.swift` (`WKApplicationDelegate`: `handle(_:)`, `handleActiveWorkoutRecovery()`)

## Domain changes
Foundation-only types in `LedgerDomain` (no `HealthKit` import). `WorkoutID`, `Weight`, `WorkoutSummary` come from F02/F04 unchanged.

```swift
public enum HealthAuthorization: Equatable, Sendable { case notDetermined, authorized, denied, unavailable }
public struct HealthWorkoutMetadata: Equatable, Sendable {           // written via builder.addMetadata
    public let workoutID: WorkoutID; public let programName: String?; public let dayName: String?
    public let totalVolume: Weight; public let doneSets: Int
}
public struct HealthWorkoutRecord: Equatable, Sendable, Codable {     // → workout_health row (F05)
    public let healthKitUUID: UUID; public let start: Date; public let end: Date
    public let avgHeartRate: Int?; public let maxHeartRate: Int?; public let activeEnergyKcal: Int?
}
public struct HeartRateSample: Equatable, Sendable { public let bpm: Int; public let at: Date }
public enum HealthSessionEvent: Equatable, Sendable {
    case prepared, running(since: Date), ended(at: Date)
    case anotherWorkoutSessionStarted                 // errorAnotherWorkoutSessionStarted (R1 §2.3)
    case mirrorConnected, mirrorDisconnected          // phone + watch
    case recovered                                    // after recoverActiveWorkoutSession
    case startRequestedByPhone                        // watch: WKApplicationDelegate.handle(_:)
    case failed(HealthError)
}
public enum HealthError: Error, Equatable, Sendable {
    case notAuthorized, unavailable, sessionAlreadyRunning, noActiveSession
    case anotherWorkoutSessionStarted, watchAppUnavailable, mirroringTimedOut, underlying(code: Int)
}
public protocol HealthStore: Sendable {
    func authorization() async -> HealthAuthorization
    func requestAuthorization() async throws -> HealthAuthorization
    var events: AsyncStream<HealthSessionEvent> { get }
    // watch (primary session)
    func startSession(workoutID: WorkoutID, at: Date) async throws           // prepare → .prepared → startActivity + beginCollection
    func heartRate() -> AsyncStream<HeartRateSample>
    func endSession(metadata: HealthWorkoutMetadata, at: Date) async throws -> HealthWorkoutRecord
    func discardSession() async throws                                       // end + discardWorkout, no HKWorkout written
    func recoverActiveSession() async throws -> Bool
    // phone
    func requestWatchStart() async throws                                    // HKHealthStore.startWatchApp(toHandle:)
    func saveWorkout(metadata: HealthWorkoutMetadata, start: Date, end: Date) async throws -> HealthWorkoutRecord   // phone-only, no HR
    func workoutRecord(healthKitUUID: UUID) async throws -> HealthWorkoutRecord?   // HR stats for a watch-saved workout (F19)
    var remoteChannel: any RemoteSessionChannel { get }
}
public protocol RemoteSessionChannel: Sendable {                      // consumed by F17's MirroringTransport
    var connection: AsyncStream<Bool> { get }
    var incoming: AsyncStream<[Data]> { get }                          // didReceiveDataFromRemoteWorkoutSession batches, arrival order
    func send(_ data: Data) async throws                               // raw sendToRemoteWorkoutSession; no timeout inside (F17 owns the watchdog)
}
```
Rules the live actor must implement (each maps to a criterion):
- HK types are exactly `HKObjectType.workoutType()`, `HKQuantityType(.heartRate)`, `HKQuantityType(.activeEnergyBurned)`; share = workout + energy, read = all three. Authorization is requested from the **phone** at first "Start workout" (prompts for both devices); the watch calls `requestAuthorization` only when standalone (F19) and `authorization() == .notDetermined`.
- Watch start sequence (ADR-005 §4, R1 §2.5 gotchas 1/3/5): `HKWorkoutConfiguration(activityType: .traditionalStrengthTraining, locationType: .indoor)` → `HKWorkoutSession(healthStore:configuration:)` → `associatedWorkoutBuilder()` → `builder.dataSource = HKLiveWorkoutDataSource(healthStore:workoutConfiguration:)` → delegates → `session.prepare()` → **wait for `.prepared`** in `workoutSession(_:didChangeTo:from:date:)` → emit `.prepared` → `startMirroringToCompanionDevice()` wrapped in a 10 s `continuousClock` timeout (gotcha 5; failure is non-fatal, emit `.failed(.mirroringTimedOut)`) → `startActivity(with:)` + `beginCollection(at:)` → `.running`. Mirroring is retried on every `.mirrorDisconnected` with backoff 2/4/8 s while the session runs.
- End: `stopActivity(with:)` → on `.stopped`: `endCollection(at:)` → `addMetadata` (`HKMetadataKeyWorkoutBrandName` = the bundle's `CFBundleDisplayName`, **not** a literal — it is shown in the Health and Fitness apps; see `docs/product-decisions.md` › Naming, `com.petearevalo.Ledger.workoutID`, `com.petearevalo.Ledger.totalVolumeGrams`, `com.petearevalo.Ledger.program`, `com.petearevalo.Ledger.day`) → `finishWorkout()` → `session.end()` → `HealthWorkoutRecord` from `builder.statistics(for:)` (HR avg/max, energy sum). Only `finishWorkout` writes the `HKWorkout` (R1 §3.1).
- HR stream: `workoutBuilder(_:didCollectDataOf:)` → `statistics(for: .heartRate).mostRecentQuantity()` → `HeartRateSample`. No HR values in logs (standards §8).
- Phone: `HKHealthStore.workoutSessionMirroringStartHandler` is assigned **synchronously in `LedgerApp.init`** before any `await` (gotcha 4); the handler may fire several times per workout with a new `HKWorkoutSession` each time (R1 §2.3) — retain every one in an array keyed by start date, set `delegate`, rebind `remoteChannel` to the newest, emit `.mirrorConnected`; on `didDisconnectFromRemoteDeviceWithError` emit `.mirrorDisconnected` and drop that instance. The handler exposes an `onMirrorStart: @Sendable (WorkoutID?) async -> Void` hook (F21 starts the Live Activity here, 10 s budget).
- `errorAnotherWorkoutSessionStarted` in `didFailWithError` → `.anotherWorkoutSessionStarted`; the session is treated as ended without a HealthKit write (the log lives on, F17/F18 keep logging).
- Recovery: watch `handleActiveWorkoutRecovery()` → `recoverActiveSession()` → `recoverActiveWorkoutSession(completion:)` → re-attach builder/dataSource/delegates → `.recovered`. Phone: `UIScene.ConnectionOptions.shouldHandleActiveWorkoutRecovery` (iOS 26) → `recoverActiveSession()`.
- Phone never writes the `HKWorkout` for a workout that had a watch session; `saveWorkout` is used only when `WorkoutState` carries no watch device in its log (F17 exposes `hasWatchParticipant`).

## Acceptance criteria
1. Given both Info.plists, when `requestAuthorization` runs, then `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` exist on **both** targets (test reads the bundles; missing keys crash at runtime, R1 §3.3).
2. Given `.notDetermined`, when the phone user taps "Start workout", then the HealthKit sheet appears once, listing exactly Workouts, Heart Rate, Active Energy; the watch shows no second sheet for a phone-authorised pair (**device**).
3. Given the watch starts a session, when `.running` is emitted, then the delegate has observed `.prepared` first and `startMirroringToCompanionDevice()` was called after it (state-machine test with a scripted `HKWorkoutSession` seam; **device** for the real call).
4. Given a running watch session, when HR samples arrive, then `heartRate()` yields `HeartRateSample`s within 5 s of wrist contact (**device**) and the fake yields scripted samples in order.
5. Given `endSession(metadata:)`, when it completes, then Apple Health shows one `traditionalStrengthTraining` workout with HR, active energy and metadata `com.petearevalo.Ledger.totalVolumeGrams` (**device**), and the returned `HealthWorkoutRecord.healthKitUUID` equals the saved workout's UUID.
6. Given `discardSession()`, when it completes, then no `HKWorkout` exists for that start date (**device**) and the fake records `discarded == true`.
7. Given the iOS app is not running, when the watch starts mirroring, then the app is launched in the background and `workoutSessionMirroringStartHandler` fires; a second reconnect fires it again with a different session object and both are retained (**device**; unit test asserts retention and channel rebind with a fake session).
8. Given the phone calls `requestWatchStart()`, when the watch app is installed, then `WKApplicationDelegate.handle(_ workoutConfiguration:)` receives `.traditionalStrengthTraining` and `.startRequestedByPhone` is emitted (**device**); when it is not installed, then `HealthError.watchAppUnavailable` is thrown within 10 s.
9. Given Apple's Workout app is started during a Ledger session, when HealthKit ends ours, then `.anotherWorkoutSessionStarted` is emitted within 2 s and no crash occurs (**device**).
10. Given the watch app is killed mid-session, when relaunched, then `handleActiveWorkoutRecovery()` → `.recovered` and HR resumes on the same `HKWorkout` (**device**).
11. Given the phone app is killed mid-mirror, when relaunched by the system, then `shouldHandleActiveWorkoutRecovery` is true and the mirror rebinds without user action (**device**).
12. Given a phone-only workout (no watch participant), when finished, then `saveWorkout` writes one workout without HR and the record's `avgHeartRate` is nil.
13. Given `FakeHealthStore`, when the contract suite runs, then every criterion 3, 4, 6, 7, 9, 12 has a passing fake-backed test (`HealthStoreContractTests`).
14. Given any error path, when it surfaces, then the emitted `HealthError` has no raw `NSError` description in UI (stores map to copy; standards §8).

## Test plan
- Unit (LedgerDomainTests): `test_healthAuthorization_isEquatableAndSendable`, `test_healthWorkoutMetadata_volumeIsGrams`
- Unit (LedgerHealthTests, scripted-session seam, no HealthKit calls): `test_startSession_waitsForPreparedBeforeMirroring`, `test_startSession_mirroringTimeoutIsNonFatal`, `test_mirroringRetries_backoff2_4_8`, `test_startHandler_retainsEverySession`, `test_startHandler_rebindsChannelToNewest`, `test_disconnect_dropsOnlyThatSession`, `test_anotherWorkoutSessionStarted_mapsToEvent_noSave`, `test_endSession_orders_stop_endCollection_addMetadata_finish_end`, `test_metadataKeys_exact`, `test_recovery_reattachesDelegates`, `test_saveWorkout_refusedWhenWatchParticipant`
- Contract (LedgerHealthTests): `HealthStoreContractTests` parameterised over `FakeHealthStore` (CI) and `LiveHealthStore` (device-only, `@Test(.enabled(if: Device.isPhysical))`)
- Integration (LedgerPersistenceTests): `test_workoutHealthRow_fromHealthWorkoutRecord`
- Bundle: `test_infoPlist_usageStringsPresent_bothTargets`, `test_watchBackgroundModes_containWorkoutProcessingAndAudio`
- Device checklist (feeds F20): auth sheet once · HR within 5 s · Health entry with metadata · discard writes nothing · handler fires on background launch and on reconnect · watch kill → recovery · phone kill → recovery · Apple Workout takeover · `startWatchApp` with watch app absent

## Non-functional
- Performance budget: `prepare()`→`.running` < 3 s on Series 9 (**device**); HR sample → stream ≤ 1 s; handler → `.mirrorConnected` < 10 s (the Live Activity budget, R1 §4.1).
- Accessibility: none (no UI). Settings "Apple Health" row copy (F14) reads `authorization()`.
- Offline behaviour: everything here is on-device; HealthKit needs no network. Mirroring absence is a normal state, never an error dialog.
- Simulator: `HKWorkoutSession` runs on the watch simulator but yields no HR; mirroring, `startWatchApp`, `workoutSessionMirroringStartHandler` and recovery do **not** work in the simulator (R1 §2.5 #6) — all such criteria are marked device and covered by the fake in CI.

## Risks / unknowns
- iOS/watchOS 26.0.x mirroring regression (FB20723311) may persist on 26.2–27.0 (R1 §6 #1); D4 ordering is the DTS workaround, not a fix. F17's WC fallback is the safety net.
- `sendToRemoteWorkoutSession` "never returns" (~5 %, R1 §2.5 #2) — the channel deliberately has no timeout; F17 owns it.
- Haptics pause HR sampling (R1 §3.1) — accepted; gaps around set-logged/rest-over haptics.
- `traditionalStrengthTraining` has no optimised calorie model (R1 D7); energy numbers are sensor floors. Do not advertise calories.
- watchOS 27 deprecates `WKExtension`; we use `WKApplicationDelegate` from day one (R1 D9).

## Definition of Done
Inherits `docs/engineering-standards.md` §12, plus:
- [ ] `LiveHealthStore` has zero `@unchecked Sendable`; HealthKit delegate callbacks hop into the actor via `AsyncStream` continuations.
- [ ] Device checklist above executed on iPhone + Watch on iOS/watchOS 26.x with results pasted into `implementation-notes.md` (the same items are reused by F20).
- [ ] No HR/energy value is logged; `os.Logger` category `health`.
- [ ] `UIRequiredDeviceCapabilities` does **not** contain `healthkit` on iOS (R1 §3.3) — app installs on devices without HealthKit and degrades to phone-only.

---
_Filled in by agents during delivery:_
- `F16-healthkit/implementation-notes.md`
- `F16-healthkit/test-findings.md`
- `F16-healthkit/review.md`
