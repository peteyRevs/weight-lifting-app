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
