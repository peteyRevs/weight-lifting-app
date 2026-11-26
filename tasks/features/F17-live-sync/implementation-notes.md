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
| **S5** double start | Two `started` envelopes with different `WorkoutID`s within 60 s: the earlier `(wallClock, device)` wins on both devices and the UI re-renders; the loser is saved to History when it holds set data, dropped only when it holds none (Pete 2026-11-25, option C; S5b); the watch adopts the phone's `started` within 5 s of `.startRequestedByPhone`, else starts its own. Needs a broadcast over `HealthStore.events` (F16: one consumer), decided here. | 8 | ~700 |
| **S6** mirroring + composite | `MirroringTransport` over `RemoteSessionChannel`: 150 ms batching, 3 s watchdog, sticky `.degraded(.mirroring)`, one retry on "remote session delegate is not set up", nothing sent before `.prepared`, the handshake first after `.mirrorConnected`; `CompositeTransport`: fan-out, merged `incoming`, `LiveConnectionState` derivation (30 s `reconnecting`). Tests on a scripted channel and a manual clock (house pattern: `RestCoverClock`, F16's `ManualClock`). | 6, part of 12 | ~900 |
| **S7** WatchConnectivity + wiring | `WCBoostTransport` (`sendMessageData` while reachable, errors logged and swallowed) behind a session seam as `CompanionSessionActivator` does; one `WCSessionDelegate` registered at launch on both apps; both compositions build store → transports → host; `watchTookPart` bound to `hasWatchParticipant`; `onMirrorStart` reaches the host; a `liveConnection` key for the connection stream. | 13 (device), wiring for all | ~800 |
| **S8** connection line | The phone's workout header line "Watch not connected — logging continues" (watch copy "iPhone not connected — logging continues", for F18), controls stay enabled, accessibility label without `.updatesFrequently`; snapshots {connected, reconnecting, solo} × {light, dark} × {default, XL}; device checklist for criteria 7, 11, 13 (F20). | 12, device halves of 7, 11, 13 | ~600 |

S3 and S4 split again (receive versus transmit; handshake versus property tests) if either passes ~1,000 lines. S7 splits into S7a (the WatchConnectivity transport) and S7b (the wiring).

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

## Slice S4b (G1, 2026-11-25)

The two-host harness and the property tests: the fake halves of criteria 4, 5 and 7. Tests only; S3 and S4a
held under them, so no product code changed.

- **`LiveSyncPair`** (`LedgerSyncTests/Support/LiveSyncPair.swift`): a phone host and a watch host, each over its
  own in-memory stores, joined by one `FakeLiveNetwork`, with one shared `SettableClock` as both hosts' date. One
  task drives it, and every step ends with both hosts at rest:
  - `step(by:)` moves the network and hands what arrived to the phone, waits for it to rest, then to the watch;
    `settle()` flushes and hands over until a round carries nothing (capped at 20 rounds), returning the rounds;
  - `partition()` / `heal()` cut and join the network and report the link to each host in turn;
  - `converged()`: both logs equal, and both hosts' `current()` equal to `WorkoutEngine.replay` of every envelope
    either device made (each device's own, from its store).
- **`HarnessTransport`** wraps each `FakeLiveWorkoutTransport`: sends go through it (so `sent` records them),
  but the host takes `incoming` and `link` from two **`GatedStream`s** the harness feeds. A gated stream knows
  when its one consumer has taken everything and asked for more; the host's listeners take the next element only
  when done with the last, so that is a barrier on the receiving side.
- **The sender's barrier is a marker:** `Side.rest()` hands the host `.handshake` for a workout nobody has. The
  host answers it in its turn, after everything queued before it, with its own handshake for that workout, and
  the transport swallows it and reports that the sender reached it. No sleep, no polling, no raised time limit.
- **`EditWriter`** (`Support/EditWriter.swift`): seeded random edits of the live workout on `SplitMix64`: log,
  unlog, retarget and add rows, move the cursor, start, extend and skip rests, 1–20 s apart.
- **`LiveSyncPropertyTests`** (`+Runs` holds the runs and what they read from the frames):
  - criterion 4: the phone starts, the watch takes it up on a clean link; then 200 edits from both sides on a link
    with 0–2 s delay, loss 0.3 and duplication 0.2, the network moving 0–2.5 s after 40 % of them and a partition
    toggled after 3 %; then a clean link, one reconnect, `settle()`, and `converged()`;
  - a control over the first four fixed seeds (under 2 s in a simulator, so not `.slow`): frames were lost, duplicated and reordered against the hosts, a partition
    happened, and at least one run was apart before the reconnect (the property has teeth);
  - criterion 5: in a partition both sides log 1–6 sets and one starts and extends a rest; after the heal, exactly
    one handshake each way, each side sends exactly the keys the other lacked and none twice, the logs have no key
    twice, and the hosts converge;
  - criterion 7: the watch logs 12 sets over 10 minutes while partitioned; after the heal `settle()` takes exactly
    two rounds (the handshakes, then one `.envelopes` frame of 12), and the phone has 12 rows done.

### Decisions (for review)

1. **"Then the transport is flushed" (criterion 4) is a reconnect.** A frame lost while the link is up is not
   resent (S4a: the next handshake replays it), and handshakes come with a link-up, so the run ends with a clean
   link that goes down and up once, then a flush to rest. A flush alone could never converge at loss 0.3.
2. **Seeds: 12 fixed seeds in PR runs and `swift test`; in the nightly, `LEDGER_PROPERTY_SEED_COUNT` capped at
   200.** The PR cut is the host contract's (testing-strategy §6). The cap departs from §6's "the nightly runs
   every seed of the lane" (2,000), for Pete to rule on: a run takes ~0.09 s on the Mac but ~0.6 s in a
   simulator, so 2,000 serial seeds would add about 20 minutes to each of `Nightly` and `Nightly-Watch`. 2,000
   seeds were run once on the Mac (`swift test`, nightly lane): all passed. The spec's "100 seeds in CI" is met
   by the nightly; the PR lane spends ~10 s on the suite in a simulator.
3. **The suite is `.serialized`.** Run in parallel, 2,000 cases crowded the suite's control test to 52 s of
   wall time against its one-minute limit; serially every test takes its own time.
4. **The harness drives receipt through the host's own listener and link task**, not by calling `receive`
   itself, so the transport path S4a wrote is the one under test; only the hop from network to `incoming` is the
   harness's.
5. **The marker depends on the host answering a handshake with its own** (S4a's reply). A host that stopped
   doing so would fail these tests by their time limit rather than by an expectation; `HostTransportTests` checks
   that reply directly and would fail first.
6. **Teeth were checked by mutation** (not committed): a vector of the highest stored `seq` instead of the
   contiguous one fails criterion 4 on every fixed seed.
7. **Out of scope here:** the double start (S5; the phone always starts), ends during a partition (criterion 11's
   ordering), the hung send (criterion 6, S6) and the device halves of 7.

## Slice S5a (G1, 2026-11-25)

S5 splits: **S5a** (this slice) is the broadcast of the health store's events and the watch's 5 s rule;
**S5b** is the double-start rule for the losing workout: Pete chose **C** on 2026-11-25 (below, and S5b).
Nothing in S5a drops a log: two live workouts are both kept, on both devices, as S3 keeps them.

- **`HealthEventBroadcast`** (`LedgerHealth/HealthEventBroadcast.swift`), an actor over `HealthStore.events`:
  `subscribe()` returns a new stream of what the store reports from then on (one subscribing before `run()` takes
  the first event gets everything, as the store's stream holds it); `run()` fans every event out until the store's
  stream ends or its task is cancelled, then ends every subscriber's stream, and a later subscriber's. A subscriber
  that stopped reading is dropped at the next event, as the host drops ended update streams. `run()` runs once.
- **`LocalWorkoutSessionActor+PhoneStart`** (LedgerSync):
  - `adoptsPhoneStart(clock:)`: true at once when a workout is live, or as soon as one becomes live (the phone's
    `started` arriving makes it live, S3); false after `phoneStartWait` (5 s) on the injected clock, or when
    cancelled;
  - `followPhoneStartRequests(_:clock:startOwn:)`: for each `.startRequestedByPhone`, in turn, `startOwn` unless
    the phone's workout was adopted; other events ignored; never starts after it was cancelled.
- **Tests:** `HealthEventBroadcastTests` (LedgerHealthTests); `HostPhoneStartTests` (LedgerSyncTests), on
  `LiveSyncPair` for criterion 8: the phone's `started` within the wait is adopted and the hosts converge on one
  workout; with none (partitioned) the watch starts its own after 5 s, and after the heal both logs are whole on
  both devices, each device keeping its own workout live.

### Decisions (for review)

1. **The broadcast is a separate actor the composition makes and runs**, not a change to `HealthStore.events`: the
   protocol, `LiveHealthStore`, `FakeHealthStore`, the stub and the brief conformance stay as they are, and the
   fan-out is in one place. An actor, not a `Mutex` (engineering-standards §4: product state lives in actors), and
   `run()` instead of a task it starts itself (§4: no fire-and-forget tasks), so its life is the caller's
   structured task. It lives in LedgerHealth, beside the store whose stream it shares; the host takes a plain
   `AsyncStream`, so LedgerSync does not depend on LedgerHealth.
2. **"Starts its own" is a closure.** The host does not know the watch's cached day (F19) or the session start
   (F16); the watch's composition or workout screen (F18) passes what starts them. Wiring the broadcast and the
   rule into `WatchComposition` waits for S7, which connects the host to its transports, and F18.
3. **Any live workout counts as adopted**, also one the lifter started on the watch before the request came: the
   watch never starts a second workout over one already live.
4. **The 5 s wait starts when the request is taken**, not at the phone's stamp: the watch's and phone's clocks
   are not compared here (S3 bounds drift only ahead).

### The losing workout (S5b): A/B/C/D, Pete chose C (2026-11-25)

The spec drops the loser's log on both devices. The only way to drop a log is `WorkoutEventStore.compact`, which
deletes it for good, and the loser can hold sets the lifter logged: the 60 s window compares the two `started`
stamps, not arrival, so a late phone `started` (slow link or partition) can arrive after minutes of sets on the
watch's own workout, which then loses. Options:
- **A.** Drop the loser only when it holds no set logged, retargeted or added; otherwise keep both (then C).
- **B.** Merge the loser's set edits into the winner as new envelopes, matched by (exercise, row): invasive, and
  fragile when the two days differ.
- **C (recommended).** Never delete: the winner goes on live on both devices; a loser with logged sets is saved as
  its own workout through the normal save, so it shows in History and Pete deletes it himself; an empty loser is
  dropped as in A.
- **D.** As the spec says: drop the loser's log, accepting the loss.

## Slice S5b (G1, 2026-11-25)

Pete's rule (option C, 2026-11-25), in `LocalWorkoutSessionActor+DoubleStart.swift`:

- **`resolveDoubleStarts()`**, run in turn after a receipt that stored a `started`, and by recovery when it finds
  more than one live log. Of the live logs whose `started` envelopes come from **different devices** and lie within
  `doubleStartWindow` (60 s) of the earliest, the earliest in the engine's order (`wallClock`, then device) wins:
  - when the workout shown lost, the winner becomes the live workout and is published (no haptic): the UI
    re-renders straight from the loser to the winner, without the loser's end in between;
  - **only the device that started a loser ends it**, with an envelope of its own: `finished(endedAt:)` at the
    loser's last stamp when its log holds anything but `started`, `exerciseSelected` and rest events, else
    `discarded`. It then completes the end as any end (`complete`: a finished loser is saved to history with its
    misses and its log dropped; a discarded one's log is dropped). The other device keeps the loser's log until
    that end arrives, then completes it as any ended workout it was not shown. One end, made once, so both devices
    reach the same outcome, nothing is saved twice, and no end answers another;
  - the end goes to the peer **in one frame with the loser's whole log**, so an end that arrives brings every set.
- **Recovery** resumes the later of two live logs as before, then applies the rule, so a device killed between
  storing the winner's `started` and ending its own loser settles it on launch.
- **A link-up resets the handshake rate limit** (`+Transport`, product fix): the double-start property found a
  watch that never learned the phone's workout, because its one request for it had been lost seconds before the
  last reconnect and the 10 s limit refused the next. What a host asked for before a link-up may have been lost
  with the link.
- **Tests:** `HostDoubleStartTests`: criterion 8 on `LiveSyncPair` for each device losing, with and without sets
  (saved on both with its sets / dropped on both; the winner live and converged on both); starts 61 s apart are no
  double start; recovery settles one; a saved loser's log relayed back is not saved over the whole one.
  `DoubleStartPropertyTests` (LiveSyncPropertyTests' seeds): starts 0–50 s apart (or 61–120 s), partitioned or
  racing on a lossy, duplicating, delaying link, sets logged on whatever each device shows; after a clean
  reconnect every set each device logged is done on it, live or in history, and within the window both show one
  converged workout. A mutation that discards every loser fails it on many seeds. `HostTransportTests` gains the
  rate-limit reset. `HostPhoneStartTests`' S5a test now expects the rule's outcome (the phone's earlier workout
  wins, the watch's empty one is dropped on both), not S3's interim "both kept".

### Decisions (for review)

1. **Health:** the loser is not saved to Health. The host never writes Health; Health's save follows the lifter's
   finish (F16, wired in S7/F18), and a loser's end is the host's, so no Health workout is made for it. The watch's
   HealthKit session goes on with the winner (F18).
2. **The loser's save is the normal finish save**, misses and program changes included, as Pete asked ("the same
   as a finished workout"). A loser of another program day therefore records misses on that day's slots.
3. **Only starts from different devices.** Two live logs of one device's own only damage makes (start refuses a
   second); recovery keeps resuming the later of those, as its test documents.
4. **A saved loser's log that comes back** (the end's frame was lost and the peer's handshake asked for its copy)
   is dropped, never saved over the whole one in history; an end is still sent so the peer completes its copy, with
   a `seq` above 2³² so it can never collide with one the peer holds.
5. **Residual gap, as for any finish (F04 item 8):** if the frame with the loser's end is lost and the peer's copy
   lacks some of its sets, the peer completes the partial copy it holds; the device that logged them keeps them
   whole in its history. Nothing is lost, but the two histories can differ until a history sync exists. Keeping a
   saved log until the peer acknowledges its end would close this, for both a finish and a loser.

## Slice S6 (G1, 2026-11-25)

Both transports in `LedgerSync/Transports/` (the spec's path), over the domain's `RemoteSessionChannel`: no
HealthKit, no new dependency. Neither is wired yet (S7 builds the compositions and runs them).

- **`MirroringTransport`** (an actor; its owner runs `run()` for its life, as `HealthEventBroadcast`):
  - **Nothing before `.prepared`:** a send while the channel's `connection` is false throws `unreachable` and
    keeps nothing. F16 reports `connection` true only after `.prepared` and the mirror's start (watch) or a
    mirrored session handed over (phone), so the channel's state is the gate; the transport reads no health events.
  - **Batching:** a frame handed into an empty queue begins a batch; at `batchWindow` (150 ms) on the injected
    clock the queue goes out, neighbouring `.envelopes` frames joined into one, cut by `WireCodec`. `send` returns
    once queued, so the host's serial sender can hand the next frame inside the window. A drop empties the queue.
  - **Handshake first after `.mirrorConnected`:** the first batch after each `connection` true leads with the
    first handshake queued in it; if none was queued, with an empty handshake for the batch's first workout.
  - **Watchdog:** each channel send races `watchdog` (3 s). The send runs as a task the race does not wait for
    (HealthKit's async `sendToRemoteWorkoutSession` need not return when cancelled); a hung one is kept and
    cancelled when `run()` ends. A hang makes the transport `degraded`: what is queued is dropped, and nothing more
    goes on the channel for the workouts it knew of then, also across reconnects, until a frame of a workout it
    had never seen is handed to it.
  - **One retry** of a send that fails with `HealthError.underlying` (notes, item 12: the "delegate is not set up"
    code is not pinned; F20 pins it on device). Other failures are logged and dropped.
  - Incoming: each `Data` of a batch decoded alone (every cut part is a whole frame, S1); one that cannot be read
    is logged and dropped. `status` (`down`, `open`, `degraded`) is the composite's view; `link` is the protocol's.
- **`CompositeTransport`** (an actor, `run()` runs the mirroring transport too): `send` goes to both channels at
  once and succeeds if either took it (else throws mirroring's error); `incoming` merges both; `link` and
  `connection` as below.
- **`LiveConnectionState`:** `.connected(.mirroring)` while mirroring is open; else, while WatchConnectivity is
  up, `.degraded(.mirroring)` after a hang or `.connected(.watchConnectivity)`; else `.reconnecting` for
  `reconnectWindow` (30 s) after the peer was last reachable (a timer task on the injected clock, cancelled when
  the peer is reached again); else `.solo` (also the state when made). Each change once.
- **`LiveWorkoutTransport.link`'s doc** now says what the host already does: a handshake on every `true`, and a
  transport may report `true` again when a second channel comes up.
- **Tests:** `MirroringTransportTests` on `ScriptedChannel` (Support: scripted answers, sends announced, a hang
  that ignores cancellation until released) and `ManualClock`: nothing before up, 150 ms batching and joining,
  handshake first (moved, or an empty one), the 3 s watchdog and its stickiness until a new workout, the one retry,
  an unencodable frame dropped, incoming decoding. `CompositeTransportTests` on `ScriptedChannel` + a
  `FakeLiveNetwork`: the state derivation including 30 s reconnecting, merged incoming, a send that neither channel
  takes, and criterion 6 with the host: `start` and `apply` return with no time gone by and are published, the
  connection becomes `.degraded(.mirroring)` at 3 s, and the frames reach the watch over WatchConnectivity.

### Decisions (for review)

1. **`send` returns when queued, not when sent.** With the host's serial sender, a send that waited for its batch
   could never batch two frames. The protocol's "returning means the frame left this device" is kept for the
   composite as a whole only in spirit: a queued mirrored frame can still be dropped by a drop or a hang, and the
   next handshake replays it, as for any lost frame.
2. **The empty handshake.** "The first frame after `.mirrorConnected` is always the handshake" cannot wait for the
   host's: with an empty store at link-up the host sends none, and a held batch would then never go. An empty
   vector is a true lower bound (it asks for the whole log of that workout); the peer replays it and answers with
   its own handshake. It happens only when no handshake reached the batch within 150 ms of the link-up, so in
   practice for a workout begun after the link came up, whose log is short.
3. **Degraded until a new workout, not for the process.** R1 §2.5 #2 says the hang stays for that workout; a new
   workout is a new HealthKit session, so the first frame of a workout the transport never saw clears it. Frames
   of old workouts then go on mirroring again (on the new session).
4. **The composite's `link` repeats `true`** when mirroring comes up while WatchConnectivity is up (and on each
   new mirrored session the phone is handed), so the host's link-up handshakes reach the new channel first. The
   host's link-up round is idempotent; at worst a peer answers a handshake on both channels twice.
5. **No frame dedupe in the composite.** The host stores envelopes by `(device, seq)` and replies to a handshake
   idempotently, so a frame arriving on both channels costs one extra reply at most; remembering frames to drop
   repeats would also drop a legitimate repeated handshake.
6. **Retry at once, under its own watchdog.** The blog's fix is "retry the first send"; no delay is documented.
7. **Unstructured tasks, kept and cancelled:** the hung sends and the reconnect timer. Both are owned by the actor
   and ended with `run()`; neither is a store's (engineering-standards §4). The reconnect timer carries a drop
   number, so a timer that fires late cannot close a later window.

## Slice S7a (G1, 2026-11-26)

S7 splits: **S7a** (this slice) is the WatchConnectivity transport and its one delegate; **S7b** is the wiring:
both compositions building store → transports → host and running them, `watchTookPart` bound to
`hasWatchParticipant`, `onMirrorStart` reaching the host, the `liveConnection` key, and on the watch the
`HealthEventBroadcast` with `followPhoneStartRequests(…startOwn:)`. All of S7 measured over 1,000 lines.

- **`WatchConnectivityTransport`** (`LedgerSync/Transports/`, the spec's `WCBoostTransport`): sends each frame as
  `WireCodec`'s parts, one `sendMessageData` each, only while the session says the peer is reachable (else
  `unreachable`, nothing sent); a message the session later reports as failed is logged and swallowed (ADR-005
  §5); `tooLarge` (or the codec's `unencodable`) refuses the frame. Each message that arrives is decoded alone onto
  `incoming`; one that cannot be read is logged and dropped. `link` is `false` when made, then each change of
  reachability once. No WatchConnectivity import: the session is the `MessageSession` seam, so the rules run and are
  tested on every platform, `swift test` included.
- **`CompanionSessionActivator` is the one `WCSessionDelegate`** on both apps, as before; it now owns the transport
  (`transport`, over `DefaultMessageSession`, the two `WCSession.default` calls) and feeds it: reachability after
  activation and on each `sessionReachabilityDidChange`, and every `session(_:didReceiveMessageData:)`.
- **Tests:** `WatchConnectivityTransportTests` on a stand-in session (only while reachable, failures swallowed, a
  400-envelope frame cut under 60 000 bytes and decoded back in order, `tooLarge` and `unencodable` refused, the
  link's changes, incoming decoding, and a host connected to it whose clock never moves handing over every own
  envelope); `CompanionSessionActivatorTests` gains the delegate feeding the transport.

### Decisions (for review)

1. **The name is `WatchConnectivityTransport`, on Apple's framework.** "WCBoost" in the spec is ADR-005 §3's "latency
   boost", not a library: no ADR names a third-party WatchConnectivity package and none is in `Package.swift`. The
   file sits where the spec puts `WCBoostTransport.swift`.
2. **A send returns once the session has the data** (S6's open question: can a WatchConnectivity send hang?).
   `sendMessageData` queues and returns; its delivery, or failure, is reported later through the error handler,
   which the transport only logs. So the transport never waits on the peer, and the host's serial sender is never
   held: the host test runs with a clock that never moves, so a send that waited could not have been ended by the
   host's 3 s timeout. The host's timeout stays for mirroring.
3. **No reply handler.** With `replyHandler: nil` the peer's `session(_:didReceiveMessageData:)` (without reply) is
   called, and the error handler still reports a failed delivery. A reply would only acknowledge what the
   handshakes already heal.
4. **Unreachable throws, failures later do not.** The composite needs to know whether either channel took a frame
   (S6); a frame handed to the session counts as taken, as a queued mirrored frame does (S6, decision 1).
5. **The last reachability sits behind a `Mutex`**: the delegate is called synchronously on WatchConnectivity's
   queue, engineering-standards §4's exception (as `MirroringStartRegistrar`). The transport is a final class with
   `let`s only; no `@unchecked Sendable`.
6. **One delegate, owned by the activator.** `WCSession` has a single delegate, so the live channel and F19's
   companion transport share the activator: the live channel owns messages (`sendMessageData`), F19 the
   application context, user info and files (ADR-005 §5). Until S7b connects the transport, nothing sends on
   either device, so nothing arrives.
7. **Coverage:** `DefaultMessageSession`'s two `WCSession.default` calls are the only lines no test runs (no
   WatchConnectivity in tests); the delegate methods that read the session run with `WCSession.default` unactivated,
   as the activator's existing test does.

### Device checks for F20

1. Phone and watch apps open, the watch app frontmost: Console (subsystem `com.petearevalo.Ledger`, category
   `sync`) shows "WCSession activation completed in state 2" on both, and no "A WatchConnectivity message failed".
2. Once S7b lands, with mirroring off (watch app not in a workout), a set logged on the watch ticks on the phone in
   under 1 s (criterion 13, signpost `sync.roundtrip`), and the reverse while the watch app is frontmost.
3. Watch app moved to the background with no workout: the phone hands nothing to WatchConnectivity (no "A
   WatchConnectivity message failed" in Console) until the watch is reachable again, and then its handshake goes
   first.
4. A message over the measured 65 536 bytes never appears: a replay of a long workout goes as several messages, and
   no "payloadTooLarge" (`WCError` 7012) is logged.

## Slice S7b (G1, 2026-11-26)

The wiring: both compositions build store → transports → host and run them.

- **The phone** (`AppComposition`): when the database opens it builds the host, then the health store from
  `Environment.makeHealthStore(HealthHooks)`, then, when the environment has a WatchConnectivity channel (the
  activator's transport), `CompositeTransport(mirroring: MirroringTransport(channel: healthStore.remoteChannel),
  watchConnectivity:)`. `HealthHooks.watchTookPart` is the host's `hasWatchParticipant`; `onMirrorStart` calls
  `connectLiveSync()`. `resume(in:)` calls it too, after the recovery and before WatchConnectivity is activated.
  `connectLiveSync()` runs once: it starts a task that runs the transport for the app's life and connects the host.
- **The watch** (`WatchComposition`): its database is a lazy `DatabaseLaunch` with `onOpen` back to the composition,
  as the phone's is. When the database opens it builds the host (bound as `workoutSession`, which the watch did not
  bind before) and the transport over the watch's `LiveHealthStore`. `connectLiveSync()` (from `resume(in:)`, once)
  runs the transport, a `HealthEventBroadcast` over the store's `events` and
  `followPhoneStartRequests(broadcast.subscribe(), startOwn: environment.startOwnWorkout)`, then connects the host.
- **The `liveConnection` key** (`LedgerDependencies`): `LiveConnectionClient` (LedgerDomain, beside
  `LiveConnectionState`), with `states() async -> AsyncStream<LiveConnectionState>`, one stream per reader.
  `CompositeTransport` conforms: each reader gets the state shown, then each change, until `run()` ends. Both
  compositions bind it to their transport. The stub's stream ends at once; the preview's `FakeLiveConnection` holds one
  state and ends (S8 grows it with changes, for the header's snapshots).
- **Tests:**
  - `LiveSyncWiringTests` (LedgerAppKitTests): a resume connects the host (an own envelope reaches the watch over
    WatchConnectivity) and `liveConnection` is the transport; `watchTookPart` answers what `hasWatchParticipant`
    answers, before and after the watch's envelope arrives; a mirrored start connects the host with no resume (a
    background launch); without a channel, nothing is connected.
  - `LiveSyncWiringTests` (LedgerWatchAppKitTests): the host is built, bound and connected; criterion 8's wiring
    (the phone's request, no phone workout within 5 s on a clock whose waits end at once, so the watch's
    `startOwnWorkout` runs); without a channel the host is still built.
  - `CompositeTransportTests`: `states()` with two readers and a late one; `DependencyKeysTests`,
    `PreviewValueTests` and `UnimplementedStubTests` gain the key.
  - **`HealthWiringTests`' first line** now reads `Environment.live(…).makeHealthStore(hooks) is LiveHealthStore`.
    It checks the same thing as before: the live environment's health store is the phone's `LiveHealthStore`. The
    store is now made from the hooks instead of held.

### Decisions (for review)

1. **The phone's health store is made when the database opens**, not in `Environment.live`, because its
   `watchTookPart` and `onMirrorStart` need the host. The handler is still assigned first in `boot()`, before the
   database opens; the registrar buffers what it is handed until the store reads it. `healthStore` was already bound
   only once the database is open, so `PhoneAppDelegate` sees no change.
2. **A mirrored start connects the host.** A background launch from mirroring may connect no scene, so `resume(in:)`
   may never run. The host's link-up runs its recovery first (`ready()`), so connecting is enough to resume the
   workout and send the handshakes. `onMirrorStart` gets nil for the workout's id (F16), and the host learns the
   workout from the watch's frames, so nothing else is needed. F21 adds the Live Activity to the same hook.
3. **The connection is not a `LaunchStep`.** It cannot fail (the host logs its own failures), so the launch-order
   tests and the root gate are unchanged. It runs after the recovery and before WatchConnectivity is activated, so
   the first reachability report finds the host connected.
4. **The live sync task is the composition's**, kept for the app's life. The composition root is not a store
   (engineering-standards §3–4), and S6 left `run()` to the transport's owner.
5. **No transport without both channels.** Tests and the package's host build pass none and connect nothing. A UI
   test on the simulator does connect: WatchConnectivity is unreachable and mirroring is down, so the state is
   `.solo`.
6. **`startOwnWorkout` is a seam that only logs** ("The watch would start its own workout here (F18/F19)"). Starting
   the watch's cached day (F19) from its workout screen (F18) belongs there. Until then, a phone start the watch does
   not adopt within 5 s starts nothing on the watch, and the phone's workout arrives later through the handshakes.
7. **`syncClock`** is injected in both environments (`ContinuousClock` in the app), shared by the transports, the
   host's send timeout and the phone-start wait.
8. **The watch now binds `workoutSession`** to its host. No watch screen reads it yet (F18).

### Device checks for F20

1. With the phone app killed, start a workout on the watch: the phone app relaunches in the background (mirroring)
   and Console (category `sync`) shows its handshake; opening the phone shows every set the watch logged (criterion 7).
2. The phone's workout header line is S8's; until then, check in Console that the connection moves to
   `connected(mirroring)` once the mirror is up, and to `connected(watchConnectivity)` with mirroring stopped.
3. A phone start request with the phone's `started` held back (airplane mode on the phone after the request): after
   5 s the watch logs "The watch would start its own workout here (F18/F19)". After F18/F19 this becomes criterion
   8's device half.
4. Criterion 13 (a watch set ticks on the phone in < 1 s over WatchConnectivity) runs once F18 gives the watch a
   screen that logs sets.
