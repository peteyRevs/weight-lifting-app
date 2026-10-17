import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S6 round 2, ruling 18: the time of a tap is the time it was tapped. S5's storm again, but with
/// time that goes by while a call waits (not at each reading of the date, which cannot tell a reading at
/// the tap from one at the tap's turn): the result must be the same taps made one at a time, each at the
/// instant it was tapped in the storm.
extension WorkoutRestAdversarialTests {
    /// The storm: every call waits, more taps arrive meanwhile, the page is behind, and up to 20 s go by
    /// before a tap and while each call waits. Returns what it came to and when each tap was made.
    static func stormWithTime(_ taps: [WorkoutEdit], seed: UInt64) async throws -> (Pump.Outcome, [Date]) {
        let bench = try await PumpBench.make()
        await bench.session.holdEveryApply()
        await bench.session.keepStreamsBehind()
        var generator = SplitMix64(seed: seed ^ 0x7A95)
        var times: [Date] = []
        var next = 0
        while next < taps.count {
            for _ in 0 ... Int.random(in: 0 ... 2, using: &generator) where next < taps.count {
                // One tap in three follows the one before within three quarters of a second.
                let isQuick = Int.random(in: 0 ..< 3, using: &generator) == 0
                let before = Double(Int.random(in: 0 ... (isQuick ? 3 : 80), using: &generator)) / 4
                bench.clock.withValue { $0 += before }
                times.append(bench.clock.value)
                bench.tap(taps[next])
                next += 1
            }
            await bench.drainReleasing {
                let waited = Double(Int.random(in: 0 ... 80, using: &generator)) / 4
                bench.clock.withValue { $0 += waited }
                await bench.session.deliver(Int.random(in: 0 ... 2, using: &generator))
            }
            await bench.settled()
        }
        bench.following.cancel()
        let outcome = await Pump.Outcome(
            applied: bench.session.applied, final: bench.session.current(), selection: bench.store.selection
        )
        return (outcome, times)
    }

    /// The same taps one at a time, each at its own instant; and for each tap that carries a time, the
    /// events it sent against what the brief owes at that instant.
    static func calmAt(_ times: [Date], _ taps: [WorkoutEdit]) async throws -> Calm {
        let bench = try await PumpBench.make()
        var calm = Calm(outcome: Pump.Outcome(applied: [], final: nil, selection: nil))
        for (index, tap) in taps.enumerated() {
            let before = await bench.session.current()
            let sent = await bench.session.applied.count
            bench.clock.setValue(times[index])
            bench.tap(tap)
            await bench.store.drain()
            await bench.settled()
            let events = await Array(bench.session.applied.dropFirst(sent))
            if let fault = calm.timeFault(of: events, for: tap, before: before, at: times[index]), calm.fault == nil {
                calm.fault = "tap \(index), \(tap): \(fault)"
            }
        }
        bench.following.cancel()
        calm.outcome = await Pump.Outcome(
            applied: bench.session.applied, final: bench.session.current(), selection: bench.store.selection
        )
        return calm
    }

    @Test(
        "Taps in a storm, with time going by while calls wait, are the same taps one at a time at their own instants",
        arguments: RestSeeds.all
    )
    func storm_eachTapAtItsOwnInstant(seed: UInt64) async throws {
        let taps = Self.tapsWithRest(seed: seed, in: EventBuilders.seedSession())
        let (storm, times) = try await Self.stormWithTime(taps, seed: seed)
        let calm = try await Self.calmAt(times, taps)
        #expect(calm.fault == nil, "seed \(seed)")
        let firstDifference = zip(calm.outcome.applied, storm.applied).enumerated()
            .first { $0.element.0 != $0.element.1 }?.offset
        #expect(firstDifference == nil, "seed \(seed): the events differ from number \(firstDifference ?? -1) on")
        #expect(calm.outcome.applied.count == storm.applied.count, "seed \(seed)")
        let isSameWorkout = unchanged(storm.final, calm.outcome.final)
        #expect(isSameWorkout, "seed \(seed)")
        #expect(calm.outcome.selection == storm.selection, "seed \(seed)")
    }

    @Test("Those storms meet the cases: sets logged and un-logged, +30s on a rest running and on one over")
    func storm_eachTapAtItsOwnInstant_isNotVacuous() async throws {
        var total = Calm(outcome: Pump.Outcome(applied: [], final: nil, selection: nil))
        for seed in RestSeeds.all.prefix(40) {
            let taps = Self.tapsWithRest(seed: seed, in: EventBuilders.seedSession())
            let (_, times) = try await Self.stormWithTime(taps, seed: seed)
            let calm = try await Self.calmAt(times, taps)
            total.extended.running += calm.extended.running
            total.extended.over += calm.extended.over
            total.logged += calm.logged
            total.unlogged.held += calm.unlogged.held
            total.unlogged.applied += calm.unlogged.applied
        }
        // The first 40 seeds give 192 and 18, 237, and 40 un-logs applied (one held: the guard under a held
        // save has its own test below).
        #expect(total.extended.running >= 80)
        #expect(total.extended.over >= 8)
        #expect(total.logged >= 100)
        #expect(total.unlogged.applied >= 20)
    }

    // MARK: The undo guard and a clock set back, by the taps' own instants

    /// Drains with every call held, three seconds going by before each is let on.
    static func drainSlowly(_ bench: LaggingRestBench) async {
        let finished = LockIsolated(false)
        let draining = Task {
            await bench.store.drain()
            finished.setValue(true)
        }
        // At most as many rounds as a test has calls: a drain that neither ends nor waits fails here.
        for _ in 0 ..< 64 {
            let came = await eventually("a call or the end") { finished.value || bench.session.waiting.value > 0 }
            if finished.value || !came {
                break
            }
            await bench.clock.base.advance(by: .seconds(3))
            await bench.session.release()
        }
        guard finished.value else {
            Issue.record("the drain did not end")
            draining.cancel()
            return
        }
        await draining.value
    }

    @Test("The undo guard is of the two taps' instants, however late they are applied", arguments: [
        (0.5, true), (0.999, true), (1.0, false), (1.5, false)
    ])
    func undoGuard_behindAHeldSave(after: Double, isHeld: Bool) async throws {
        let bench = try await LaggingRestBench()
        let row = bench.running.exercises[0].sets[0]
        await bench.session.holdEveryApply()
        bench.store.send(.edit(.log(exerciseIndex: 0, setID: row.id)))
        await bench.clock.base.advance(by: .seconds(after))
        bench.store.send(.edit(.unlog(exerciseIndex: 0, setID: row.id)))
        await Self.drainSlowly(bench)
        let applied = await bench.session.applied
        #expect(applied.count == (isHeld ? 1 : 2))
        #expect(await bench.session.current()?.doneSets == (isHeld ? 1 : 0))
        guard case let .setLogged(_, _, _, _, doneAt) = applied.first else {
            Issue.record("the first event is not the logged set")
            return
        }
        #expect(doneAt == Fixtures.now, "the set is done when its check was tapped")
        bench.following.cancel()
    }

    @Test("A tap earlier than the event before it (the clock set back between two taps) is taken at its own date")
    func clockSetBack_betweenTwoTaps() async throws {
        let cover = try await RestCover(Fixtures.seedSession())
        let rows = try Fixtures.seedSession().exercises[0].sets
        await cover.run(100)
        await cover.tap(.log(exerciseIndex: 0, setID: rows[0].id))
        await cover.back(40)
        // The un-log is 40 s before the set's `doneAt`: no guard holds it (the guard is of a second after).
        await cover.tap(.unlog(exerciseIndex: 0, setID: rows[0].id))
        #expect(await cover.truth()?.doneSets == 0)
        let tapped = cover.now
        #expect(tapped < Fixtures.now.addingTimeInterval(100), "the clock is behind the first log")
        await cover.tap(.log(exerciseIndex: 0, setID: rows[0].id))
        let state = await cover.truth()
        #expect(state?.exercises[0].sets[0].doneAt == tapped)
        #expect(state?.shownRest?.endsAt == tapped.addingTimeInterval(150))
        #expect(cover.panel?.clock == "2:30", "the panel reads the new rest at the date now, not at the later one")
        #expect(await cover.panelFault() == nil)
        await cover.close()
    }
}

extension WorkoutRestAdversarialTests.Calm {
    /// What is wrong with the events a tap sent, by the brief and the tap's own instant; nil when nothing
    /// is. A logged set is done at the tap; an un-log within a second of the set's `doneAt` sends
    /// nothing, and from a second on one event; the panel's taps are `owed(for:showing:readAt:)`'s.
    mutating func timeFault(
        of events: [WorkoutEvent],
        for tap: WorkoutEdit,
        before: WorkoutState?,
        at instant: Date
    ) -> String? {
        switch tap {
        case .extendRest, .skipRest:
            let owed = owed(for: tap, showing: before?.shownRest, readAt: instant)
            return events == owed ? nil : "sent \(events), owed \(owed)"
        case .log:
            guard case let .setLogged(_, _, _, _, doneAt)? = events.first else {
                return nil
            }
            logged += 1
            return doneAt == instant ? nil : "done at \(doneAt), tapped at \(instant)"
        case let .unlog(exercise, setID):
            guard let exercises = before?.exercises, exercises.indices.contains(exercise),
                  let doneAt = exercises[exercise].sets.first(where: { $0.id == setID })?.doneAt
            else {
                return events.isEmpty ? nil : "an un-log of a row that is not logged sent \(events)"
            }
            let since = instant.timeIntervalSince(doneAt)
            let isHeld = since >= 0 && since < 1
            unlogged.held += isHeld ? 1 : 0
            unlogged.applied += isHeld ? 0 : 1
            return events.count == (isHeld ? 0 : 1) ? nil : "\(since) s after the set, sent \(events.count)"
        default:
            return nil
        }
    }
}
