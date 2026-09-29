# F17 — Live workout sync transport (`LedgerSync`)

| | |
|---|---|
| Milestone | M2 |
| Status | ready |
| Depends on | F04, F16 |
| Branch | `feat/F17-live-sync` |
| Design refs | `design/prototype/Ledger.dc.html` → screen labels: `Active workout` (header, for the connection line); `design/prototype/LedgerWatch.dc.html` → `Watch — set ready` |
| Spec refs | `docs/product-spec.md` §5.3 (superseded by ADR-004/005 — see Risks), §9 ("Error / offline states"); ADR-004; ADR-005; `docs/architecture.md` §6, §8; R1 §2.3–2.6 |

## Goal
After this ships, a set logged on either device appears on the other within a second while connected, nothing is lost when the phone is in a bag or Bluetooth drops, both devices converge on the same `WorkoutState` after any partition, and the UI can say "Watch not connected — logging continues" instead of failing.

## User stories
- As a lifter, I can log a set on the watch and see it ticked on the phone (and vice versa) so that either screen is trustworthy.
- As a lifter, I can lock my phone in a locker for ten minutes, keep logging on the wrist, and find the phone caught up when I return.
- As a lifter, I can extend rest on the phone and have the watch ring agree to the second.
- As a lifter, I am told when the other device is unreachable, without being blocked.

## Scope
**In:** `EnvelopeCodec` (versioned wire format, size-bounded); `WorkoutSessionActor` (log owner, local intents → envelopes, remote apply, `AsyncStream<WorkoutState>`, effect execution hooks); `LiveWorkoutTransport` protocol + `MirroringTransport` (over F16's `RemoteSessionChannel`) + `WCBoostTransport` (`sendMessageData` while `isReachable`) + `CompositeTransport` (dedupe, watchdog, fallback); reconnect handshake and gap replay; `LiveConnectionState` for the UI; envelope persistence through `WorkoutEventStore` on both devices; phone `FeatureWorkout` store switched from its F10 local reducer loop to the session client (second PR); property tests over `FakeTransport`.
**Out (explicitly):** HealthKit session lifecycle (F16); watch screens (F18); program push, finished-workout pull-back, standalone-start data (F19); Live Activity updates (F21 — consumes `Effect.updateLiveActivity`); rest notifications (F23).

## Touches
- `LedgerKit/Sources/LedgerDomain/Sync/WorkoutSessionClient.swift` (protocol, `WorkoutIntent`, `LiveConnectionState`)
- `LedgerKit/Sources/LedgerDomain/Sync/LiveWorkoutTransport.swift` (protocol, `WireFrame`)
- `LedgerKit/Sources/LedgerSync/EnvelopeCodec.swift`
- `LedgerKit/Sources/LedgerSync/WorkoutSessionActor.swift`
- `LedgerKit/Sources/LedgerSync/Transports/MirroringTransport.swift`, `WCBoostTransport.swift`, `CompositeTransport.swift`
- `LedgerKit/Sources/LedgerSync/Handshake.swift`
- `LedgerKit/Sources/LedgerSync/DependencyKeys.swift` (`liveWorkoutTransport.liveValue`, new `workoutSession` key)
- `LedgerKit/Sources/LedgerTestSupport/Fakes/FakeTransport.swift` (partition / reorder / duplicate / loss / hang knobs), `FakeWorkoutSessionClient.swift`
- `LedgerKit/Sources/FeatureWorkout/ActiveWorkoutStore.swift` (adopt `WorkoutSessionClient`; connection line)
- `LedgerKit/Tests/LedgerSyncTests/…`, `LedgerKit/Tests/FeatureWorkoutTests/ActiveWorkoutStoreSyncTests.swift`
- `Apps/Ledger/AppDependencies.swift`, `Apps/LedgerWatch/WatchDependencies.swift` (bind actor + transports; `WCSession` delegate registered at launch)
- `LedgerKit/Package.swift` (LedgerSync links `WatchConnectivity`; **no** `HealthKit` — mirroring is reached only through `RemoteSessionChannel`)

## Domain changes
Uses F04's `EventEnvelope`, `WorkoutEvent`, `WorkoutState`, `WorkoutEngine.reduce/replay`, `Effect`, F02's `DeviceID`, F05's `WorkoutEventStore` unchanged. New, in `LedgerDomain`:

```swift
public enum WorkoutIntent: Equatable, Sendable {              // user gestures, timestamped by the caller (@Dependency(\.date))
    case start(WorkoutState.Source, at: Date), selectExercise(SlotID, at: Date)
    case logSet(SlotID, SetID, Weight, Reps, at: Date), unlogSet(SlotID, SetID, at: Date)
    case changeTarget(SlotID, SetID, weight: Weight?, reps: Reps?, at: Date), addSet(SlotID, Weight, Reps, at: Date)
    case swap(SlotID, to: ExerciseID, at: Date), extendRest(by: Duration, at: Date), skipRest(at: Date)
    case finish(at: Date), discard(at: Date)
}
public enum LiveConnectionState: Equatable, Sendable { case solo, connected(Channel), reconnecting, degraded(Channel) }
public enum Channel: Equatable, Sendable { case mirroring, watchConnectivity }
public protocol WorkoutSessionClient: Sendable {
    var states: AsyncStream<WorkoutState> { get }             // replays current state to a new subscriber first
    var connection: AsyncStream<LiveConnectionState> { get }
    func send(_ intent: WorkoutIntent) async                  // never throws; logging never blocks on transport
    func resumeIfNeeded() async -> WorkoutState?              // launch: unfinished log → replay
    var hasWatchParticipant: Bool { get async }               // F16 uses it to decide phone-only Health save
}
public enum WireFrame: Codable, Sendable, Equatable {         // what goes over any transport
    case envelopes([EventEnvelope])
    case handshake(workoutID: WorkoutID, highestSeq: [DeviceID: UInt64], phase: WorkoutState.Phase)
    case replayRequest(workoutID: WorkoutID, from: [DeviceID: UInt64])
}
public protocol LiveWorkoutTransport: Sendable {
    var incoming: AsyncStream<WireFrame> { get }
    var link: AsyncStream<Bool> { get }                       // peer reachable on this transport
    func send(_ frame: WireFrame) async throws               // throws TransportError.timeout / .unreachable / .tooLarge
}
```
Rules (each maps to a criterion):
- **Codec.** `EnvelopeCodec.encode(WireFrame) -> Data`: 1 magic byte `0x4C`, 1 version byte (`1`), then JSON (`JSONEncoder` with `.iso8601` dates, sorted keys). Decoder rejects unknown magic, and for a newer version decodes only the fields it knows (forward-compatible enums: unknown `WorkoutEvent` cases decode to `.unknown` and are skipped by the reducer — add `.unknown` to `WorkoutEvent` if F04 lacks it; additive). Frames are split so no `Data` exceeds **60 000 bytes** (WC `sendMessageData` measured ceiling 65 536, R1 §2.6; mirroring has no documented limit, R1 §2.4 — use the same bound).
- **Actor.** `WorkoutSessionActor` (in `LedgerSync`, conforms to `WorkoutSessionClient`) holds `log: [EventEnvelope]`, `seen: Set<EnvelopeKey>` keyed `(device, seq)`, `nextSeq`, `deviceID` (F05 `device` table). `send(intent)` → envelope (own device, `nextSeq += 1`, `wallClock` from the intent's date) → `WorkoutEngine.reduce` → persist (`WorkoutEventStore`) → publish state → execute effects: `.persistEnvelope`, `.transmitEnvelope` (transport, fire-and-await with 3 s timeout, never blocking `send`), others forwarded to injected `EffectSink` (haptics/notifications/live activity/health — bound in the app shells). Remote frames: dedupe by `seen`, append, **rebuild by `WorkoutEngine.replay`** (ADR-004 rule 2), persist, publish; remote envelopes execute only local-side effects (`.haptic`, `.updateLiveActivity`, `.scheduleRestNotification`), never `.transmitEnvelope`.
- **Double start.** If two `.started` envelopes with different `WorkoutID`s arrive within 60 s, the earlier `(wallClock, device)` wins; the loser's log is discarded on both devices and the UI re-renders. Phone-initiated start = phone sends `.start` then `requestWatchStart()`; the watch adopts the phone's `.started` when it arrives (WC boost or mirror); if none arrives within 5 s after `.startRequestedByPhone`, the watch starts its own (F19 cached day) and the rule above resolves it.
- **Transports.** `MirroringTransport` wraps `RemoteSessionChannel`: batches envelopes produced within 150 ms into one frame; each `send` is wrapped in a **3 s watchdog** (`continuousClock`) because `sendToRemoteWorkoutSession` may never return (R1 §2.5 #2); on timeout the transport reports `.degraded(.mirroring)` and stays degraded for that workout (a reboot is the only known cure), and one retry is made on "Remote session delegate is not set up" (gotcha 3). `WCBoostTransport` sends the same frames via `WCSession.sendMessageData` only while `isReachable`, errors are swallowed with a log line (delivery is not guaranteed by design, ADR-005 §5). `CompositeTransport` fans out to both, merges `incoming`, and derives `LiveConnectionState`: `.connected(.mirroring)` if the channel is up, else `.connected(.watchConnectivity)` if reachable, else `.reconnecting` for 30 s after a drop, else `.solo`.
- **Handshake / gap replay.** On every `link == true` transition and on launch-resume: send `.handshake(highestSeq: vector)`; on receipt, reply with `.envelopes` of every local envelope whose `(device, seq)` exceeds the peer's vector (covers both own and relayed envelopes, so a reinstalled phone heals too), then send our own handshake if we have not in the last 10 s. `.replayRequest` is the explicit form used after a decode error.
- **Persistence.** Every produced or received envelope is written through `WorkoutEventStore` before publish; on launch `resumeIfNeeded()` replays an unfinished log and, if `phase == .live`, emits the handshake when a link appears. Compaction after `finished` is F05's responsibility and is triggered by the actor after `WorkoutRepository` materialisation commits.
- **DTS ordering (R1 §2.5, ADR-005 §4).** The actor sends nothing on mirroring until F16 emits `.prepared`; the first frame after `.mirrorConnected` is always the handshake.

## Acceptance criteria
1. Given any `WireFrame`, when encoded then decoded, then it round-trips (`Equatable`) and the data starts with `0x4C 0x01`.
2. Given 400 envelopes of 300 bytes, when encoded, then no frame exceeds 60 000 bytes and their concatenated decode equals the input.
3. Given a version-2 payload with an unknown event case, when decoded by version 1, then decoding succeeds and the reducer state is unchanged by that envelope.
4. Given two actors on a `FakeTransport` with `loss = 0.3, reorder = true, duplicate = 0.2`, when 200 random intents are sent from both sides and the transport is then flushed, then both actors' `WorkoutState` are equal (property test, 100 seeds).
5. Given a partition (`FakeTransport.partitioned = true`) during which both sides log sets and one extends rest, when the partition heals, then one handshake each way is observed, the gaps are replayed, and states converge without any envelope applied twice.
6. Given the mirroring fake `hang = true`, when the actor sends, then `send(intent)` returns in < 50 ms, the state is published immediately, the connection becomes `.degraded(.mirroring)` within 3 s, and the frame is delivered via the WC fake.
7. Given the watch is `.solo` for 10 min while 12 sets are logged, when the phone reconnects, then the phone shows all 12 within 5 s (**device**) and the fake-transport equivalent within one handshake round.
8. Given phone-initiated start, when the watch receives `.startRequestedByPhone` and the phone's `.started` arrives within 5 s, then both devices carry one `WorkoutID`; when it arrives after the watch started its own, then the earlier `(wallClock, device)` wins on both.
9. Given a remote `.setLogged`, when applied, then `.haptic(.setLogged)` is executed locally and `.transmitEnvelope` is not.
10. Given the app is killed mid-workout, when relaunched, then `resumeIfNeeded()` returns the replayed state and the next link emits a handshake (integration with in-memory `WorkoutEventStore`).
11. Given `finish` on the phone while the watch is unreachable, when the watch reconnects, then it applies `.finished`, ends its HealthKit session (F16) and both histories hold one workout (**device**; fake-backed unit test for the ordering).
12. Given the phone's `ActiveWorkoutStore`, when the transport reports `.reconnecting`, then the header shows "Watch not connected — logging continues" (watch copy: "iPhone not connected — logging continues") and every control stays enabled.
13. Given a set logged on the watch while `.connected(.watchConnectivity)`, when measured on device, then the phone row ticks in < 1 s (architecture §15; **device**, signpost `sync.roundtrip`).

## Test plan
- Unit (LedgerSyncTests): `test_codec_roundTrip`, `test_codec_magicAndVersion`, `test_codec_splitsAt60000Bytes`, `test_codec_unknownEventIsSkipped`, `test_actor_localIntentAssignsMonotonicSeq`, `test_actor_dedupesByDeviceSeq`, `test_actor_remoteEffectsExcludeTransmit`, `test_actor_doubleStart_earlierWins`, `test_actor_sendNeverBlocksOnTransport`, `test_mirroring_batches150ms`, `test_mirroring_watchdogDegradesAfter3s`, `test_mirroring_retriesOnDelegateNotSetUp`, `test_wcBoost_onlyWhenReachable`, `test_composite_connectionStateDerivation`, `test_handshake_replaysGapFromVector`, `test_handshake_onLinkUp_andResume`
- Property (LedgerSyncTests): `test_property_convergence_lossReorderDuplicate`, `test_property_partitionHeal`, `test_property_idempotentReplay`
- Integration (LedgerPersistenceTests): `test_eventStore_persistsBeforePublish`, `test_resume_replaysUnfinishedLog`
- Snapshot (FeatureWorkoutTests): `ActiveWorkoutHeader` × {connected, reconnecting, solo} × {light, dark} × {default, XL}
- Device (F20): scenarios 1–10 there reference criteria 7, 11, 13.

## Non-functional
- Performance budget: set logged → other device < 1 s while reachable (§15); actor `send` < 5 ms on watch (replay of ≤ 500 envelopes < 20 ms).
- Accessibility: connection line has an accessibility label; not announced repeatedly (`.accessibilityAddTraits(.updatesFrequently)` avoided).
- Offline behaviour: everything works `.solo`; the watch never waits on transport; envelopes persist locally first.

## Risks / unknowns
- Spec §5.3 says "single source of truth: phone" and §5.2 says the watch `onLog` path is not superset-aware; ADR-004/005 and decision #6 override both — one reducer, symmetric log, watch authoritative for HealthKit only.
- Mirroring delivery "several minutes between delegate calls" while the phone app is suspended (R1 §2.3) — WC boost covers the reachable case; unreachable + suspended is simply late, healed by handshake.
- `WCSession.sendMessageData` iPhone→watch does not wake the watch app (R1 §2.6); during a workout the watch is frontmost so this is moot.
- The `workoutSession` DI key is new (architecture §13 lists none) — record in implementation-notes.

## Definition of Done
Inherits `docs/engineering-standards.md` §12, plus:
- [ ] Property tests run 100 seeds in CI in < 30 s; seeds printed on failure.
- [ ] Two PRs: (a) `LedgerSync` + tests, (b) `FeatureWorkout` adoption; each ≤ 500 lines.
- [ ] `LedgerSync` imports `WatchConnectivity` only; `Package.swift` diff reviewed against architecture §3.
- [ ] Signposts `sync.send`, `sync.roundtrip`, `sync.handshake` present (category `sync`).

---
_Filled in by agents during delivery:_
- `F17-live-sync/implementation-notes.md`
- `F17-live-sync/test-findings.md`
- `F17-live-sync/review.md`

## Inputs from F04 (2026-09-29)

F04 owns the pure engine and the `WorkoutEventStore` contract. F17 owns the host that runs them. The rules
below are fixed by F04's fix rounds and its re-plan (2026-09-29; ADR-004 amendment, "The clock rule"
onwards). Where they contradict this brief, they win, and the brief should be amended.

1. **The host loop** (re-plan 2026-09-29: one path per source). `reduce` keeps no log and must never see an
   envelope twice.
   - Own action: stamp it with the HLC, `reduce` it, run `reduce`'s effects in order (`.persist` appends it
     to the store before `.transmit` sends it). The HLC sorts it after everything stored, so this equals
     `replay`.
   - Received frames: append every envelope to `WorkoutEventStore` first, whatever it holds. If `append`
     stored anything new, rebuild with `WorkoutEngine.replay` of the stored log and run
     `WorkoutEngine.effects(from: old, to: new)`. Never reduce a received envelope.
   - The "Actor" rule above ("dedupe by `seen`, append, rebuild by replay") is this loop; its remote
     effects are item 2's.
2. **Remote effects are `effects(from:to:)`'s**, and nothing else:
   - at most one `.haptic(.setLogged)` per rebuild, while the workout is live, when at least one set is done
     that was not before. A single remote set buzzes (criterion 9 stands); a reconnect that brings many sets
     buzzes once (Pete); a rebuild that ends finished or discarded never buzzes, even for a late set.
     Criterion 9 needs companion cases for the batch and the terminal;
   - materialise, `discardLog`, schedule or cancel of the rest notification, and `.updateLiveActivity`;
   - it re-emits `.materialize` whenever a finished state changes, including a rebuild from `nil` when
     both finishes arrived before the `started`;
   - it emits `.discardLog` when a late discard sorts before a finish that was already materialised.
     F05 must then delete that workout; decide who owns that.
   - The launch step (item 4) plays no haptic: nothing was just logged.
3. **HLC recovery.** Before stamping anything after a launch, set the clock's `newest` to the largest
   stored `wallClock` across `WorkoutEventStore.uncompactedWorkoutIDs()`. Skip a stored stamp your drift
   bound would reject on receipt. The drift bound itself is still F17's (F04 fix round 1, finding 6).
4. **Launch step and compaction.**
   - `liveWorkoutIDs()` is gone. `uncompactedWorkoutIDs()` lists every stored log. Classify each by
     `replay`: live means resume; finished or discarded means materialise or drop, then compact.
   - A log that replays to `nil` is **never compacted**. Keep it, and request a resend.
   - **Open for F17:** should the handshake base be the highest *contiguous* `seq` per device, rather than
     `highestSeq`? With the maximum, a dropped seq 1–2 followed by a received seq 3 never heals.
     `EventStoreAdversarialTests.holeBeforeTerminal_isKept_untilTheResendHeals` pins the hole.
5. **Malformed envelopes** (`EventEnvelope.isWellFormed`) are no-ops for the engine but stay stored. An
   envelope is malformed only when a date it carries is not finite or a rest length is outside
   `0 ... longestRest`. There is no time window (Pete, 2026-09-29), so a "Still lifting?" Finish backdated
   days is kept.
   - A NaN date is unequal to itself, so a store that compares envelopes with `==` would call a re-sent
     copy a conflict. JSON cannot carry one. Reject non-finite dates when decoding a wire frame, before
     anything is stored.
6. **Lossless date encoding.** The codec above uses `.iso8601`, which drops fractional seconds. The
   sender would then sort its own envelope by the precise stamp and the receiver by the truncated one,
   and the devices diverge. Encode dates losslessly (the default `.deferredToDate` round-trips exactly,
   `EventCodableTests`), or truncate `wallClock` when the envelope is created.
7. **Renamed event labels** (SwiftLint `identifier_name` rejects `at:`, `to:`, `by:`):

   | ADR-004 / brief | F04 |
   |---|---|
   | `setLogged(…, at:)` | `setLogged(…, doneAt:)` |
   | `exerciseSwapped(…, to:, …)` | `exerciseSwapped(…, exerciseID:, …)` |
   | `restExtended(by:)` | `restExtended(amount:extendsShownRest:tappedAt:)` |
   | `finished(at:)`, `discarded(at:)` | `finished(endedAt:)`, `discarded(endedAt:)` |
   | `Effect.scheduleRestNotification(at:)` | `Effect.scheduleRestNotification(endsAt:)` |

   `WorkoutIntent.extendRest` must carry what the screen showed. The UI sets `extendsShownRest` when its
   rest had time left (`RestTimer.remaining(at: now) > .zero`), and `tappedAt` is the intent's date.
8. **Out of scope for F04, noted by its tester (round 3):**
   - *Dropping a log at the terminal:* after `.discardLog` or a compaction, a partitioned peer's late
     envelopes wait in a log that replays to `nil` for a resend that never comes; drop or compact only
     after the peer acknowledges the terminal, or keep a tombstone.
   - *Drift bound:* still yours; with no payload window a peer far ahead no longer drops this device's
     actions, but it still drags every stamp.
   - *F05's stale brief:* criterion 8's `liveWorkoutIDs()` is now `uncompactedWorkoutIDs()`, and its
     `wall_clock TEXT` column must keep full precision (the contract suite now fails a lossy store).
