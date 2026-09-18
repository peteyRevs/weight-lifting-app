# F19 — Companion sync over WatchConnectivity (`LedgerSync`)

| | |
|---|---|
| Milestone | M2 |
| Status | ready |
| Depends on | F17, F18 |
| Branch | `feat/F19-companion-sync` |
| Design refs | `design/prototype/LedgerWatch.dc.html` → screen labels: `Watch — before workout` (data source), `Watch — summary`; `design/prototype/Ledger.dc.html` → `Today`, `Settings` |
| Spec refs | `docs/product-spec.md` §4.3 (idle), §5.1 (`weekLabel`, `dayName`, `hasPlan`, `planLine`, `nextSessionLine`), §7.3, §9 ("standalone start when the phone is away"); `docs/product-decisions.md` #16, #18; ADR-005 §5–6; `docs/architecture.md` §8 ("Everything else"); R1 §2.6 |

## Goal
After this ships, the watch always knows the current program, this week's schedule and the settings it needs, can start and finish a workout with the phone absent, and every workout finished on the wrist reaches the phone's history (with HealthKit stats) even if the phone was away for hours — including the case where both devices finished the same workout independently.

## User stories
- As a lifter, I can leave my phone at home and still see "Lower A — Squat focus" with the right loads on my wrist.
- As a lifter, a workout I finished on the watch shows up on my phone's History when I get back, once, with heart rate.
- As a lifter, if both devices ended the same workout while disconnected, I still get exactly one workout with every set.
- As a lifter, changing units or default rest on the phone is reflected on the watch within a minute.

## Scope
**In:** `CompanionTransport` protocol (Domain) + `WCCompanionTransport` (`LedgerSync`); phone→watch `updateApplicationContext` (program summary + next scheduled day + settings subset), `transferFile` (full program JSON + last-performance history snapshot), watch→phone `transferUserInfo` (finished-workout record); watch-local `Program`/`Settings` cache via the watch's own GRDB (`ProgramRepository`, `SettingsRepository`, F05 on watch); standalone start from the cached day; `WorkoutReconciler` (union + replay, idempotent re-materialisation); HealthKit stats pull for watch-saved workouts (F16 `workoutRecord(healthKitUUID:)`); fakes + device protocol entries.
**Out (explicitly):** live envelopes (F17); iCloud (F28); Smart Stack refresh on context change (F22 consumes the same snapshot); editing programs on the watch (never).

## Touches
- `LedgerKit/Sources/LedgerDomain/Sync/CompanionTransport.swift` (protocol, `CompanionContext`, `CompanionFile`, `FinishedWorkoutRecord`)
- `LedgerKit/Sources/LedgerDomain/Sync/WorkoutReconciler.swift` (pure)
- `LedgerKit/Sources/LedgerSync/Companion/WCCompanionTransport.swift` (one `WCSessionDelegate` shared with F17's `WCBoostTransport`)
- `LedgerKit/Sources/LedgerSync/Companion/ProgramPusher.swift` (phone), `WorkoutPullback.swift` (phone), `WatchProgramCache.swift` (watch), `FinishedWorkoutOutbox.swift` (watch)
- `LedgerKit/Sources/LedgerPersistence/Repositories/GRDBWorkoutRepository.swift` (`replaceMaterialised(workoutID:state:)` idempotent upsert — additive), `Migrations.swift` (`v0NN_addWorkoutSourceDevice` if absent: `workout.source_device_id`, `workout.reconciled_at`)
- `LedgerKit/Sources/LedgerSync/DependencyKeys.swift` (`companionTransport.liveValue`)
- `LedgerKit/Sources/LedgerTestSupport/Fakes/FakeCompanionTransport.swift`
- `LedgerKit/Sources/WatchFeatureWorkout/WatchWorkoutStore.swift` (standalone start path only)
- `LedgerKit/Sources/FeatureToday/TodayStore.swift` (observe pull-back → "Logged" card), `FeatureSettings` (nothing; pusher observes `SettingsRepository`)
- `Apps/Ledger/AppDependencies.swift`, `Apps/LedgerWatch/WatchDependencies.swift`
- `LedgerKit/Tests/LedgerSyncTests/Companion…`, `LedgerKit/Tests/LedgerDomainTests/WorkoutReconcilerTests.swift`, `LedgerKit/Tests/LedgerPersistenceTests/ReplaceMaterialisedTests.swift`

## Domain changes
```swift
public struct CompanionContext: Codable, Equatable, Sendable {           // ≤ 256 KB (R1 §2.6), latest wins
    public let programID: ProgramID?; public let programName: String?; public let weekIndex: Int; public let weekCount: Int; public let isDeload: Bool
    public let nextDay: NextDay?          // dayTemplateID, name, tag, weekday, exerciseCount, setCount, firstExerciseName, isToday, isLoggedToday
    public let settings: WatchSettings    // units, defaultRest, autoRest, watchBuzz, weekStart
    public let pendingStart: PendingStart?   // dayTemplateID + weekIndex the phone just asked the watch to start (F17 double-start rule)
    public let revision: UInt64           // monotonically increasing; watch ignores older
}
public enum CompanionFile: Codable, Sendable { case program(Program, history: [ExerciseID: LastPerformance]), historySnapshot([WorkoutSummaryRow]) }
public struct FinishedWorkoutRecord: Codable, Equatable, Sendable {      // ≤ 60 000 bytes; else sent as a file
    public let workoutID: WorkoutID; public let log: [EventEnvelope]; public let healthKitUUID: UUID?; public let finishedAt: Date; public let device: DeviceID
}
public protocol CompanionTransport: Sendable {
    func updateContext(_ context: CompanionContext) async throws          // WCSession.updateApplicationContext
    func transfer(_ file: CompanionFile) async throws                      // transferFile(_:metadata:)
    func enqueue(_ record: FinishedWorkoutRecord) async throws            // transferUserInfo (ordered, survives suspension)
    var receivedContext: AsyncStream<CompanionContext> { get }
    var receivedFiles: AsyncStream<CompanionFile> { get }
    var receivedRecords: AsyncStream<FinishedWorkoutRecord> { get }
    var isPaired: Bool { get async }; var isWatchAppInstalled: Bool { get async }
}
public enum WorkoutReconciler {
    public static func merge(local: [EventEnvelope], remote: [EventEnvelope]) -> [EventEnvelope]     // union, dedupe (device, seq), sort (wallClock, device, seq)
    public static func resolve(_ merged: [EventEnvelope]) -> WorkoutState                            // WorkoutEngine.replay; first terminal event wins
}
```
Rules (each maps to a criterion):
- **Push triggers (phone):** any `ProgramRepository` change, `SettingsRepository` change, midnight (next day changes), a workout finished/deleted (last performance changes), and `WCSessionActivationState == .activated` / `isWatchAppInstalled` flipping true. Context is tiny and sent every time; the program file is sent when the program or last-performance snapshot hash changes. Never `sendMessage` for these (ADR-005 §5).
- **Watch cache:** received `Program` replaces the cached program (single active program); `LastPerformance` per exercise stored for `SessionBuilder`; `WatchSettings` written to the watch `SettingsRepository`. The idle screen (F18) reads only local repositories — no live WC reads on render.
- **Standalone start:** `SessionBuilder.build(program:week:day:history:)` on the watch from cache using `WeekCalendar` for the week index (decision #18); if `authorization() == .notDetermined`, request on the watch first (F16); on finish with no phone: `endSession` (F16) → materialise into the watch GRDB → `enqueue(FinishedWorkoutRecord)` (queued by WC until delivered). Records over 60 000 bytes go through `transfer(.historySnapshot)` plus a small record carrying only IDs.
- **Pull-back (phone):** on `receivedRecords`: if no workout with that `WorkoutID` exists → `WorkoutReconciler.resolve` → `replaceMaterialised` (PRs + misses computed as on finish, F05) → mark `source_device_id`; if one exists → `merge(local: storedLog ?? materialisedAsLog, remote:)` → `resolve` → `replaceMaterialised` in one transaction → `reconciled_at`. Re-materialisation is idempotent: same envelopes twice → identical rows. Then `workoutRecord(healthKitUUID:)` (F16) → `workout_health` row; if HealthKit has not yet synced the workout to the phone, retry on next launch and when History opens (bounded 24 h, then give up silently — HR simply absent).
- **Watch when the phone finished first:** the `.finished` envelope arrives over F17 on reconnect; if the watch already finished with a different `finishedAt`, the earlier terminal event wins in `resolve` and the watch's HealthKit workout stays (the watch is the Health authority). The phone never calls `saveWorkout` for a workout with a watch participant (F16 rule).
- **Compaction:** the watch keeps its event log until the phone acknowledges the record (`receivedRecords` echo of `workoutID` in the next context `acknowledgedWorkoutIDs`), then compacts (F05).

## Acceptance criteria
1. Given the phone edits a program, when saved, then `updateContext` is called with `revision + 1` within 1 s and `transfer(.program)` is called once (hash-gated; a second identical save sends no file).
2. Given the watch receives a context with a lower `revision` than cached, when applied, then the cache is unchanged.
3. Given a cached program on the watch and no phone, when idle renders, then week label, day name and plan line match what the phone's Today shows for the same date (shared fixtures; `WeekCalendar`).
4. Given the watch starts standalone, when the day is built, then the loads equal `ProgressionRules.prescribe` output from the cached program and misses (identical to the phone for the same fixture).
5. Given a standalone workout is finished on the watch with the phone off, when the phone returns, then exactly one `FinishedWorkoutRecord` is delivered and History shows the workout with all sets within 60 s of reconnect (**device**; fake-backed test asserts one enqueue and one materialisation).
6. Given both devices finished the same `WorkoutID` while partitioned (watch logged sets 6–8, phone logged set 6 with a different weight edit and finished 40 s later), when reconciled, then the phone holds one workout, sets 6–8 present, set 6's target follows the later `(wallClock, device)` per field, `finishedAt` = the earlier terminal event, and re-running reconciliation changes nothing (property test over shuffled logs).
7. Given a `FinishedWorkoutRecord` for a workout the phone never saw, when received, then a new workout row with `source_device_id = watch` appears, PRs and misses computed, Today's card flips to "Logged".
8. Given a record > 60 000 bytes, when enqueued, then the log travels as `transfer(.historySnapshot)` and the record carries IDs only; the phone reconciles identically.
9. Given the watch-saved workout's HealthKit stats are not yet on the phone, when the record is processed, then `workout_health` is filled on a later retry without duplicating the workout.
10. Given settings change on the phone (units lb→kg, watchBuzz off), when the watch receives the context, then the watch's `SettingsRepository` reflects both within 60 s (**device**) and immediately via the fake.
11. Given the simulator, when `transferUserInfo` is unsupported, then `WCCompanionTransport` logs once and `FakeCompanionTransport` is what CI exercises; no test in CI touches `WCSession` (standards §9).
12. Given `isWatchAppInstalled == false`, when the phone starts a workout, then no push is attempted and Today shows no watch line.

## Test plan
- Unit (LedgerDomainTests): `test_reconciler_unionDedupesByDeviceSeq`, `test_reconciler_orderIsWallClockDeviceSeq`, `test_reconciler_firstTerminalWins`, `test_reconciler_property_shuffleInvariant`, `test_reconciler_property_idempotent`, `test_context_revisionMonotonic`, `test_context_encodedUnder256KB`, `test_record_encodedUnder60000_orFileFallback`
- Unit (LedgerSyncTests): `test_pusher_triggersOnProgramSettingsMidnightFinish`, `test_pusher_fileHashGated`, `test_cache_ignoresOlderRevision`, `test_outbox_enqueuesOncePerFinishedWorkout`, `test_outbox_compactsAfterAck`, `test_pullback_newWorkout_materialises`, `test_pullback_existingWorkout_mergesAndRematerialises`, `test_pullback_healthStatsRetryBounded24h`, `test_standaloneStart_usesCachedPrescription`
- Integration (LedgerPersistenceTests): `test_replaceMaterialised_idempotent`, `test_replaceMaterialised_recomputesPRsAndMisses`, `test_migration_addsSourceDeviceAndReconciledAt`
- Snapshot (FeatureTodayTests): Today "Logged · from Apple Watch" card × {light, dark}
- Device (F20): scenarios "start from wrist", "phone locked 10 min", "finish on watch", "kill phone app".

## Non-functional
- Performance budget: context encode < 5 ms; program file < 200 KB for a 12-week, 4-day program; pull-back materialisation < 100 ms for a 60-set workout.
- Accessibility: Today card source line readable by VoiceOver ("Logged on Apple Watch").
- Offline behaviour: all WC calls are queue-and-forget; nothing awaits delivery; the watch can run any number of standalone workouts before the phone returns (outbox is ordered).

## Risks / unknowns
- `transferUserInfo` unsupported in the simulator (R1 §2.6, ADR-005) → CI uses fakes; device protocol is the only proof.
- WC payload ceilings are community-measured (65 536 / 262 144 bytes), not documented — bounds above leave headroom; assert in tests.
- Architecture §16 says health data "never leaves the device except to HealthKit": HR reaches the phone by reading HealthKit's own sync, not by shipping numbers over WC — keep it that way.
- Same-`WorkoutID` conflict on set *edits* is per-field LWW by `(wallClock, device, seq)`; clocks on paired devices are within seconds — acceptable.

## Definition of Done
Inherits `docs/engineering-standards.md` §12, plus:
- [ ] One `WCSessionDelegate` object in the process, shared with F17 (documented in implementation-notes).
- [ ] Device protocol entries executed and recorded (F20 results file).
- [ ] No WC call on the main actor path of any store; all in `LedgerSync` actors.
- [ ] Migration name recorded; append-only.

---
_Filled in by agents during delivery:_
- `F19-companion-sync/implementation-notes.md`
- `F19-companion-sync/test-findings.md`
- `F19-companion-sync/review.md`
