import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Round 3 (G2 after fix round 2): the host loop of ADR-004, on `LiteralHost`. Final fix round (re-plan
/// 2026-09-29, decision 3): the loop has one path for what a host receives, append then rebuild, and a
/// rebuild buzzes at most once.
@Suite("WorkoutEngine · literal host loop (adversarial, round 3)", .tags(.domain))
struct Round3HostAdversarialTests {
    typealias Adv = EngineAdv

    static let sample = Array(PropertySeed.all.prefix(100))

    @Test(
        """
        Property: hosts that follow ADR-004's loop literally stay on replay after every delivery under skew, \
        clock steps, partitions, lost and resent messages, copies and relaunches; they converge; their \
        notification and stored workout match the state; a delivery buzzes at most once
        """,
        .tags(.property),
        arguments: PropertySeed.all
    )
    func literalHost_convergesAndBuzzesOncePerDelivery(seed: PropertySeed) async throws {
        let scenario = try await Round3Scenario.run(seed: seed)
        let expected = WorkoutEngine.replay(scenario.everything)
        for host in scenario.hosts {
            #expect(host.mismatches == 0, "\(host.device) left replay \(host.mismatches) times")
            #expect(host.state == expected, "\(host.device) did not converge")
            #expect(host.largestBurst <= 1, "\(host.device) buzzed \(host.largestBurst) times for one delivery")
            #expect(host.notification == host.state?.rest?.endsAt, "\(host.device)'s notification is stale")
            switch host.state?.phase {
            case .finished:
                #expect(host.materialized == host.state, "\(host.device) stored another state")
            case .discarded:
                #expect(host.droppedLog)
            case .live, nil:
                #expect(host.materialized == nil && !host.droppedLog)
            }
        }
    }

    @Test("In random sessions, remote set logs buzz on the receiving device (F17 criterion 9)")
    func remoteSetLogs_buzz() async throws {
        var remote = 0
        for seed in Self.sample {
            let scenario = try await Round3Scenario.run(seed: seed)
            remote += scenario.hosts.reduce(0) { $0 + $1.haptics[.rebuild, default: 0] }
        }
        #expect(remote > 0)
    }
}

// MARK: - Finding 17: which envelopes count as "already applied"? (answered by decision 3: none; one path)

extension Round3HostAdversarialTests {
    /// A watch-started workout (decision #16). The phone gets the watch's seq 2 (a set log) before seq 1
    /// (the `started`), which a lost message and the resend handshake produce, then seq 3.
    static func lostFirstMessage() async throws -> LiteralHost {
        var watch = LiteralHost(Adv.watch, offset: 0)
        var phone = LiteralHost(Adv.phone, offset: 0)
        try await watch.create(.started(EventBuilders.seedSession()), real: 0)
        try await watch.create(Adv.logged(0, 0, doneAt: 10), real: 10)
        try await phone.receive([watch.outbox[1]])
        try await phone.receive([watch.outbox[0]])
        try await watch.create(Adv.logged(0, 1, doneAt: 200), real: 200)
        try await phone.receive([watch.outbox[2]])
        return phone
    }

    /// Final fix round (decision 3): the in-order path, and with it the two readings of "applied", is gone.
    @Test(
        """
        Finding 17: with a lost first message, the one-path loop stays on replay, shows the watch's first set \
        once the started arrives, and buzzes once for each delivery that brought a set
        """
    )
    func lostFirstMessage_staysOnReplay() async throws {
        let phone = try await Self.lostFirstMessage()
        #expect(phone.mismatches == 0)
        #expect(Adv.row(phone.state, 0, 0)?.isDone == true)
        #expect(Adv.row(phone.state, 0, 1)?.isDone == true)
        #expect(
            phone.haptics[.rebuild] == 2,
            "the started (bringing set 1) and set 2; the early set alone shows nothing"
        )
    }

    /// Final fix round (decision 3): every receipt rebuilds, so raw stamps no longer leave replay here.
    @Test(
        """
        Finding 17 (documents): without the hybrid logical clock, a third device that hears a peer's early \
        set log before the started stays on replay, because a received envelope is never reduced
        """
    )
    func rawStamps_oneLoopStaysOnReplay() async throws {
        var phone = LiteralHost(Adv.phone, offset: 0)
        var watch = LiteralHost(Adv.watch, offset: -10)
        var tablet = LiteralHost(Adv.tablet, offset: 0)
        (phone.hybrid, watch.hybrid, tablet.hybrid) = (false, false, false)
        try await phone.create(.started(EventBuilders.seedSession()), real: 100)
        try await watch.receive(phone.outbox)
        try await watch.create(Adv.logged(0, 0, doneAt: 91), real: 101)
        #expect(watch.outbox[0].wallClock < phone.outbox[0].wallClock, "raw stamp: 91 s < 100 s")
        try await tablet.receive(watch.outbox)
        try await tablet.receive(phone.outbox)
        #expect(tablet.mismatches == 0)
        #expect(Adv.row(tablet.state, 0, 0)?.isDone == true)
        #expect(Adv.row(Replica(watch.outbox + phone.outbox).state, 0, 0)?.isDone == true)
    }
}

// MARK: - Finding 18: a reconnect batch buzzes once (Pete's rule, decision 3)

extension Round3HostAdversarialTests {
    /// Final fix round (decision 3): the burst of five is now one buzz, whichever device acted meanwhile.
    @Test(
        """
        Finding 18: after a partition in which the watch logged five sets, the phone's reconnect batch buzzes \
        once, whether or not the phone acted during the partition
        """
    )
    func reconnectBatch_buzzesOnce() async throws {
        for skip in [nil, 300.0] {
            let phone = try await Self.partition(phoneSkipsAt: skip)
            #expect(phone.largestBurst == 1)
            #expect(phone.haptics[.rebuild] == 1)
        }
    }

    /// The phone starts; the watch, cut off, logs bench sets 1–5 at 60…780 s; the phone optionally taps
    /// Skip at `phoneSkipsAt`; then the phone gets the watch's five envelopes in one batch.
    static func partition(phoneSkipsAt skip: Double?) async throws -> LiteralHost {
        var phone = LiteralHost(Adv.phone, offset: 0)
        var watch = LiteralHost(Adv.watch, offset: 0)
        try await phone.create(.started(EventBuilders.seedSession()), real: 0)
        try await watch.receive(phone.outbox)
        for (row, real) in [60.0, 240, 420, 600, 780].enumerated() {
            try await watch.create(Adv.logged(0, row, doneAt: real), real: real)
        }
        if let skip {
            try await phone.create(.restSkipped, real: skip)
        }
        var generator = SeededGenerator(seed: 144)
        try await phone.receive(watch.outbox.shuffled(using: &generator))
        #expect(phone.mismatches == 0)
        #expect(phone.state?.doneSets == 5)
        return phone
    }
}

// MARK: - Finding 19: every host model runs the same rule for a remote set

extension Round3HostAdversarialTests {
    /// Final fix round (decision 3): both models now rebuild on receipt; the haptic comes from the rebuild.
    @Test("Finding 19: a single remote set log plays one haptic on LiteralHost and on SimHost alike (F17 criterion 9)")
    func remoteSetLog_buzzesOnEveryHostModel() async throws {
        let start = Adv.start()
        let remote = Adv.env(Adv.logged(0, 0, doneAt: 10), Adv.watch, seq: 1, at: 10)
        var literal = LiteralHost(Adv.phone, offset: 0)
        try await literal.receive([start])
        try await literal.receive([remote])
        #expect(literal.haptics[.rebuild] == 1)
        var sim = SimHost(Adv.phone, offset: 0)
        try await sim.receive([start])
        try await sim.receive([remote])
        #expect(sim.remoteHaptics == 1)
    }
}
