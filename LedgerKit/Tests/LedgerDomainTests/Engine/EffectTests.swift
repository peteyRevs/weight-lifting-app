import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

@Suite("WorkoutEngine · effects", .tags(.domain))
struct EffectTests {
    /// One row of the effect table: `event` reduced after `before`, and the effects it must produce
    /// between `.persist`/`.transmit` and the trailing `.updateLiveActivity`.
    struct Row: Sendable, CustomTestStringConvertible {
        let name: String
        var before: [WorkoutEvent] = []
        let event: WorkoutEvent
        let own: [Effect]
        let changesState: Bool

        var testDescription: String {
            name
        }
    }

    static let rows: [Row] = [
        Row(
            name: "setLogged, first time",
            event: Engine.logged(0, 0, at: 30),
            own: [.haptic(.setLogged), .scheduleRestNotification(endsAt: Engine.at(180))],
            changesState: true
        ),
        Row(
            name: "setLogged, mid-round",
            event: Engine.logged(0, 0, at: 30),
            own: [.haptic(.setLogged)],
            changesState: true
        ),
        Row(
            name: "setLogged, same values again",
            before: [Engine.logged(0, 0, at: 30)],
            event: Engine.logged(0, 0, at: 30),
            own: [.haptic(.setLogged)],
            changesState: false
        ),
        Row(name: "setLogged, unknown set", event: Engine.logged(9, 0, at: 30), own: [], changesState: false),
        Row(
            name: "setUnlogged",
            before: [Engine.logged(0, 0, at: 30)],
            event: .setUnlogged(exerciseIndex: 0, setID: Engine.set(0, 0)),
            own: [],
            changesState: true
        ),
        Row(
            name: "setTargetChanged",
            event: .setTargetChanged(exerciseIndex: 0, setID: Engine.set(0, 0), weight: nil, reps: .one),
            own: [],
            changesState: true
        ),
        Row(
            name: "setAdded",
            event: .setAdded(
                exerciseIndex: 0,
                set: LoggedSet(id: SetID(EventBuilders.uuid(1)), weight: .zero, reps: .one, kind: .added)
            ),
            own: [],
            changesState: true
        ),
        Row(
            name: "allSetsRepeated",
            event: .allSetsRepeated(exerciseIndex: 1, weight: .zero, reps: .one),
            own: [],
            changesState: true
        ),
        Row(
            name: "exerciseSwapped",
            event: .exerciseSwapped(
                exerciseIndex: 1,
                exerciseID: ExerciseID(EventBuilders.uuid(2)),
                name: "Dip",
                alsoUpdateProgram: false
            ),
            own: [],
            changesState: true
        ),
        Row(
            name: "exerciseSelected",
            event: .exerciseSelected(exerciseIndex: 1, setIndex: 1),
            own: [],
            changesState: true
        ),
        Row(
            name: "exerciseSelected, ignored",
            event: .exerciseSelected(exerciseIndex: 9, setIndex: 1),
            own: [],
            changesState: false
        ),
        Row(
            name: "restStarted",
            event: .restStarted(endsAt: Engine.at(120), total: .seconds(90)),
            own: [.scheduleRestNotification(endsAt: Engine.at(120))],
            changesState: true
        ),
        Row(
            name: "restExtended",
            before: [.restStarted(endsAt: Engine.at(120), total: .seconds(90))],
            event: .restExtended(amount: .seconds(30)),
            own: [.scheduleRestNotification(endsAt: Engine.at(150))],
            changesState: true
        ),
        Row(
            name: "restSkipped",
            before: [.restStarted(endsAt: Engine.at(120), total: .seconds(90))],
            event: .restSkipped,
            own: [.cancelRestNotification],
            changesState: true
        ),
        Row(name: "restSkipped, no rest", event: .restSkipped, own: [.cancelRestNotification], changesState: false),
        Row(
            name: "discarded",
            event: .discarded(endedAt: Engine.at(30)),
            own: [.discardLog, .cancelRestNotification],
            changesState: true
        )
    ]

    @Test(
        "Each event yields persist, transmit, its own effects, then updateLiveActivity if the state changed",
        arguments: rows
    )
    func effects_exactListPerEvent(row: Row) throws {
        // "mid-round" needs a superset: A1 is not the last of its round.
        let session = row.name.hasSuffix("mid-round")
            ? EventBuilders.session(EventBuilders.supersetExercises)
            : EventBuilders.seedSession()
        let before = try #require(Engine.fold([Engine.started(session)] + EventBuilders.log(
            from: row.before,
            firstSeq: 2
        )))
        let envelope = Engine.envelope(row.event, 30, from: Engine.watch, seq: 1)
        let (state, effects) = WorkoutEngine.reduce(before, envelope)
        let expected = [.persist(envelope), .transmit(envelope)] + row
            .own + (row.changesState ? [.updateLiveActivity] : [])
        #expect(effects == expected)
        #expect((state != before) == row.changesState)
    }

    @Test("finished yields persist, transmit, materialize(summary), the finish haptic, cancel, updateLiveActivity")
    func effects_finished() throws {
        let live = try Engine.live()
        let envelope = Engine.envelope(.finished(endedAt: Engine.at(900)), 900, seq: 2)
        let (state, effects) = WorkoutEngine.reduce(live, envelope)
        let finished = try #require(state)
        #expect(effects == [
            .persist(envelope),
            .transmit(envelope),
            .materialize(WorkoutEngine.summary(finished, prs: [])),
            .haptic(.workoutFinished),
            .cancelRestNotification,
            .updateLiveActivity
        ])
    }

    @Test("Ignored envelopes yield no effects at all")
    func effects_ignoredEnvelopes_areEmpty() throws {
        let live = try Engine.live()
        #expect(WorkoutEngine.reduce(live, Engine.envelope(.started(live), 5, seq: 2)).1.isEmpty)
        #expect(WorkoutEngine.reduce(nil, Engine.envelope(.restSkipped, 5, seq: 2)).1.isEmpty)
    }
}
