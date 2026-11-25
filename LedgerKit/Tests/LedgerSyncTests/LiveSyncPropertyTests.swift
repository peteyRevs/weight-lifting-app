import Foundation
import LedgerDomain
import LedgerFakes
import LedgerSync
import LedgerTestSupport
import Testing

/// F17 S4b: two hosts over the fake network (`LiveSyncPair`), the fake halves of criteria 4, 5 and 7. Each run is
/// driven step by step from the test's own task, so a seed decides it whole; a failing seed is named in the
/// failure and joins `fixedSeeds` (testing-strategy §3 rule 5).
@Suite("Live sync · two hosts on the fake network", .tags(.sync, .property), .serialized, .timeLimit(.minutes(1)))
struct LiveSyncPropertyTests {
    typealias Side = LiveSyncPair.Side

    /// The seeds a PR run and `swift test` take. Their first four already meet every fault of the schedule
    /// against the hosts (`schedules_reachEveryFault`, kept to four so it stays under 2 s in a simulator).
    static let fixedSeeds: [UInt64] = (0 ..< 12).map(seed)

    /// In the nightly lane, `LEDGER_PROPERTY_SEED_COUNT` seeds up to `nightlySeedCount`, never fewer than
    /// `fixedSeeds`; the fixed seeds elsewhere. A run of two hosts costs hundreds of times an engine law's (about
    /// 0.1 s on a Mac, 0.6 s in a simulator), so the PR lane cuts it as the host contract's matrix is cut
    /// (testing-strategy §6), and the nightly stops at twice the spec's 100. The suite is serialized, so that its
    /// cases never crowd its other tests past their time limit.
    static let seeds: [UInt64] = {
        let configured = ProcessInfo.processInfo.environment["LEDGER_PROPERTY_SEED_COUNT"].flatMap(Int.init) ?? 0
        let count = min(configured, nightlySeedCount)
        return TestLane.isNightly && count > fixedSeeds.count ? (0 ..< count).map(seed) : fixedSeeds
    }()

    static let nightlySeedCount = 200

    static func seed(_ number: Int) -> UInt64 {
        UInt64(number) &* 104_729 &+ 31
    }

    static let workout = Sample.session.id

    /// Criterion 4's network: up to 2 s of delay (so frames overtake each other), a third lost, a fifth twice.
    static let faulty = FakeLiveNetwork.Link(delay: .zero ... .seconds(2), loss: 0.3, duplication: 0.2)

    @Test(
        "Criterion 4: 200 random edits from both sides under loss, reordering, duplication and partitions converge",
        arguments: seeds
    )
    func randomEdits_underFaults_converge(seed: UInt64) async throws {
        let run = try await Self.faultyRun(seed: seed)
        #expect(run.converged, "seed \(seed)")
    }

    @Test("The first fixed seeds' schedules lose, duplicate and reorder frames, partition, and leave hosts apart")
    func schedules_reachEveryFault() async throws {
        var reached = Reach()
        for seed in Self.fixedSeeds.prefix(4) {
            let run = try await Self.faultyRun(seed: seed)
            reached.add(run.reach)
        }
        #expect(reached.lost && reached.duplicated && reached.reordered && reached.partitioned)
        #expect(reached.apartBeforeReconnect)
    }

    @Test(
        "Criterion 5: edits on both sides of a partition are replayed after one handshake each way, once each",
        arguments: fixedSeeds
    )
    func partitionHeal_replaysEachGapOnce(seed: UInt64) async throws {
        let pair = try await Self.started(seed: seed)
        defer { pair.close() }
        var writer = EditWriter(seed: seed)
        await pair.partition()
        let extender = writer.coin() ? pair.phone : pair.watch
        for side in [pair.peer(of: extender), extender] {
            for _ in 0 ..< writer.int(in: 1 ... 6) {
                try await writer.logSet(on: side, pair)
            }
        }
        let now = pair.clock.now
        try await EditWriter.edit(extender, .restStarted(endsAt: now.addingTimeInterval(90), total: .seconds(90)))
        try await EditWriter.edit(extender, .restExtended(amount: .seconds(30), extendsShownRest: true, tappedAt: now))
        let extended = await extender.log().last { $0.device == extender.device }
        guard case .restExtended = extended?.event else {
            Issue.record("seed \(seed): the rest was not extended")
            return
        }
        let lacking = await (Self.lacking(pair.phone, pair), Self.lacking(pair.watch, pair))
        let sentBefore = (pair.phone.transport.base.sent.count, pair.watch.transport.base.sent.count)
        await pair.heal()
        await pair.settle()
        let phoneSent = Self.summary(pair.phone.transport.base.sent.dropFirst(sentBefore.0))
        let watchSent = Self.summary(pair.watch.transport.base.sent.dropFirst(sentBefore.1))
        #expect(phoneSent.handshakes == 1 && watchSent.handshakes == 1, "seed \(seed)")
        let repliedTheGaps = phoneSent.keys == lacking.0 && watchSent.keys == lacking.1
        #expect(repliedTheGaps, "seed \(seed): each side sends what the other lacks, each envelope once")
        #expect(!lacking.0.isEmpty && !lacking.1.isEmpty, "seed \(seed)")
        #expect(try await pair.converged(), "seed \(seed)")
        let logs = await (pair.phone.log(), pair.watch.log())
        #expect(Set(logs.0.map(\.key)).count == logs.0.count && logs.0.count == logs.1.count, "seed \(seed)")
    }

    @Test("Criterion 7: twelve sets logged on a watch solo for ten minutes reach the phone in one handshake round")
    func soloWatch_reachesThePhone_inOneRound() async throws {
        let pair = try await Self.started(seed: 7)
        defer { pair.close() }
        await pair.partition()
        let rows = Sample.session.exercises.indices.flatMap { exercise in
            Sample.session.exercises[exercise].sets.indices.map { (exercise, $0) }
        }
        for (exercise, row) in rows.prefix(12) {
            pair.clock.set(pair.clock.now.addingTimeInterval(50))
            await pair.step(by: .seconds(50))
            let done = Sample.logged(exercise, row, at: pair.clock.now.timeIntervalSince(EventBuilders.start))
            try await pair.watch.host.apply(done)
            await pair.watch.rest()
        }
        let sentBefore = pair.watch.transport.base.sent.count
        await pair.heal()
        #expect(await pair.settle() == 2) // the handshakes, then the reply
        let replies = Self.summary(pair.watch.transport.base.sent.dropFirst(sentBefore))
        #expect(replies.handshakes == 1 && replies.envelopeFrames == 1 && replies.keys.count == 12)
        let doneOnPhone = try await pair.phone.host.current()?.exercises.flatMap(\.sets).filter(\.isDone).count
        #expect(doneOnPhone == 12)
        #expect(try await pair.converged())
    }
}
