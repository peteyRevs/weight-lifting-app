import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S1 adversarial round 1: the value types of the session seam. `WorkoutSessionUpdate.feedback(from:)`
/// is "the one forwarding rule: `.haptic` only" (criterion 3), `live` is the state while its phase is
/// `.live`, and `WorkoutSessionError`'s cases are told apart by the workout they name.
@Suite("Adversarial F10 S1 · WorkoutSessionUpdate", .tags(.domain))
struct WorkoutSessionUpdateAdversarialTests {
    static let session = EventBuilders.seedSession()
    static let envelope = EventBuilders.envelope(.restSkipped, seq: 1, at: EventBuilders.start)

    /// Every effect that is not a haptic, with payloads that differ.
    static let others: [Effect] = [
        .scheduleRestNotification(endsAt: EventBuilders.start),
        .scheduleRestNotification(endsAt: .distantFuture),
        .cancelRestNotification,
        .updateLiveActivity,
        .persist(envelope),
        .transmit(envelope),
        .materialize(session),
        .discardLog
    ]

    static let haptics = Haptic.allCases.map(Effect.haptic)

    /// The rule as criterion 3 states it, written here: the haptics, in order.
    static func onlyHaptics(_ effects: [Effect]) -> [Effect] {
        effects.filter { effect in
            if case .haptic = effect {
                return true
            }
            return false
        }
    }

    @Test("feedback(from:) keeps every haptic there is, including the two the engine never emits")
    func feedback_keepsEveryHaptic() {
        #expect(Self.haptics.count == 4)
        #expect(WorkoutSessionUpdate.feedback(from: Self.haptics) == Self.haptics)
        #expect(WorkoutSessionUpdate.feedback(from: Self.haptics.reversed()) == Self.haptics.reversed())
    }

    @Test("feedback(from:) drops every other effect, whatever it carries, and an empty list stays empty")
    func feedback_dropsEverythingElse() {
        #expect(WorkoutSessionUpdate.feedback(from: Self.others) == [])
        #expect(WorkoutSessionUpdate.feedback(from: []) == [])
        for other in Self.others {
            #expect(WorkoutSessionUpdate.feedback(from: [other]) == [], "\(other)")
        }
    }

    @Test(
        "feedback(from:) keeps order and repeats: seeded shuffles of haptics among the rest",
        arguments: PropertySeed.all
    )
    func feedback_keepsOrderAndRepeats(seed: PropertySeed) {
        var generator = seed.generator
        let pool = Self.haptics + Self.haptics + Self.others
        let effects = (0 ..< Int.random(in: 0 ... 24, using: &generator)).map { _ in
            pool[Int.random(in: 0 ..< pool.count, using: &generator)]
        }
        #expect(WorkoutSessionUpdate.feedback(from: effects) == Self.onlyHaptics(effects), "\(seed)")
    }

    @Test("feedback(from:) of the engine's own effects: a log buzzes, a finish buzzes, nothing else does")
    func feedback_ofTheEnginesEffects() {
        let log = WorkoutEvent.setLogged(
            exerciseIndex: 0,
            setID: EventBuilders.setID(0, 0),
            weight: .pounds(185),
            reps: .one,
            doneAt: EventBuilders.start
        )
        let cases: [(WorkoutEvent, [Effect])] = [
            (log, [.haptic(.setLogged)]),
            (.finished(endedAt: EventBuilders.start), [.haptic(.workoutFinished)]),
            (.discarded(endedAt: EventBuilders.start), []),
            (.restStarted(endsAt: EventBuilders.start, total: .seconds(90)), []),
            (.restSkipped, []),
            (.exerciseSelected(exerciseIndex: 1, setIndex: 0), [])
        ]
        for (event, expected) in cases {
            let effects = WorkoutEngine.reduce(
                Self.session,
                EventBuilders.envelope(event, seq: 1, at: EventBuilders.start)
            ).1
            #expect(effects.count >= 2, "the engine ignored \(event)")
            #expect(WorkoutSessionUpdate.feedback(from: effects) == expected, "\(event)")
        }
        let started = WorkoutEngine.reduce(
            nil,
            EventBuilders.envelope(.started(Self.session), seq: 1, at: EventBuilders.start)
        ).1
        #expect(started.count >= 2 && WorkoutSessionUpdate.feedback(from: started) == [])
    }

    @Test("live is the state only while its phase is live", arguments: WorkoutPhase.allCases)
    func live_isTheStateOnlyWhileLive(_ phase: WorkoutPhase) {
        var state = Self.session
        state.phase = phase
        state.endedAt = phase == .live ? nil : EventBuilders.start
        let update = WorkoutSessionUpdate(state: state, effects: [.haptic(.workoutFinished)])
        #expect(update.live == (phase == .live ? state : nil))
        #expect(update.state == state)
    }

    @Test("An update with no workout has no live workout; effects default to none")
    func update_withoutAWorkout() {
        let update = WorkoutSessionUpdate(state: nil)
        #expect(update.state == nil && update.live == nil && update.effects == [])
        #expect(update == WorkoutSessionUpdate(state: nil, effects: []))
        #expect(update != WorkoutSessionUpdate(state: nil, effects: [.haptic(.setLogged)]))
        #expect(update != WorkoutSessionUpdate(state: Self.session))
    }

    @Test("Updates are equal, and hash alike, exactly when state and effects are; effects compare in order")
    func update_equalityAndHashing() {
        let buzz = WorkoutSessionUpdate(state: Self.session, effects: [.haptic(.setLogged), .haptic(.personalRecord)])
        let same = WorkoutSessionUpdate(
            state: EventBuilders.seedSession(),
            effects: [.haptic(.setLogged), .haptic(.personalRecord)]
        )
        let reordered = WorkoutSessionUpdate(
            state: Self.session,
            effects: [.haptic(.personalRecord), .haptic(.setLogged)]
        )
        #expect(buzz == same && buzz.hashValue == same.hashValue)
        #expect(buzz != reordered)
        #expect(Set([buzz, same, reordered, WorkoutSessionUpdate(state: nil)]).count == 3)
    }

    @Test("WorkoutSessionError: four cases, told apart by case and by the workout they name")
    func error_casesAreDistinct() {
        let (one, two) = (EventBuilders.workoutID, WorkoutID(EventBuilders.uuid(0xF101)))
        let errors: [WorkoutSessionError] = [
            .workoutInProgress(one), .workoutInProgress(two), .notStartable(one), .notStartable(two),
            .noLiveWorkout, .incompleteLog(one), .incompleteLog(two)
        ]
        for (index, error) in errors.enumerated() {
            #expect(errors.firstIndex(of: error) == index, "\(error) equals an earlier case")
        }
    }
}
