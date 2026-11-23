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
