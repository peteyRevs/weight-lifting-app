# F16 — implementation notes

## Slice plan (G1, 2026-11-22)

From the brief, architecture §9, ADR-005, ADR-008, R1 §2–3 and main `f76c432`. Each slice branches from main once
the previous one has merged (no stacked PRs) and is green alone.

| Slice | Contents | Criteria | Est. |
|---|---|---|---|
| **S1** domain contract + fake | `HealthStore`, `RemoteSessionChannel` and the value types in `LedgerDomain`; `HealthAuthorization` moved there from `LedgerHealth` (the HealthKit mapping and Diagnostics' label stay as extensions); `FakeHealthStore` (its own `remoteChannel`, as `UnimplementedHealthStore` is); `UnimplementedHealthStore` grown to the protocol; `HealthStoreContractTests` on the fake; bundle tests on both apps; `audio` in the watch's background modes. | 1, 13; fake halves of 3, 4, 6, 7, 9, 12 | ~950 |
| **S2** watch live session | `LiveHealthStore` actor (shared surface + `#if os(watchOS)`) over a scripted seam standing in for `HKWorkoutSession` + `HKLiveWorkoutBuilder`: `HealthTypeSet`, authorization, start sequence (prepare → `.prepared` → mirroring under a 10 s timeout → startActivity + beginCollection → `.running`), mirroring retry 2/4/8 s, HR stream, end ordering + metadata keys + `CFBundleDisplayName` brand, discard, takeover, recovery. `LiveHealthStoreStateMachineTests`. | 3, 4, 5, 6, 9, 10 | ~900 |
| **S3** phone side + wiring | Extend `MirroringStartRegistrar` into the mirror receiver (delegate per session, drop on disconnect, rebind `remoteChannel`, `onMirrorStart` hook for F21); `#if os(iOS)`: `requestWatchStart`, `PhoneWorkoutSaver`, `workoutRecord(healthKitUUID:)`, phone recovery; `healthStore` bound in both compositions; `WatchAppDelegate` forwards `handle(_:)` and `handleActiveWorkoutRecovery()`; iOS `shouldHandleActiveWorkoutRecovery`. Device checklist pasted here. | 2, 7, 8, 10, 11, 12, 14 | ~850 |

If S2 passes 1,000 lines it splits into S2a (seam, start, mirroring retry, HR) and S2b (end/save, discard,
takeover, recovery).

**Paths follow the repo, not the brief's `Touches`** (the brief predates F07 and ADR-008): the protocol stays in
`LedgerDomain/Protocols/HealthStore.swift`, the values are `LedgerDomain/Model/HealthTypes.swift`, the fakes live in
`LedgerFakes` (not `LedgerTestSupport`), `healthStore.liveValue` is bound by the compositions as every other key is
(LedgerHealth does not depend on LedgerDependencies), the phone half extends the existing `MirroringStartRegistrar`
instead of a new `PhoneMirrorReceiver`, and the watch delegate is `LedgerWatchAppKit/WatchAppDelegate.swift`. New
files under `Apps/` land in synchronized folders (ADR-003), so no project edit is needed.

## Slice S1 (G1, 2026-11-22)

- **Package:** `LedgerHealthTests` links `LedgerFakes` directly, by ADR-008 decision 2's rule, so the fake's lines
  count towards LedgerFakes' 90 % gate; graph re-recorded; ADR-008's list updated.
- **Apps:** `audio` added to the watch's `WKBackgroundModes` (R1 D6 and §3.1 agree). The usage strings were already
  on both targets.
- **`ProtocolsAdversarialTests`:** its brief conformance of `HealthStore` was empty, which no longer compiles; it is
  now written from F16's signatures, and the case asserts what it asserted.

### Deviations from the brief

1. **`heartRate()` is `async`.** An actor cannot meet a synchronous requirement with isolated state, so the brief's
   signature would force `LiveHealthStore` to keep its subscribers behind a `Mutex`, which standards §4 allows only
   for framework callbacks.
2. **Labels renamed for SwiftLint's `identifier_name`:** `HeartRateSample.date` (not `at`), `.ended(Date)` (not
   `ended(at:)`); the protocol keeps the brief's argument labels (`at start:`, `at end:`).
3. **`HealthAuthorization` has no raw values.** Its old `String` raw values were Diagnostics' words; they moved to
   `diagnosticsLabel` in LedgerHealth.
4. **The contract runs against the fake only.** `LiveHealthStore` joins it in S2/S3, on the device lane.
5. **Criterion 1 is one test per app test target** (`LedgerTests`, `LedgerWatchTests`), each reading its own
   bundle.
6. **A send with no mirrored session throws `noActiveSession`** (the brief names no error for it).
7. testing-strategy §2.4 says `.anotherSessionRunning` and "save idempotent by `WorkoutID`": the brief's
   `anotherWorkoutSessionStarted` is used, and idempotence is left to F17/F19's coordinator.

### Open questions

- `events` is one stream for the store's life (one consumer). If F17 and F18 both need it, F17 adds a broadcast.
- Both entitlements carry `com.apple.developer.healthkit.access` as an empty array; R1 §3.3 says not to ask for
  clinical access. Harmless, but a human may remove it in Xcode (ADR-003).

## Slice S2a (G1, 2026-11-22)

S2 as planned came to ~1,360 lines with its tests (HealthKit adapter ~260, state machine ~390, seam ~75, tests
~550), past the 1,000 cap. The brief's fallback split (start, heart rate and mirroring first) still came to ~1,020
with the adapter's start half, so S2 splits at the HealthKit boundary instead:

- **S2a (this slice):** the seam (`WorkoutSessionDriver`, `WorkoutSessionProvider`, `WorkoutSessionCallback`) and
  `LiveHealthStore`'s state machine for the start (prepare → `.prepared` → mirroring under a 10 s timeout →
  startActivity + beginCollection → `.running`), mirroring retries after 2, 4 and 8 s, the heart-rate stream and
  the channel's `connection`. `LiveHealthStoreStateMachineTests` over `ScriptedSession` and `ManualClock`. Nothing
  in it imports HealthKit, so it builds and is tested on iOS (the PR lane's coverage) and watchOS alike.
- **S2b:** the watch's HealthKit provider and session behind the seam (`#if os(watchOS)`: configuration →
  session → `associatedWorkoutBuilder()` → `HKLiveWorkoutDataSource` → delegates), `HealthTypeSet`, the `HKError`
  → `HealthError` map, authorization against HealthKit (shared, for S3), `public init(healthStore:)`; the end
  (stop → `.stopped` → endCollection → addMetadata → finishWorkout → end, the record from the builder's
  statistics), the metadata keys and the `CFBundleDisplayName` brand, discard, the takeover, recovery, and the
  channel's data. Its tests: `endSession_orders_stop_endCollection_addMetadata_finish_end`, `metadataKeys_exact`,
  `anotherWorkoutSessionStarted_mapsToEvent_noSave`, `recovery_reattachesDelegates`. Drafted during S2a, compiled
  against the watchOS 27 SDK and green on both simulators (~640 lines); it lands as its own PR after this one.

### Decisions

1. **Callbacks reach the actor through a stream.** A driver exposes `callbacks: AsyncStream<WorkoutSessionCallback>`;
   the store runs one listener task per session, held in the session and cancelled when it is detached (and in
   `deinit`), which awaits `handle(_:session:)` for each callback in order. A session number makes a late callback
   or retry of a replaced session do nothing. A wait for a state (`.prepared`; `.stopped` in S2b) is one
   `CheckedContinuation` that the matching callback resumes, a failure throws into, and a detach ends.
2. **No `@unchecked Sendable` (S2b, compiled).** HealthKit marks `HKWorkoutSession`, `HKLiveWorkoutBuilder`,
   `HKLiveWorkoutDataSource` and `HKHealthStore` `NS_SWIFT_SENDABLE`, so the adapter is a final class of `let`s. The
   delegate is `final class WorkoutSessionDelegate: NSObject, HKWorkoutSessionDelegate,
   HKLiveWorkoutBuilderDelegate, Sendable` whose one stored property is the stream's `let` continuation (Sendable):
   HealthKit may call it on any queue, it reads only what each call hands it, and the store reads the stream in
   its own isolation.
3. **The mirroring timeout is a race.** A task group runs `startMirroring()` against `clock.sleep(for: 10 s)`; the
   first answer wins and the other is cancelled. A group waits for its children, so the seam requires
   `startMirroring()` to return when cancelled even if HealthKit never answers (R1 §2.5 gotcha 5); S2b's adapter
   resumes its continuation from HealthKit's answer or from the cancellation, whichever comes first, through a
   `Mutex` slot (standards §4's exception for state a framework callback writes).
4. **Retries.** On `.mirrorDisconnected` while the session runs (and no retry is under way), a retry task held in
   the session waits 2 s, mirrors under the same timeout, then 4 s, then 8 s, and stops at the first success
   (`.mirrorConnected`, `connection` true). After the third failure it gives up until the next disconnect; the
   failures are logged, not emitted (a missing mirror is a normal state, brief › Non-functional).
5. **The clock is injected as `any Clock<Duration>`** (default `ContinuousClock`), not `@Dependency`:
   LedgerHealth does not depend on LedgerDependencies (S1). The tests' `ManualClock` follows `RestCoverClock`
   (#122): a sleep is registered, and announced on `sleeps`, in the step that suspends its task, and `advance(by:)`
   wakes what is due without yielding. No `TestClock`, no sleeps.
6. **The start needs `.authorized`**, as the fake's does.

### Deviations from the brief

1. **S2 splits at the HealthKit boundary** (above), not start-versus-end.
2. **A mirroring error at the start is non-fatal too**, and is emitted as `.failed(error)`; the brief names only the
   timeout.
3. **What S2a does not implement throws `HealthError.unavailable`:** `endSession`, `discardSession`,
   `recoverActiveSession` and `send` until S2b; `requestWatchStart`, `saveWorkout` and `workoutRecord` until S3,
   and for good on the watch (it never asks itself to start, saves only by ending its session, and has no caller
   for records). `incoming` stays open and silent until S2b. No composition binds `LiveHealthStore` yet (S3).
4. **`HealthStoreContractTests` stays on the fake.** Its clauses drive the fake's `simulate…` hooks, and a package
   test host has no HealthKit entitlement, even on a device, so a `.enabled(if:)` live leg could never run. The
   live store's halves of criteria 3 and 4 are the state-machine tests; the real-HealthKit halves are the device
   checklist (S3).
5. **Files:** the seam is `LedgerHealth/WorkoutSessionDriver.swift`; S2b's adapter is
   `LedgerHealth/Watch/HealthKitWorkoutSession.swift` (the brief's `Watch/WatchWorkoutSession.swift`).

## Slice S2b (G1, 2026-11-22)

Ported from the draft written during S2a onto main's merged S2a (#130).

- **The watch's HealthKit provider** (`Watch/HealthKitWorkoutSession.swift`, `#if os(watchOS)`):
  `HKWorkoutConfiguration` (`.traditionalStrengthTraining`, `.indoor`) → `HKWorkoutSession(healthStore:configuration:)`
  → `associatedWorkoutBuilder()` → `HKLiveWorkoutDataSource` → delegates, one initializer for a new session and a
  recovered one (`recoverActiveWorkoutSession()`). The delegate turns heart-rate batches into `HeartRateSample`s
  (`mostRecentQuantity()`), state changes, failures, disconnects and the phone's data into callbacks.
  `startMirroring()` resumes once, from HealthKit's answer or the task's cancellation (S2a decision 3).
  `LiveHealthStore(healthStore:bundle:)` is the watch's public initializer; no composition binds it until S3.
- **Shared, for S3** (`HealthKitMapping.swift`): `HealthTypeSet` (share workout + active energy, read those and
  heart rate), `HealthKitAuthorizer`, the `HKError` → `HealthError` map (takeover, authorization, unavailable, else
  the code), the metadata keys and the brand name.
- **The store** (`LiveHealthStore+End.swift`): `endSession` stops the activity, waits for `.stopped`, then
  endCollection → addMetadata → finishWorkout → end, and returns the record from the builder's statistics (HR
  average and maximum, energy sum, rounded); `discardSession` ends and discards (`.ended(now)`); recovery attaches
  the kept session as running (`.recovered`, mirror retries allowed); `send` goes over the session, the phone's
  batches arrive on `incoming`. `errorAnotherWorkoutSessionStarted` → discard the builder's workout, detach, and
  `.anotherWorkoutSessionStarted`; a call waiting on the session throws it.
- **Brand name:** `CFBundleDisplayName`, else `CFBundleName`, a blank one absent (as `AppAbout`); no brand key
  when neither exists.

### Decisions

1. **`totalVolumeGrams` is an `HKQuantity` in grams**, not an `NSDecimalNumber`. HealthKit documents metadata
   values as `NSString`, `NSDate`, `NSNumber` or `HKQuantity`; an `NSDecimalNumber` is an `NSNumber` subclass, but
   how HealthKit stores a subclass is not documented, while a quantity is, and it carries its unit, so a reader
   can never take the number for kilograms or pounds. The seam keeps the value exact (`.grams(Decimal)`, compared
   exactly in `metadataKeys_exact`); only the watch's adapter makes it a `Double` for `HKQuantity`. A `Double`
   holds a session's grams (at most ~10⁸, with lb conversions to 10⁻⁵ g) far inside its 15 significant digits,
   and Health only displays it; Ledger's exact volume stays in its own log (ADR-007).
2. **The metadata entries live with the keys** (`HealthWorkoutMetadata.healthKitEntries(brandName:)` beside
   `HealthMetadataKey`), so the brand key is HealthKit's own `HKMetadataKeyWorkoutBrandName`, not a copy of its
   text.
3. **The end, discard, recovery and the phone's calls moved to `LiveHealthStore+End.swift`** to keep the actor
   under SwiftLint's file and body lengths; the state the extension reads (`session`, `sink`, `logger`, …) is now
   module-internal rather than private, and the session-life helpers internal.
4. **S2a's `authorization_andLaterSlices` became `authorization_andPhoneCalls`**: the calls S2b implements no longer
   throw `unavailable`; each has its own test now.

### Deviations from the brief

1. **`HKWorkoutConfiguration` is built by setting its properties**, not with the brief's
   `HKWorkoutConfiguration(activityType:locationType:)`, which its header does not declare.
2. **A finished workout's start and end are HealthKit's** (`HKWorkout.startDate`/`endDate`), so a recovered
   session, whose start the store never saw, reports them too.
3. **A takeover discards the builder's workout** (`discardWorkout()`) as well as emitting the event, so that
   nothing collected so far is written by accident.

### Decided: the coverage gate (Pete, 2026-11-24)

`Watch/HealthKitWorkoutSession.swift` has 241 executable lines that only a real `HKWorkoutSession` can run, and
a package test host cannot drive one (no HealthKit entitlement; standards §9 forbids HealthKit in unit tests).
With it, LedgerHealth measured 363 / 647 = 56.1 % on the iOS bundle against its 80 % threshold; without it,
363 / 406 = 89.4 %. Pete approved excluding `LedgerHealth/Watch/*` from the gate (`scripts/coverage-thresholds.json`,
testing-strategy §4); the adapter is verified on his iPhone 17 + Apple Watch Series 9 by F20 scenario 15, part of
the M2 exit. The folder holds only the thin HealthKit adapter; logic stays in `LiveHealthStore`.
