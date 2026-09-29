import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

@Suite("WorkoutEngine · rest (rule 9)", .tags(.domain))
struct ReduceRestTests {
    @Test("Criterion 5: +30 s with no rest shown starts a 30 s rest from the tap")
    func criterion5_extendWithNoRest_startsRestFromNow() throws {
        let live = try Engine.live()
        let now = Engine.at(42)
        for shown in [false, true] {
            // The device showed no rest; `true` with no rest in the state is the same: nothing to extend.
            let envelope = EventBuilders.envelope(
                Engine.extend(shown: shown, tapped: 42),
                device: Engine.watch,
                seq: 1,
                at: now
            )
            let (state, effects) = WorkoutEngine.reduce(live, envelope)
            #expect(state?.rest == RestTimer(endsAt: now.addingTimeInterval(30), total: .seconds(30)))
            #expect(effects.contains(.scheduleRestNotification(endsAt: now.addingTimeInterval(30))))
        }
    }

    @Test("+30 s on a shown rest grows both endsAt and total (spec rule 23)")
    func extend_runningRest_growsEndsAtAndTotal() throws {
        let (state, _) = try Engine.run([
            .restStarted(endsAt: Engine.at(100), total: .seconds(90)),
            Engine.extend(tapped: 20)
        ])
        #expect(state.rest == RestTimer(endsAt: Engine.at(130), total: .seconds(120)))
    }

    @Test("Extending twice adds both amounts")
    func extendTwice_addsBoth() throws {
        let (state, effects) = try Engine.run([
            .restStarted(endsAt: Engine.at(100), total: .seconds(90)),
            Engine.extend(tapped: 20),
            Engine.extend(15, tapped: 30)
        ])
        #expect(state.rest == RestTimer(endsAt: Engine.at(145), total: .seconds(135)))
        #expect(effects.contains(.scheduleRestNotification(endsAt: Engine.at(145))))
    }

    @Test("Decision #7: +30 s on a rest the device showed as over starts a fresh 30 s rest at the tap")
    func extend_afterRestIsOver_startsFreshRest() throws {
        // The rest ends at 15 s; the device, showing it over, taps at 20 s (the second event of `run`).
        let (state, _) = try Engine.run([
            .restStarted(endsAt: Engine.at(15), total: .seconds(60)),
            Engine.extend(shown: false, tapped: 20)
        ])
        #expect(state.rest == RestTimer(endsAt: Engine.at(50), total: .seconds(30)))
    }

    @Test(
        """
        Decision B (fix round 2): the tap's intent decides, never a timestamp. A shown rest extends even when \
        both clocks say it is over; a rest shown over restarts even when both clocks say it is running
        """
    )
    func extend_followsTheLiftersIntent_notTheClock() throws {
        let rest = WorkoutEvent.restStarted(endsAt: Engine.at(15), total: .seconds(60))
        // Stamped at 20 s and tapped at 25 s, both after the rest's end at 15 s.
        let late = try Engine.run([rest, Engine.extend(shown: true, tapped: 25)])
        #expect(late.state.rest == RestTimer(endsAt: Engine.at(45), total: .seconds(90)))
        let running = WorkoutEvent.restStarted(endsAt: Engine.at(30), total: .seconds(90))
        // Stamped at 20 s and tapped at 5 s, both before the end at 30 s; the fresh rest ends later, at 35 s.
        let early = try Engine.run([running, Engine.extend(shown: false, tapped: 5)])
        #expect(early.state.rest == RestTimer(endsAt: Engine.at(35), total: .seconds(30)))
    }

    @Test(
        """
        Decision 4 (re-plan): +30 s from a device that showed no rest never shortens the state's rest. One \
        ending later than the fresh rest would is kept unchanged; one ending sooner is replaced
        """
    )
    func extend_unshown_neverShortensARunningRest() throws {
        let running = WorkoutEvent.restStarted(endsAt: Engine.at(100), total: .seconds(90))
        let kept = try Engine.run([running, Engine.extend(shown: false, tapped: 20)])
        #expect(kept.state.rest == RestTimer(endsAt: Engine.at(100), total: .seconds(90)))
        #expect(kept.effects.count == 2, "only persist and transmit, the rest is unchanged: \(kept.effects)")
        let replaced = try Engine.run([running, Engine.extend(shown: false, tapped: 80)])
        #expect(replaced.state.rest == RestTimer(endsAt: Engine.at(110), total: .seconds(30)))
        // At the fresh rest's exact end the state's rest does not run later, so the fresh one starts.
        let tie = try Engine.run([running, Engine.extend(shown: false, tapped: 70)])
        #expect(tie.state.rest == RestTimer(endsAt: Engine.at(100), total: .seconds(30)))
    }

    @Test("restStarted stores the absolute end, whenever the envelope is applied")
    func restStarted_isAbsolute() throws {
        let event = WorkoutEvent.restStarted(endsAt: Engine.at(200), total: .seconds(90))
        let live = try Engine.live()
        let early = WorkoutEngine.reduce(live, Engine.envelope(event, 110, seq: 2)).0
        let late = WorkoutEngine.reduce(live, Engine.envelope(event, 190, from: Engine.watch, seq: 2)).0
        #expect(early?.rest == RestTimer(endsAt: Engine.at(200), total: .seconds(90)))
        #expect(late?.rest == early?.rest)
    }

    @Test("Skip clears the rest and cancels its notification; with no rest it only cancels")
    func skip_clearsRest() throws {
        let running = try Engine.run([.restStarted(endsAt: Engine.at(100), total: .seconds(90)), .restSkipped])
        #expect(running.state.rest == nil)
        #expect(running.effects.contains(.cancelRestNotification))
        let idle = try Engine.run([.restSkipped])
        #expect(try idle.state == (Engine.live()))
        #expect(idle.effects.contains(.cancelRestNotification))
    }
}

// MARK: - The rest bound (fix round 1, finding 1; fix round 2, decision A)

extension ReduceRestTests {
    @Test(
        """
        A shown rest grown past longestRest is held: total pinned at an hour, endsAt at most an hour after \
        the tap; the sum saturates on the way
        """
    )
    func longestRest_holdsGrownRests() throws {
        #expect(WorkoutEngine.longestRest == .seconds(3600))
        let hour = WorkoutEngine.longestRest
        // A rest of the full hour, grown by a full hour at 30 s: the bound holds both fields.
        let grown = try Engine.run([
            .restStarted(endsAt: Engine.at(3610), total: hour),
            Engine.extend(3600, tapped: 20)
        ])
        #expect(grown.state.rest == RestTimer(endsAt: Engine.at(3620), total: hour))
        #expect(grown.effects.contains(.scheduleRestNotification(endsAt: Engine.at(3620))))
        // A zero amount changes nothing; the notification is still rescheduled (a replace).
        let still = try Engine.run([
            .restStarted(endsAt: Engine.at(100), total: .seconds(90)),
            Engine.extend(0, tapped: 20)
        ])
        #expect(still.state.rest == RestTimer(endsAt: Engine.at(100), total: .seconds(90)))
        #expect(still.effects.contains(.scheduleRestNotification(endsAt: Engine.at(100))))
    }

    @Test(
        "A hostile state handed to reduce, its rest at either Duration extreme, extended, saturates without overflow",
        arguments: [(Duration(attoseconds: .max), Int64(30)), (Duration(attoseconds: .min), Int64(0))]
    )
    func longestRest_saturatesAHostileStateRest(total: Duration, amount: Int64) throws {
        // `isWellFormed` rejects such a snapshot, so only a caller's own state can carry this rest.
        var hostile = try Engine.live()
        hostile.rest = RestTimer(endsAt: Engine.at(100), total: total)
        let envelope = Engine.envelope(Engine.extend(amount, tapped: 20), 20, seq: 2)
        let (state, _) = WorkoutEngine.reduce(hostile, envelope)
        let expected = total > .zero ? WorkoutEngine.longestRest : .zero
        #expect(state?.rest == RestTimer(endsAt: Engine.at(100 + Double(amount)), total: expected))
    }
}
