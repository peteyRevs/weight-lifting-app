# F17 — implementation notes

## Slice plan (G1, 2026-11-25)

From the brief, its "Inputs from F04 / F05 / F10 S8a" sections, ADR-004/005, architecture §6, §8, §13, R1 §2.3–2.6,
F16's implementation notes and main `b01cfcc`. Each slice branches from main once the previous one has merged (no
stacked PRs), is green alone, and stays under ~900 changed lines with its tests (hard cap 1,000). The brief's "two
PRs of ≤ 500 lines" predates both F10 (which already moved the phone's store to the session client) and Pete's
larger-slice rule (2026-10-08).

| Slice | Contents | Criteria | Est. |
|---|---|---|---|
| **S1** wire format | `WireFrame` and `WireCodec` (magic `0x4C`, version 1, sorted-key JSON with exact dates, cut at 60 000 bytes, refusals) in `LedgerDomain/Sync/`; `WireCodecTests`. | 1, 2, 3 (as resolved below) | ~400 |
| **S2** transport contract + fake | `LiveWorkoutTransport` filled (`incoming`, `link`, `send`), `TransportError`, `LiveConnectionState` and `Channel` in LedgerDomain; `FakeLiveWorkoutTransport` over `FakeLinkBus<WireFrame>` (loss, duplication, delay/reorder, partition, hang knobs; its own manual time); the unimplemented stub and `ProtocolsAdversarialTests`' brief conformance grown to the protocol; fake tests. | test-plan fakes for 4–7 | ~750 |
| **S3** the host receives | `LocalWorkoutSessionActor` takes frames: receipt checks (stamp drift bound, F04 items 3 and 9), append before rebuild, `WorkoutEngine.replay` + `effects(from:to:)` (one haptic per rebuild, none at a terminal), the one-by-one retry on `conflictingEnvelope`, a peer-started workout becoming the live one, the clock observing received stamps; `hasWatchParticipant(_:)`. Tests over the in-memory store. | 9 (+ batch and terminal companions), part of 4 | ~850 |
| **S4** the host transmits + handshake | Own envelopes sent as `.transmit` runs, off the operation queue, under a 3 s timeout on an injected clock (`send` never waits on it); the contiguous vector; handshake on every link-up and after a resume; replies with what the peer's vector lacks, own handshake at most every 10 s; `.replayRequest` after `unreadable`; signposts `sync.send`, `sync.handshake`. Property tests on S2's fake: convergence under loss/reorder/duplication (100 seeds, printed on failure), partition-heal, idempotent replay; resume + handshake with the in-memory store. | 4, 5, 7 (fake), 10, 11 (ordering) | ~900 |
| **S5** double start | Two `started` envelopes with different `WorkoutID`s within 60 s: the earlier `(wallClock, device)` wins on both devices, the loser's log is dropped and the UI re-renders; the watch adopts the phone's `started` within 5 s of `.startRequestedByPhone`, else starts its own. Needs a broadcast over `HealthStore.events` (F16: one consumer), decided here. | 8 | ~700 |
| **S6** mirroring + composite | `MirroringTransport` over `RemoteSessionChannel`: 150 ms batching, 3 s watchdog, sticky `.degraded(.mirroring)`, one retry on "remote session delegate is not set up", nothing sent before `.prepared`, the handshake first after `.mirrorConnected`; `CompositeTransport`: fan-out, merged `incoming`, `LiveConnectionState` derivation (30 s `reconnecting`). Tests on a scripted channel and a manual clock (house pattern: `RestCoverClock`, F16's `ManualClock`). | 6, part of 12 | ~900 |
| **S7** WatchConnectivity + wiring | `WCBoostTransport` (`sendMessageData` while reachable, errors logged and swallowed) behind a session seam as `CompanionSessionActivator` does; one `WCSessionDelegate` registered at launch on both apps; both compositions build store → transports → host; `watchTookPart` bound to `hasWatchParticipant`; `onMirrorStart` reaches the host; a `liveConnection` key for the connection stream. | 13 (device), wiring for all | ~800 |
| **S8** connection line | The phone's workout header line "Watch not connected — logging continues" (watch copy "iPhone not connected — logging continues", for F18), controls stay enabled, accessibility label without `.updatesFrequently`; snapshots {connected, reconnecting, solo} × {light, dark} × {default, XL}; device checklist for criteria 7, 11, 13 (F20). | 12, device halves of 7, 11, 13 | ~600 |

S3 and S4 split again (receive versus transmit; handshake versus property tests) if either passes ~1,000 lines.

## Where the brief predates the repo, and how each is resolved

1. **The session client already exists** (F10 S2): `WorkoutSessionClient` is `updates()` / `current()` / `start` /
   `apply(WorkoutEvent)` / `finish` / `discard`, hosted by `LocalWorkoutSessionActor` in LedgerSync, with a
   contract suite in LedgerTestSupport, and the `workoutSession` key already exists (architecture §13). F17 does not
   add `WorkoutIntent`, a second `WorkoutSessionActor` or a new protocol: it adds the peer's frames and the transport
   to the existing host (S3, S4). The intents' timestamps are already the callers' (`@Dependency(\.date)`), and
   F04's renamed labels (`doneAt`, `tappedAt`, `extendsShownRest`, …) are what `apply` already takes.
   `resumeIfNeeded()` is the host's existing launch recovery (`LocalWorkoutSessionActor+Recovery`).
2. **`connection` and `hasWatchParticipant` stay off `WorkoutSessionClient`.** Adding requirements would grow the
   contract, the fake and the stub for something only the workout screen (S8) and F16's save read. The host exposes
   `hasWatchParticipant(_ workout:)` (any envelope of the workout's log from another device), which the phone's
   composition passes to `LiveHealthStore` as its `watchTookPart` closure (F16 S3b); the connection is its own
   stream (S6/S7, its key decided there).
3. **The phone's store already runs on the session client** (F10), so the brief's second PR ("switch
   `ActiveWorkoutStore` from its local reducer loop") is only the connection line (S8). The store is
   `FeatureWorkout/WorkoutStore.swift`.
4. **The codec is `WireCodec` in LedgerDomain**, not `EnvelopeCodec` in LedgerSync: `EnvelopeCodec` is already the
   store's per-row codec in `LedgerDomain/Storage` (F05). The wire codec is pure Foundation like it, so it sits in
   the domain (`LedgerDomain/Sync/`) and LedgerFakes' transport can use it without LedgerSync.
5. **Dates are exact, not `.iso8601`** (F04 item 6): `JSONEncoder`'s default `.deferredToDate`, which round-trips.
6. **No `.unknown` event case; a newer version is refused whole** (criterion 3 resolved). The brief's
   forward-compatible decode would let an older device fold a newer payload into a different workout, which F10
   S8a's ruling forbids ("require one payload version on both devices, or refuse a peer's newer rows"), and F05
   already keeps a store's unreadable rows rather than half-reading them. So `decode` throws
   `unsupportedVersion(v)` for any version but its own, and an unknown case under version 1 is `unreadable`; nothing
   is decoded, so nothing reaches the reducer. `WireCodec.version` rises with `EnvelopeCodec.version` (the first
   TestFlight build makes payload changes raise it) or with a change of `WireFrame`'s shape. How the host answers a
   peer on another version (no replay request, which would loop; a line telling the lifter to update) is S4's.
7. **Non-finite dates never cross the wire** (F04 item 5, F05): JSON cannot carry ±∞ or NaN, so `encode` throws
   `unencodable` and a `1e400` makes a frame `unreadable`; no receiver can store such a stamp. The drift bound on
   finite stamps (F04 items 3 and 9) is the host's receipt check (S3).
8. **The handshake carries the highest contiguous `seq` per device** (F04 item 4's open question): with the
   highest stored `seq`, a lost seq 1–2 under a received 3 never heals. `WireFrame.handshake` and `.replayRequest`
   carry `contiguousSeq`, not `highestSeq`. The brief's `phase` is dropped: no rule reads it, the envelopes carry
   the terminal, and keeping a compacted log's tombstone (F04 item 8) is the host's.
9. **Phase type:** the brief's `WorkoutState.Phase` is `WorkoutPhase`; `Channel`, `LiveConnectionState` and
   `TransportError` land with the protocol in S2, in LedgerDomain beside `LiveWorkoutTransport`
   (`Protocols/Transports.swift`), not a new `Sync/WorkoutSessionClient.swift`.
10. **Fakes live in LedgerFakes** (ADR-008), not `LedgerTestSupport/Fakes`; `FakeLiveWorkoutTransport` is already
    declared there (empty, F07) and is grown over `FakeLinkBus` in S2. testing-strategy §2.3's `TestClock` is not
    used: fake time is the bus's own, and the host's timeouts take an injected clock in the `ManualClock` pattern.
11. **F16 shapes F17 builds on:** `RemoteSessionChannel` is `connection: AsyncStream<Bool>`, `incoming:
    AsyncStream<[Data]>` (one consumer each) and `send(Data)` with no timeout of its own (the watchdog is S6's);
    `HealthStore.events` has one consumer (S5 adds the broadcast it needs); `noteStartRequestedByPhone()` reports
    the phone's request as `.startRequestedByPhone`; `onMirrorStart` is handed nil for the workout's id, which the
    host learns from the watch's first frame; `watchTookPart` is the seam `hasWatchParticipant` fills (S7).
12. **"Remote session delegate is not set up" has no `HealthError` case**: it reaches LedgerSync as
    `HealthError.underlying(code:)`. S6 retries once on that code, to be confirmed on device (F20), or on any
    `underlying` error if the code cannot be pinned.
13. **Coverage risk (S7):** `WCBoostTransport`'s `WCSession` adapter cannot run in a package test host. It stays a
    thin adapter behind a tested seam, as `CompanionSessionActivator` is; if LedgerSync's 90 % still cannot be met,
    the slice stops and asks Pete, as F16 did for `LedgerHealth/Watch/*`.
14. **`Package.swift`:** LedgerSync needs no new dependency (WatchConnectivity is a system framework it already
    imports behind `#if canImport`), and never HealthKit: mirroring is reached only through `RemoteSessionChannel`.

## Slice S1 (G1, 2026-11-25)

- **`WireFrame`** (`LedgerDomain/Sync/WireFrame.swift`): `.envelopes([EventEnvelope])`,
  `.handshake(workoutID:contiguousSeq:)`, `.replayRequest(workoutID:contiguousSeq:)`; `Hashable`, `Codable`,
  `Sendable`.
- **`WireCodec`** (`LedgerDomain/Sync/WireCodec.swift`): `encode(_:) throws -> [Data]`, `decode(_:) throws ->
  WireFrame`, `magic` `0x4C`, `version` 1, `frameLimit` 60 000; `WireCodecError` (`notAFrame`,
  `unsupportedVersion`, `unreadable`, `tooLarge`, `unencodable`).

### Decisions

1. **Cutting is by halving.** An `.envelopes` frame over the limit is cut in two halves, each encoded again, until
   every part fits; one envelope that does not fit alone throws `tooLarge`. Every part is measured as encoded, so
   no size is predicted, and order is kept. 400 envelopes of ~300 bytes become a few frames; the extra encodes cost
   little against the ≤ 500-envelope replays the budget names.
2. **`tooLarge` is an error, not a silent drop.** A large workout's `started` snapshot (12 exercises × 9 rows)
   measures well under half the limit (`encode_largeStartFitsOneFrame`), so only a damaged envelope can hit it;
   the host (S4) logs its key and sends the rest.
3. **A decode error carries no underlying error** (`unreadable`), so `WireCodecError` stays `Equatable` and no
   decoder text can reach a log with health values in it.
4. **A frame read from a slice decodes** (`decode` indexes from `startIndex`), since a transport may hand one out
   of a larger buffer.

## Slice S2 (G1, 2026-11-25)

- **`LiveWorkoutTransport`** (`LedgerDomain/Protocols/Transports.swift`) is filled from the brief: `incoming:
  AsyncStream<WireFrame>`, `link: AsyncStream<Bool>` (the state when made, then each change; one consumer each, as
  `RemoteSessionChannel`'s streams), `send(_:) async throws`. Beside it: `TransportError` (`unreachable`, `timeout`,
  `tooLarge`), `Channel` (`mirroring`, `watchConnectivity`) and `LiveConnectionState` (`solo`, `connected`,
  `reconnecting`, `degraded`), all `Hashable` and `Sendable`.
- **`FakeLiveNetwork` + `FakeLiveWorkoutTransport`** (`LedgerFakes/FakeLiveWorkoutTransport.swift`): a phone and a
  watch over one `FakeLinkBus<WireFrame>`. The bus's `Link` gives delay (and so reordering), loss and duplication;
  `partition()` / `heal()` cut and join the pair (both links report it, a send throws `unreachable`, frames on
  their way are lost); `advance(by:)` / `flush()` move the network's time and hand what is due to each `incoming`.
  Each transport records `sent` and `received`; `hang` makes a send wait, announced on `hung`, until it is
  cancelled (`CancellationError`, nothing sent) or `hang` is turned off. A transport made alone (`init()`, the
  key's preview value) has its link down and refuses every send.
- **`UnimplementedLiveWorkoutTransport`** logs and throws from `send` and ends both streams;
  `ProtocolsAdversarialTests`' brief conformance is now a `BriefLiveWorkoutTransport` written from the brief.
- **Tests:** `FakeLiveWorkoutTransportTests` (LedgerSyncTests), the fake halves of criteria 4–7: loss 0.3,
  duplication 0.2 and reordering are the same for a seed over 100 seeds and each occurs; a partition and its heal;
  a hung send, cancelled and released; ten minutes solo then one flush. `UnimplementedStubTests.liveWorkoutTransport`.

### Decisions

1. **The fake carries frames, not bytes.** `WireCodec` is tested on its own (S1), and the real transports encode
   (S6, S7); a fake that encoded would only re-test the codec.
2. **A hang is an `AsyncStream<Never>` the send iterates**: cancelling the task ends the iteration, and turning
   `hang` off finishes every waiting stream (outside the lock, so nothing runs under it). No sleep, no clock. The
   `hung` stream lets a test wait for the send to be waiting without polling (the `ManualClock` pattern's
   announcement).
3. **The fakes' state is behind a `Mutex`**, as `FakeLinkBus`'s is: the network calls into its transports
   synchronously from `advance` and `flush`, which an actor could not do. No `@unchecked Sendable`.
4. **The fake transport moved out of `DeviceFakes.swift`** into its own file, as `FakeHealthStore` has.

### Deviations from the brief

1. **`partition()` / `heal()` and the bus's delay range** stand for the brief's `FakeTransport.partitioned = true`
   and `reorder = true`; the fake is `FakeLiveWorkoutTransport` (F07's name) made in pairs by `FakeLiveNetwork`.
2. **`TransportError.timeout`** is the watchdog's (S6); the fake never throws it or `tooLarge`, which only a real
   transport's encoding can.

## Slice S3 (G1, 2026-11-25)

- **`LocalWorkoutSessionActor.receive(_ envelopes:)`** (`LedgerSync/LocalWorkoutSessionActor+Receive.swift`),
  queued like every call:
  1. **Receipt checks** drop, with the key logged: an envelope with a date that is not finite (the new
     `EventEnvelope.hasFiniteDates`), and one stamped more than `driftBound` (1 h) ahead of this device's clock.
  2. **Append per workout before anything else.** On `EngineError.conflictingEnvelope` the batch is appended again
     one envelope at a time and only the conflicting ones are dropped. Any other store error throws and the next
     call recovers first, as an own `.persist` failure does.
  3. **Rebuild** with `WorkoutEngine.replay` of the stored log, and run `effects(from:to:)` against what readers
     were shown (the live state), or against the log without the new envelopes for a workout not shown:
     - the live workout: published with the rebuild's haptics, then the rest notification. An end the peer made
       completes as an own end does (`ending`, then `settle()`), unless the log holds unreadable rows: then it
       stays live, as `apply` keeps a finish it refuses;
     - no live workout and a live rebuild: the peer's workout becomes the live one, its own `seq` from the store
       (F04 item 9: joining mid-session buzzes once);
     - an ended workout no reader was shown: completed (saved or dropped) without an update;
     - a second live workout: kept in the store for S5's double-start rule;
     - a log that replays to nothing (its `started` has not arrived): kept; it folds in when the `started` comes.
  4. The clock observes every stored received stamp. This device's own envelopes relayed back move its `seq` on.
- **`hasWatchParticipant(_:)`**: another device's envelope in the workout's log, or one received for it by this
  host (a finished workout's log goes with its save). A store that cannot be read answers `true`.
- **`EventEnvelope.hasFiniteDates`** (LedgerDomain): `isWellFormed` is now `hasFiniteDates && hasValidValues`, one
  list of an event's dates (`dates`) and one of its value checks. It means exactly what it meant before; the whole
  engine suite passes unchanged.

### Decisions (made without asking; for review)

1. **The drift bound is 1 h ahead, with no bound behind.** A paired phone and watch keep network time, so their
   skew is seconds; an hour lets through any honest clock and keeps out a corrupt stamp, including the 2⁴⁴ s ones
   (F04 item 9). A device whose clock runs more than an hour behind its peer's drops the peer's envelopes (logged)
   until the clocks agree. A clock behind does no harm on the sender's side, since its envelopes only sort earlier.
2. **`hasWatchParticipant` answers `true` when the store cannot be read**: the phone then refuses its own Health
   save (`watchSavesThisWorkout`), so the worst case is a workout missing from Health, never one written twice.
   What it remembers after a log is compacted lasts only for this process: S7 wires the save so it asks before the
   end completes, or passes the answer along with the end.
3. **`receive` takes envelopes, not a `WireFrame`.** Handshakes and replay requests are S4's, which dispatches
   frames from the transport.
4. **A waiting end is completed before anything is received** (`settle()` first, as `apply` does). If its save
   keeps failing, `receive` throws and stores nothing; the peer's handshake replays those envelopes later.
5. **An ended workout nobody was shown is not published.** The client's contract publishes an end only to readers
   who saw the workout live; History reads it from the repository.
6. **No haptic for an end by the peer**: `effects(from:to:)` never buzzes at an end (F04 item 2).

## Slice S4a (G1, 2026-11-25)

S4 splits: **S4a** (this slice) is the host on a transport; **S4b** is the two-host harness and the property
tests (criteria 4, 5, 7 on the fake; the resume half of 10 is here).

- **`connect(_:clock:)`** (`LedgerSync/LocalWorkoutSessionActor+Transport.swift`), once for the host's life:
  - **Sending:** each own envelope goes to an outbox as `.transmit` runs, right after its `.persist`; one sender
    task sends the outbox in order, each send raced against `sendTimeout` (3 s) on the injected clock. A failure or a
    timeout is logged and not retried: the next handshake replays it. No call waits on a send (criterion 6, host
    half).
  - **Receiving:** a listener hands every frame to `receive(_ frame:)`, its errors logged.
  - **Link-up:** on every `true` of `link`, in turn and after recovery, a handshake for every log the store holds
    (live, ended and unsaved, or waiting for its `started`). A launch's resume is covered by the first link
    state (criterion 10). `connect` returns once that first state is taken, so no call races the first
    handshake.
- **`receive(_ frame:)`:** `.envelopes` as S3; when that throws, a `.replayRequest` for the frame's workouts
  (at most one per workout per `handshakeInterval`, 10 s) and the error is rethrown. This carries S3's decision 4
  forward: what a failed receipt did not store comes back from the peer. `.handshake`: the envelopes its vector
  lacks (own and relayed), then this host's handshake unless one went in the last 10 s. `.replayRequest`: the
  envelopes only.
- **The vector** is the highest contiguous `seq` per device (`contiguousSeq(of:)`), so a hole is replayed.
- **`FakeLiveWorkoutTransport.handed`**: each frame as it reaches the network, so a test waits for the host's
  sender without polling. `ManualClock` is copied into LedgerSyncTests' support from LedgerHealthTests'.

### Decisions (for review)

1. **`LiveConnectionState` is not the host's.** The host sees one transport and its `link: Bool`; which channel
   carries frames and whether mirroring is degraded is known only to `CompositeTransport`, so the derivation stays
   in S6, as planned. The host's contribution is the handshake on every link-up.
2. **The rate limit uses the host's injected date** (`now`), not the clock: one `Date` per workout, and the tests
   already set it.
3. **The host does its own 3 s timeout** as well as S6's mirroring watchdog: the sender is serial, so a transport
   that never returns would otherwise stop every later frame.
4. **Replies are not rate-limited**, only handshakes and replay requests, so two hosts can never ping-pong
   handshakes faster than one per 10 s per workout.
