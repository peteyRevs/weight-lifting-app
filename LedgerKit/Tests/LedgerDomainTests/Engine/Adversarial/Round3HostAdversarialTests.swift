import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Round 3 (G2 after fix round 2): the host loop of ADR-004, as amended and corrected, on `LiteralHost`.
@Suite("WorkoutEngine · literal host loop (adversarial, round 3)", .tags(.domain))
struct Round3HostAdversarialTests {
    typealias Adv = EngineAdv

    static let sample = Array(PropertySeed.all.prefix(100))

    @Test(
        """
        Property: hosts that follow ADR-004's loop literally stay on replay after every delivery under skew, \
        clock steps, partitions, lost and resent messages, copies and relaunches; they converge; their \
        notification and stored workout match the state; a rebuild or relaunch never buzzes
        """,
        .tags(.property),
        arguments: PropertySeed.all
    )
    func literalHost_convergesAndRebuildsNeverBuzz(seed: PropertySeed) async throws {
        let scenario = try await Round3Scenario.run(seed: seed)
        let expected = WorkoutEngine.replay(scenario.everything)
        for host in scenario.hosts {
            #expect(host.mismatches == 0, "\(host.device) left replay \(host.mismatches) times")
            #expect(host.state == expected, "\(host.device) did not converge")
            #expect(host.haptics[.rebuild, default: 0] + host.haptics[.relaunch, default: 0] == 0)
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

    @Test(
        """
        The corrected rule is exercised: in random sessions, remote envelopes reduced in order play their \
        haptic on the receiving device (F17 criterion 9)
        """
    )
    func inOrderRemoteEnvelopes_buzz() async throws {
        var remote = 0
        for seed in Self.sample {
            let scenario = try await Round3Scenario.run(seed: seed)
            remote += scenario.hosts.reduce(0) { $0 + $1.haptics[.inOrder, default: 0] }
        }
        #expect(remote > 0)
    }
}

// MARK: - Finding 17 (spec question): which envelopes count as "already applied"?

extension Round3HostAdversarialTests {
    /// A watch-started workout (decision #16). The phone gets the watch's seq 2 (a set log) before seq 1
    /// (the `started`), which a lost message and the resend handshake produce.
    static func lostFirstMessage(_ applied: LiteralHost.Applied) async throws -> LiteralHost {
        var watch = LiteralHost(Adv.watch, offset: 0)
        var phone = LiteralHost(Adv.phone, offset: 0)
        phone.applied = applied
        try await watch.create(.started(EventBuilders.seedSession()), real: 0)
        try await watch.create(Adv.logged(0, 0, doneAt: 10), real: 10)
        try await phone.receive([watch.outbox[1]])
        try await phone.receive([watch.outbox[0]])
        try await watch.create(Adv.logged(0, 1, doneAt: 200), real: 200)
        try await phone.receive([watch.outbox[2]])
        return phone
    }

    @Test(
        """
        Finding 17 (documents): read as "every envelope handed to reduce", the loop holds with a lost first \
        message; read as "every envelope reduce accepted", the phone skips the watch's first set for good
        """
    )
    func appliedMeaning_decidesALostFirstMessage() async throws {
        let everyReduced = try await Self.lostFirstMessage(.everyReduced)
        #expect(everyReduced.mismatches == 0)
        #expect(Adv.row(everyReduced.state, 0, 0)?.isDone == true)
        let onlyAccepted = try await Self.lostFirstMessage(.onlyAccepted)
        #expect(onlyAccepted.mismatches == 2, "every apply after the started differs from replay")
        #expect(Adv.row(onlyAccepted.state, 0, 0)?.isDone == false, "the watch's first set is missing")
        #expect(await Adv.row(WorkoutEngine.replay(onlyAccepted.log), 0, 0)?.isDone == true)
        // At scale, under the hybrid logical clock with two or three devices.
        var diverged = 0
        for seed in Self.sample {
            let scenario = try await Round3Scenario.run(seed: seed, applied: .onlyAccepted)
            diverged += scenario.hosts.reduce(0) { $0 + $1.mismatches }
        }
        #expect(diverged > 0)
    }

    @Test(
        """
        Finding 17 (documents): without the hybrid logical clock, the literal loop leaves replay on a third \
        device that hears a peer's early set log before the started; a "state is not nil" guard rebuilds
        """
    )
    func rawStamps_literalLoopLeavesReplay() async throws {
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
        #expect(tablet.mismatches == 1)
        #expect(Adv.row(tablet.state, 0, 0)?.isDone == false)
        #expect(await Adv.row(WorkoutEngine.replay(tablet.log), 0, 0)?.isDone == true)
        // `Replica` (round 1) guards on a non-nil state and rebuilds instead.
        #expect(Adv.row(Replica(watch.outbox + phone.outbox).state, 0, 0)?.isDone == true)
    }
}

// MARK: - Finding 18 (spec question): the in-order path buzzes once per envelope of a reconnect batch

extension Round3HostAdversarialTests {
    @Test(
        """
        Finding 18 (documents): after a partition in which only the watch logged, the phone reduces the \
        reconnect batch in order and buzzes once per set, the burst the ADR says a reconnect does not cause
        """
    )
    func reconnectBatch_inOrder_buzzesPerSet() async throws {
        let quiet = try await Self.partition(phoneSkipsAt: nil)
        #expect(quiet.largestBurst == 5)
        #expect(quiet.haptics[.inOrder] == 5 && quiet.haptics[.rebuild] == nil)
        // Had the phone acted once during the partition, the same batch would rebuild, and play nothing.
        let busy = try await Self.partition(phoneSkipsAt: 300)
        #expect(busy.largestBurst == 0 && busy.haptics[.inOrder] == nil)
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
        try await phone.receive(watch.outbox.shuffled())
        #expect(phone.mismatches == 0)
        return phone
    }
}

// MARK: - Finding 19 (minor bug): the round-2 host model still runs the superseded remote-effects rule

extension Round3HostAdversarialTests {
    @Test(
        """
        Finding 19: a remote set log that sorts after everything a host applied is reduced in order, and \
        per the orchestrator's correction plays its haptic there (F17 criterion 9); SimHost plays none
        """
    )
    func simHost_playsTheInOrderRemoteHaptic() async throws {
        let start = Adv.start()
        let remote = Adv.env(Adv.logged(0, 0, doneAt: 10), Adv.watch, seq: 1, at: 10)
        var literal = LiteralHost(Adv.phone, offset: 0)
        try await literal.receive([start])
        try await literal.receive([remote])
        #expect(literal.haptics[.inOrder] == 1)
        var sim = SimHost(Adv.phone, offset: 0)
        try await sim.receive([start])
        try await sim.receive([remote])
        #expect(sim.remoteHaptics == 1, "SimHost runs effects(from:to:) for an in-order remote envelope")
    }
}
