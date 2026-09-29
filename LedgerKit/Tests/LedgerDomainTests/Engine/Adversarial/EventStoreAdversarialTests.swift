import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Round 2: `WorkoutEventStore.append` returning what it newly stored (finding 5's decision), and the
/// store's lifecycle lists (finding 8's decision) against what `replay` makes of each log.
@Suite("WorkoutEventStore · append and lifecycle (adversarial, round 2)", .tags(.domain))
struct EventStoreAdversarialTests {
    typealias Adv = EngineAdv
    typealias Probe = StoreProbe

    static let workout = Adv.workoutID

    @Test("A partial batch returns only its new envelopes, once each, in the order given (not sorted)")
    func append_partialBatch_returnsNewInGivenOrder() async throws {
        let store: any WorkoutEventStore = InMemoryEventStore()
        let skips = (1 ... 5).map { Probe.skip(UInt64($0)) }
        #expect(try await store.append([skips[1]]) == [skips[1]])
        #expect(try await store.append([skips[4], skips[1], skips[0], skips[4], skips[2]]) == [
            skips[4],
            skips[0],
            skips[2]
        ])
        #expect(try await store.append([skips[3], skips[2], skips[1]]) == [skips[3]])
        #expect(try await store.append([]).isEmpty)
        #expect(try await Set(store.envelopes(for: Self.workout)) == Set(skips))
    }

    @Test("Two different envelopes with one new key in the same batch reject the whole batch; a retry succeeds")
    func append_conflictWithinOneBatch_rejectsAll() async throws {
        let store: any WorkoutEventStore = InMemoryEventStore()
        let (first, second, rival) = (Probe.skip(1), Probe.skip(2), Probe.extend(2))
        await #expect(throws: EngineError.conflictingEnvelope(rival.key)) {
            try await store.append([first, second, rival])
        }
        #expect(try await store.envelopes(for: Self.workout).isEmpty)
        #expect(try await store.highestSeq(for: Self.workout, device: Adv.watch) == nil)
        #expect(try await store.append([first, second]) == [first, second])
    }

    @Test("Same key and event but another stamp is a different envelope: a conflict, not a duplicate")
    func append_sameEventOtherStamp_isConflict() async throws {
        let store: any WorkoutEventStore = InMemoryEventStore()
        let stored = Probe.skip(1)
        let restamped = Probe.skip(1, at: 1.5)
        _ = try await store.append([stored])
        await #expect(throws: EngineError.conflictingEnvelope(stored.key)) {
            try await store.append([restamped])
        }
        #expect(try await store.envelopes(for: Self.workout) == [stored])
    }

    @Test("One batch may carry the same key for two workouts: both are new")
    func append_sameKeyTwoWorkouts_oneBatch() async throws {
        let store: any WorkoutEventStore = InMemoryEventStore()
        let mine = Probe.skip(1)
        let theirs = Probe.skip(1, in: Probe.other)
        #expect(try await store.append([mine, theirs, mine]) == [mine, theirs])
    }

    @Test("Host path: a batch that repeats an envelope, then a half-new batch, reduce each new envelope exactly once")
    func host_reducesEachNewEnvelopeOnce() async throws {
        let log = Adv.env(Adv.logged(0, 0, doneAt: 10), Adv.watch, seq: 1, at: 10)
        let extend = Adv.env(.restExtended(amount: .seconds(30)), Adv.watch, seq: 2, at: 20)
        var host = StoringHost()
        let first = try await host.receive([Adv.start(), log, log])
        #expect(first.count(where: { $0 == .haptic(.setLogged) }) == 1)
        let before = host.state
        let second = try await host.receive([log, extend, log])
        #expect(second == WorkoutEngine.reduce(before, extend).1)
        #expect(host.state?.rest == RestTimer(endsAt: engineTime(190), total: .seconds(180)))
        #expect(try await host.replayed() == host.state)
    }
}

// MARK: - Lifecycle: live, unmaterialized, compacted

extension EventStoreAdversarialTests {
    /// The store's two lists for the fixture workout, and what its log replays to.
    struct Snapshot: Equatable {
        var live: Bool
        var unmaterialized: Bool
        var replayed: WorkoutPhase?
    }

    static func snapshot(_ store: any WorkoutEventStore) async throws -> Snapshot {
        try await Snapshot(
            live: store.liveWorkoutIDs().contains(workout),
            unmaterialized: store.unmaterializedWorkoutIDs().contains(workout),
            replayed: WorkoutEngine.replay(store.envelopes(for: workout))?.phase
        )
    }

    @Test("Lifecycle, finished path: early envelope, started, finished, compacted; each list agrees with replay")
    func lifecycle_finished() async throws {
        let store: any WorkoutEventStore = InMemoryEventStore()
        let early = Adv.env(Adv.logged(0, 0, doneAt: -5), Adv.watch, seq: 1, at: -5)
        _ = try await store.append([early])
        #expect(try await Self.snapshot(store) == Snapshot(live: false, unmaterialized: false, replayed: nil))
        _ = try await store.append([Adv.start()])
        #expect(try await Self.snapshot(store) == Snapshot(live: true, unmaterialized: false, replayed: .live))
        _ = try await store.append([Adv.env(.finished(endedAt: engineTime(100)), seq: 2, at: 100)])
        #expect(try await Self.snapshot(store) == Snapshot(live: false, unmaterialized: true, replayed: .finished))
        try await store.compact(workout: Self.workout)
        #expect(try await Self.snapshot(store) == Snapshot(live: false, unmaterialized: false, replayed: nil))
        #expect(try await store.highestSeq(for: Self.workout, device: Adv.phone) == nil)
    }

    @Test("Lifecycle, discarded path, and two racing terminals: listed unmaterialized; the first terminal decides")
    func lifecycle_discarded() async throws {
        let store: any WorkoutEventStore = InMemoryEventStore()
        _ = try await store.append([Adv.start()])
        _ = try await store.append([Adv.env(.discarded(endedAt: engineTime(100)), seq: 2, at: 100)])
        #expect(try await Self.snapshot(store) == Snapshot(live: false, unmaterialized: true, replayed: .discarded))
        _ = try await store.append([Adv.env(.finished(endedAt: engineTime(101)), Adv.watch, seq: 1, at: 101)])
        #expect(try await Self.snapshot(store) == Snapshot(live: false, unmaterialized: true, replayed: .discarded))
    }
}

// MARK: - Finding 11: the lists are predicates on event kinds, not on what replay makes of the log

extension EventStoreAdversarialTests {
    @Test("Finding 11 (documents): a log whose only started is unusable is listed live, yet replays to nil")
    func unusableStarted_isLive_butReplaysToNil() async throws {
        var ended = EventBuilders.seedSession()
        ended.phase = .finished
        let store: any WorkoutEventStore = InMemoryEventStore()
        _ = try await store.append([Adv.start(ended), Adv.env(Adv.logged(0, 0, doneAt: 5), seq: 2, at: 5)])
        #expect(try await Self.snapshot(store) == Snapshot(live: true, unmaterialized: false, replayed: nil))
    }

    @Test(
        """
        Finding 11 (documents): after compaction a peer's resend (seq > nil) leaves an orphan log: with no \
        terminal it is on neither list; with the peer's finish it is unmaterialized but replays to nil
        """
    )
    func compactedThenPeerResend_orphanLog() async throws {
        let store: any WorkoutEventStore = InMemoryEventStore()
        let watchLog = Adv.env(Adv.logged(0, 0, doneAt: 50), Adv.watch, seq: 1, at: 50)
        let watchFinish = Adv.env(.finished(endedAt: engineTime(100)), Adv.watch, seq: 2, at: 100)
        _ = try await store.append([Adv.start(), watchLog, watchFinish])
        try await store.compact(workout: Self.workout)
        // The handshake asks the watch for "seq > highestSeq", which compaction has reset to nil.
        #expect(try await store.highestSeq(for: Self.workout, device: Adv.watch) == nil)
        _ = try await store.append([watchLog])
        #expect(try await Self.snapshot(store) == Snapshot(live: false, unmaterialized: false, replayed: nil))
        _ = try await store.append([watchFinish])
        #expect(try await Self.snapshot(store) == Snapshot(live: false, unmaterialized: true, replayed: nil))
    }

    @Test(
        """
        Finding 11 (documents): a hole (the watch's seq 1–2 dropped, seq 3 = finish received) is invisible to \
        highestSeq, so "seq > N" never heals it, and the documented launch step compacts the finish away
        """
    )
    func holeBeforeTerminal_neverHeals_andLaunchStepDropsIt() async throws {
        let store: any WorkoutEventStore = InMemoryEventStore()
        let watchStart = Adv.start(EventBuilders.seedSession(), Adv.watch, seq: 1, at: 0)
        let watchLog = Adv.env(Adv.logged(0, 0, doneAt: 50), Adv.watch, seq: 2, at: 50)
        let watchFinish = Adv.env(.finished(endedAt: engineTime(100)), Adv.watch, seq: 3, at: 100)
        #expect(WorkoutEngine.replay([watchStart, watchLog, watchFinish])?.phase == .finished)
        _ = try await store.append([watchFinish])
        // The gap-replay handshake (ADR-004 rule 4) would ask the watch only for seq > 3.
        #expect(try await store.highestSeq(for: Self.workout, device: Adv.watch) == 3)
        #expect(try await Self.snapshot(store) == Snapshot(live: false, unmaterialized: true, replayed: nil))
        // Launch: for each unmaterialized workout, replay, materialise or drop, then compact. Replay is nil.
        for id in try await store.unmaterializedWorkoutIDs() {
            #expect(try await WorkoutEngine.replay(store.envelopes(for: id)) == nil)
            try await store.compact(workout: id)
        }
        #expect(try await Self.snapshot(store) == Snapshot(live: false, unmaterialized: false, replayed: nil))
    }
}
