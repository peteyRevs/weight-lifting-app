import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 adversarial round 1, criterion 3: "A stamp is `max(now, newest stamp seen or sent + 1 ms)`. After a
/// relaunch the clock continues from the store's newest wall clock … The host never produces a stamp that is
/// not finite." Stamps are read from the store; expected ones are the formula computed here.
@Suite("Adversarial F10 S2 · the host's clock", .tags(.sync), .timeLimit(.minutes(1)))
struct HostClockAdversarialTests {
    typealias Backing = SiegeRig.Backing

    static let tick = 0.001

    /// A distinct accepted event for each `index`.
    static func event(_ index: Int) -> WorkoutEvent {
        .restStarted(endsAt: Seam.at(1000 + Double(index)), total: .seconds(60))
    }

    /// What the brief's formula gives for system clock readings `readings`, from `newest`.
    static func stamps(_ readings: [Date], after newest: Date?) -> [Date] {
        var newest = newest
        return readings.map { now in
            let stamp = newest.map { max(now, $0.addingTimeInterval(tick)) } ?? now
            newest = stamp
            return stamp
        }
    }

    /// Clock readings that step back, repeat, creep by less than a tick, and jump a century ahead and back.
    static let offsets: [TimeInterval] = [0, 10, 10, 10, 9.9995, -3600, 10.0005, 3_155_760_000, 20, 3_155_760_000, 30]

    @Test(
        "Stamps follow the formula across a clock that steps back, repeats and jumps ahead",
        arguments: Backing.allCases
    )
    func stamps_unsteadyClock_followTheFormula(backing: Backing) async throws {
        let rig = try await SiegeRig.make(backing)
        let host = await rig.host()
        let readings = Self.offsets.map(Seam.at)
        for (index, reading) in readings.enumerated() {
            rig.clock.set(reading)
            if index == 0 {
                try await host.start(Seam.session(1))
            } else {
                try await host.apply(Self.event(index))
            }
        }
        let log = await rig.siege.stored
        #expect(log.map(\.wallClock) == Self.stamps(readings, after: nil))
        #expect(log.map(\.seq) == Array(1 ... UInt64(readings.count)))
        #expect(zip(log, log.dropFirst()).allSatisfy { $0.wallClock < $1.wallClock }, "strictly rising")
        #expect(try await host.current() == WorkoutEngine.replay(log), "reduce in call order is replay in stamp order")
    }

    @Test("After a relaunch the clock continues above the store's newest stamp", arguments: Backing.allCases)
    func stamps_afterARelaunch_continueAboveTheStore(backing: Backing) async throws {
        let rig = try await SiegeRig.make(backing)
        var host = await rig.host()
        rig.clock.set(Seam.at(86400))
        try await host.start(Seam.session(1))
        try await host.apply(Self.event(1))
        rig.clock.set(Seam.at(0))
        host = await rig.host()
        let unlogged = try await host.apply(Self.event(2))
        let log = await rig.siege.stored
        #expect(log.map(\.wallClock) == Self.stamps([86400, 86400, 0].map(Seam.at), after: nil))
        #expect(log.map(\.wallClock).min() == Seam.at(86400), "no stamp older than one already stored")
        #expect(log.map(\.seq) == [1, 2, 3])
        #expect(unlogged == WorkoutEngine.replay(log), "the action after the relaunch is not replayed before the last")
    }

    @Test("The second workout of a process starts at seq 1, with stamps above the first's", arguments: Backing.allCases)
    func seq_twoWorkoutsInARow_restartsAtOne(backing: Backing) async throws {
        let rig = try await SiegeRig.make(backing)
        let host = await rig.host()
        rig.clock.set(Seam.at(500))
        try await host.start(Seam.session(1))
        try await host.apply(Self.event(1))
        _ = try await host.finish(endedAt: Seam.at(600))
        rig.clock.set(Seam.at(100))
        try await host.start(Seam.session(2))
        try await host.apply(Seam.logged(0, 0, in: 2))
        try await host.discard(endedAt: Seam.at(700))
        try await host.start(Seam.session(3))
        let log = await rig.siege.stored
        #expect(log.map(\.seq) == [1, 2, 3, 1, 2, 3, 1])
        #expect(log.allSatisfy { $0.device == rig.device })
        #expect(log.map(\.wallClock) == Self.stamps([500, 500, 500, 100, 100, 100, 100].map(Seam.at), after: nil))
    }

    @Test("An ignored event takes no seq and no stamp; a refused one neither", arguments: Backing.allCases)
    func seq_ignoredAndRefusedEvents_takeNone(backing: Backing) async throws {
        let scene = try await SiegeScene.make(backing)
        let before = await scene.siege.stored
        for ignored in SeamEvents.ignored.map(\.event) {
            scene.rig.clock.advance(1000)
            #expect(try await scene.host.apply(ignored) == scene.live, "\(SeamCall.apply(ignored))")
        }
        #expect(await Seam
            .outcome(of: .start(Seam.session(2)), on: scene.host) == .refused(.workoutInProgress(scene.live.id)))
        #expect(await scene.siege.stored == before, "nothing is stored for an event the engine ignores")
        #expect(await scene.heard().isEmpty, "and nothing is published")
        scene.rig.clock.set(Seam.at(0))
        try await scene.host.apply(scene.nextLog)
        let last = try #require(await scene.siege.stored.last)
        let newest = try #require(before.last)
        #expect(last.seq == newest.seq + 1)
        #expect(last.wallClock == newest.wallClock.addingTimeInterval(Self.tick), "the ignored calls moved no clock")
    }

    @Test(
        "A peer's envelopes in the log do not move this device's seq, and their stamps move its clock",
        arguments: Backing.allCases
    )
    func seq_peerEnvelopes_countOnlyForTheClock(backing: Backing) async throws {
        let own = SiegeLogs.log(1, SiegeLogs.twoSets(in: 1))
        let peer = EventBuilders.log(
            from: [Seam.logged(1, 0, in: 1, at: 300), Seam.logged(1, 1, in: 1, at: 400)],
            device: EventBuilders.watch,
            firstSeq: 7,
            startingAt: Seam.at(5000),
            workoutID: Seam.workout(1)
        )
        let rig = try await SiegeLogs.rig(backing, [own + peer])
        let host = await rig.host()
        rig.clock.set(Seam.at(50))
        let after = try await host.apply(Self.event(1))
        let stored = try #require(await rig.siege.stored.last)
        #expect(stored.seq == 4 && stored.device == rig.device)
        #expect(stored.wallClock == Seam.at(5010).addingTimeInterval(Self.tick), "above the watch's newest stamp")
        #expect(try await rig.replayed(Seam.workout(1)) == after)
    }
}
