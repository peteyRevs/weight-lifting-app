import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

@Suite("WorkoutEngine · rest (rule 9)", .tags(.domain))
struct ReduceRestTests {
    @Test("Criterion 5: +30 s with no rest running starts a 30 s rest from the envelope's time")
    func criterion5_extendWithNoRest_startsRestFromNow() throws {
        let live = try Engine.live()
        let now = Engine.at(42)
        let envelope = EventBuilders.envelope(
            .restExtended(amount: .seconds(30)),
            device: Engine.watch,
            seq: 1,
            at: now
        )
        let (state, effects) = WorkoutEngine.reduce(live, envelope)
        #expect(state?.rest == RestTimer(endsAt: now.addingTimeInterval(30), total: .seconds(30)))
        #expect(effects.contains(.scheduleRestNotification(endsAt: now.addingTimeInterval(30))))
    }

    @Test("+30 s on a running rest grows both endsAt and total (spec rule 23)")
    func extend_runningRest_growsEndsAtAndTotal() throws {
        let (state, _) = try Engine.run([
            .restStarted(endsAt: Engine.at(100), total: .seconds(90)),
            .restExtended(amount: .seconds(30))
        ])
        #expect(state.rest == RestTimer(endsAt: Engine.at(130), total: .seconds(120)))
    }

    @Test("Extending twice adds both amounts")
    func extendTwice_addsBoth() throws {
        let (state, effects) = try Engine.run([
            .restStarted(endsAt: Engine.at(100), total: .seconds(90)),
            .restExtended(amount: .seconds(30)),
            .restExtended(amount: .seconds(15))
        ])
        #expect(state.rest == RestTimer(endsAt: Engine.at(145), total: .seconds(135)))
        #expect(effects.contains(.scheduleRestNotification(endsAt: Engine.at(145))))
    }

    @Test("Decision #7: +30 s after the rest reached zero starts a fresh 30 s rest")
    func extend_afterRestIsOver_startsFreshRest() throws {
        // The rest ends at 15 s; the extension arrives at 20 s (the second event of `run`).
        let (state, _) = try Engine.run([
            .restStarted(endsAt: Engine.at(15), total: .seconds(60)),
            .restExtended(amount: .seconds(30))
        ])
        #expect(state.rest == RestTimer(endsAt: Engine.at(50), total: .seconds(30)))
    }

    @Test("A rest ending exactly at the extension's time is over")
    func extend_atExactEnd_startsFreshRest() throws {
        let (state, _) = try Engine.run([
            .restStarted(endsAt: Engine.at(20), total: .seconds(60)),
            .restExtended(amount: .seconds(30))
        ])
        #expect(state.rest == RestTimer(endsAt: Engine.at(50), total: .seconds(30)))
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
