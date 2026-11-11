import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S9, ruling Q4: a not-done → done row that is not the last of its round ends the rest the workout
/// holds, running or over, and cancels its notification. A re-log, an un-log, a solo set and a set that ends
/// its round behave as before.
extension ReduceSetLoggedTests {
    private static let superset = EventBuilders.session(EventBuilders.supersetExercises)
    /// A1 at 10 s and B1 at 20 s: the group's 90 s rest runs to 110 s.
    private static let firstRound = [Engine.logged(0, 0, at: 10), Engine.logged(1, 0, at: 20)]
    private static let groupRest = RestTimer(endsAt: Engine.at(110), total: .seconds(90))

    /// The event's own effects: its haptics and notifications, without the envelope's persist and transmit.
    private static func own(_ effects: [Effect]) -> [Effect] {
        effects.filter {
            switch $0 {
            case .persist, .transmit, .updateLiveActivity: false
            default: true
            }
        }
    }

    @Test("Q4: a member logged while the rest runs ends it and cancels its notification")
    func memberLoggedDuringRest_endsItAndCancels() throws {
        let (state, effects) = try Engine.run(Self.firstRound + [Engine.logged(0, 1, at: 30)], on: Self.superset)
        #expect(state.rest == nil)
        #expect(state.shownRest == nil)
        #expect(Self.own(effects) == [.haptic(.setLogged), .cancelRestNotification])
        #expect(state.cursor == Cursor(exerciseIndex: 1, setIndex: 1), "the cursor moves as before")
    }

    @Test("Q4: a member logged after the rest's end ends the ended rest")
    func memberLoggedAfterRestOver_endsIt() throws {
        let (state, effects) = try Engine.run(Self.firstRound + [Engine.logged(0, 1, at: 500)], on: Self.superset)
        #expect(state.rest == nil)
        #expect(effects.contains(.cancelRestNotification))
    }

    @Test("Q4: un-logging that member afterwards brings no rest back")
    func unlogAfterThat_bringsNoRestBack() throws {
        let unlog = WorkoutEvent.setUnlogged(exerciseIndex: 0, setID: Engine.set(0, 1))
        let (state, effects) = try Engine.run(
            Self.firstRound + [Engine.logged(0, 1, at: 30), unlog], on: Self.superset
        )
        #expect(state.rest == nil)
        #expect(state.shownRest == nil)
        #expect(Self.own(effects).isEmpty)
    }

    @Test("Q4: a re-log of a done row, a member with no rest held, keep what is held")
    func relogOfDoneRow_keepsRest() throws {
        let relog = Engine.logged(0, 0, pounds: 60, at: 30)
        let (state, effects) = try Engine.run(Self.firstRound + [relog], on: Self.superset)
        #expect(state.rest == Self.groupRest)
        #expect(Self.own(effects) == [.haptic(.setLogged)])
        let first = try Engine.run([Engine.logged(0, 0, at: 10)], on: Self.superset)
        #expect(first.state.rest == nil)
        #expect(Self.own(first.effects) == [.haptic(.setLogged)], "no rest is held: nothing to cancel")
    }

    @Test("Q4: a solo set and a set that ends its round behave as before")
    func soloAndRoundEnd_unchanged() throws {
        let solo = try Engine.run([Engine.logged(0, 0, at: 10), Engine.logged(0, 1, at: 20)])
        #expect(solo.state.rest == RestTimer(endsAt: Engine.at(170), total: .seconds(150)))
        let roundEnd = try Engine.run(
            Self.firstRound + [Engine.logged(0, 1, at: 30), Engine.logged(1, 1, at: 40)], on: Self.superset
        )
        #expect(roundEnd.state.rest == RestTimer(endsAt: Engine.at(130), total: .seconds(90)))
        #expect(roundEnd.effects.contains(.scheduleRestNotification(endsAt: Engine.at(130))))
        // Auto rest off: a solo set leaves a "+30s" rest as it was.
        let off = EventBuilders.seedSession(autoRest: false)
        let manual = try Engine.run([Engine.extend(tapped: 10), Engine.logged(0, 0, at: 20)], on: off)
        #expect(manual.state.rest == RestTimer(endsAt: Engine.at(40), total: .seconds(30)))
    }

    @Test("Q4 against the oracle: after every event of seeded superset scripts, the rest is the oracle's")
    func seededScripts_restMatchesTheOracle() {
        let session = EventBuilders.session(EventBuilders.supersetExercises)
        let rows = (0 ..< 3).flatMap { set in [(0, set), (1, set)] }
        for seed in UInt64(1) ... 40 {
            var generator = SeededGenerator(seed: seed)
            var events: [WorkoutEvent] = []
            for step in 0 ..< 14 {
                let (exercise, set) = rows[Int.random(in: 0 ..< rows.count, using: &generator)]
                let seconds = Double(10 * (step + 1)) + Double(Int.random(in: 0 ..< 200, using: &generator))
                let event: WorkoutEvent = switch Int.random(in: 0 ..< 5, using: &generator) {
                case 0: .setUnlogged(exerciseIndex: exercise, setID: Engine.set(exercise, set))
                case 1: Engine.extend(tapped: seconds)
                case 2: .restSkipped
                default: Engine.logged(exercise, set, at: seconds)
                }
                events.append(event)
                let log = [Engine.started(session)]
                    + EventBuilders.log(from: events, firstSeq: 2, startingAt: Engine.at(10))
                let engine = Engine.fold(log)
                var oracle = ModelOracle()
                log.forEach { oracle.apply($0) }
                #expect(engine?.rest == oracle.state?.rest, "seed \(seed), step \(step)")
            }
        }
    }
}
