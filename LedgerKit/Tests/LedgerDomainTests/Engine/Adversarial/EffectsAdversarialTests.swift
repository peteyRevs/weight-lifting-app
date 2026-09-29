import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Exact effect multisets per event (rules 3, 9, 10; `WorkoutEngine.reduce`'s documented contract:
/// persist + transmit for every accepted envelope, the event's own effects, and updateLiveActivity when
/// the state changed), and no repeated side effects for a duplicate envelope (ADR-004 idempotence).
@Suite("WorkoutEngine · effects (adversarial)", .tags(.domain))
struct EffectsAdversarialTests {
    typealias Adv = EngineAdv

    struct Case: Sendable, CustomStringConvertible {
        let description: String
        let before: [EventEnvelope]
        let envelope: EventEnvelope
        let extra: [Effect]
    }

    static let resting = [
        Adv.start(),
        Adv.env(.restStarted(endsAt: engineTime(90), total: .seconds(90)), seq: 2, at: 0)
    ]

    static let cases: [Case] = setCases() + restCases() + terminalCases()

    static func setCases() -> [Case] {
        let superset = Adv.start(EventBuilders.session(EventBuilders.supersetExercises))
        let logged = Adv.env(Adv.logged(0, 0, doneAt: 10), seq: 2, at: 10)
        let target = WorkoutEvent.setTargetChanged(
            exerciseIndex: 0, setID: Adv.sid(0, 1), weight: pounds("190"), reps: nil
        )
        return [
            Case(description: "started", before: [], envelope: Adv.start(), extra: []),
            Case(
                description: "setLogged, last of round", before: [Adv.start()], envelope: logged,
                extra: [.haptic(.setLogged), .scheduleRestNotification(endsAt: engineTime(160))]
            ),
            Case(
                description: "setLogged, not last of round",
                before: [superset],
                envelope: logged,
                extra: [.haptic(.setLogged)]
            ),
            Case(
                description: "setUnlogged", before: [Adv.start(), logged],
                envelope: Adv.env(.setUnlogged(exerciseIndex: 0, setID: Adv.sid(0, 0)), seq: 3, at: 11), extra: []
            ),
            Case(
                description: "setTargetChanged",
                before: [Adv.start()],
                envelope: Adv.env(target, seq: 2, at: 11),
                extra: []
            )
        ]
    }

    static func restCases() -> [Case] {
        [
            Case(
                description: "restStarted", before: [Adv.start()],
                envelope: Adv.env(.restStarted(endsAt: engineTime(90), total: .seconds(90)), seq: 2, at: 0),
                extra: [.scheduleRestNotification(endsAt: engineTime(90))]
            ),
            Case(
                description: "restExtended", before: resting,
                envelope: Adv.env(.restExtended(amount: .seconds(30)), seq: 3, at: 10),
                extra: [.scheduleRestNotification(endsAt: engineTime(120))]
            ),
            Case(
                description: "restSkipped", before: resting, envelope: Adv.env(.restSkipped, seq: 3, at: 10),
                extra: [.cancelRestNotification]
            )
        ]
    }

    static func terminalCases() -> [Case] {
        let finished = Adv.env(.finished(endedAt: engineTime(50)), seq: 3, at: 50)
        let summary = Adv.state(after: resting + [finished]).map { WorkoutEngine.summary($0, prs: []) }
        return [
            Case(
                description: "finished", before: resting, envelope: finished,
                extra: [.haptic(.workoutFinished), .cancelRestNotification] + (summary.map { [.materialize($0)] } ?? [])
            ),
            Case(
                description: "discarded", before: resting,
                envelope: Adv.env(.discarded(endedAt: engineTime(50)), seq: 3, at: 50),
                extra: [.discardLog, .cancelRestNotification]
            )
        ]
    }

    @Test(
        "Each event's effects are exactly persist, transmit, its own effects and one live-activity update.",
        arguments: cases
    )
    func exactEffects(_ testCase: Case) {
        let state = Adv.state(after: testCase.before)
        let (_, effects) = WorkoutEngine.reduce(state, testCase.envelope)
        let expected = [.persist(testCase.envelope), .transmit(testCase.envelope), .updateLiveActivity] + testCase.extra
        #expect(Adv.bag(effects) == Adv.bag(expected), "got \(effects)")
    }

    @Test("Ignored envelopes (before started, other workout, second started, after terminal) emit nothing.")
    func ignored_emitNothing() {
        let live = Adv.state(after: [Adv.start()])
        let ended = Adv.state(after: [Adv.start(), Adv.env(.finished(endedAt: engineTime(5)), seq: 2, at: 5)])
        let stray = Adv.env(Adv.logged(0, 0, doneAt: 5), seq: 2, at: 5, workoutID: WorkoutID(EventBuilders.uuid(0xBAD)))
        let ignored: [(WorkoutState?, EventEnvelope)] = [
            (nil, Adv.env(Adv.logged(0, 0, doneAt: 5), Adv.watch, seq: 1, at: 5)),
            (live, stray),
            (live, Adv.start(EventBuilders.seedSession(), Adv.watch, seq: 1, at: 1)),
            (ended, Adv.env(Adv.logged(0, 0, doneAt: 6), Adv.watch, seq: 1, at: 6))
        ]
        for (state, envelope) in ignored {
            #expect(WorkoutEngine.reduce(state, envelope).1.isEmpty)
        }
    }

    @Test("A no-op the engine accepts (select a done row) is logged but buzzes and redraws nothing.")
    func acceptedNoOp_noHapticNoActivity() {
        let live = Adv.state(after: [Adv.start(), Adv.env(Adv.logged(0, 0, doneAt: 1), seq: 2, at: 1)])
        let select = Adv.env(.exerciseSelected(exerciseIndex: 0, setIndex: 0), Adv.watch, seq: 1, at: 5)
        let (_, effects) = WorkoutEngine.reduce(live, select)
        #expect(Adv.bag(effects) == Adv.bag([.persist(select), .transmit(select)]))
    }
}

// MARK: - Duplicates (ADR-004 consequences: "idempotence: apply twice → same state")

extension EffectsAdversarialTests {
    @Test("Duplicate delivery: a setLogged applied twice does not buzz or notify twice.")
    func duplicateSetLogged_noSecondHaptic() {
        let envelope = Adv.env(Adv.logged(0, 0, doneAt: 10), Adv.watch, seq: 1, at: 10)
        let once = WorkoutEngine.reduce(Adv.state(after: [Adv.start()]), envelope)
        let (twice, effects) = WorkoutEngine.reduce(once.0, envelope)
        #expect(twice == once.0)
        #expect(!effects.contains(.haptic(.setLogged)), "second delivery re-emitted \(effects)")
        #expect(!Adv.schedulesRest(effects))
    }

    @Test("Duplicate delivery: a restExtended applied twice by reduce extends once (replay already dedupes).")
    func duplicateRestExtended_extendsOnce() {
        let envelope = Adv.env(.restExtended(amount: .seconds(30)), Adv.watch, seq: 1, at: 10)
        let once = WorkoutEngine.reduce(Adv.state(after: Self.resting), envelope).0
        let twice = WorkoutEngine.reduce(once, envelope).0
        #expect(WorkoutEngine.replay(Self.resting + [envelope, envelope])?.rest?.endsAt == engineTime(120))
        #expect(
            twice?.rest?.endsAt == engineTime(120),
            "reduce extended a duplicate: \(String(describing: twice?.rest))"
        )
    }

    @Test(
        "Every event is idempotent under reduce: applying an envelope twice equals applying it once.",
        arguments: cases
    )
    func reduceTwice_equalsOnce(_ testCase: Case) {
        let once = WorkoutEngine.reduce(Adv.state(after: testCase.before), testCase.envelope).0
        let twice = WorkoutEngine.reduce(once, testCase.envelope).0
        #expect(twice == once)
    }
}
