import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S1 adversarial round 1: the value types of the session seam. `WorkoutSessionUpdate.haptics(from:)`
/// is "the one forwarding rule: the engine's haptics, in order" (criterion 3), `live` is the state while its phase is
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
    static func onlyHaptics(_ effects: [Effect]) -> [Haptic] {
        effects.compactMap { effect -> Haptic? in
            if case let .haptic(haptic) = effect {
                return haptic
            }
            return nil
        }
    }

    @Test("haptics(from:) keeps every haptic there is, including the two the engine never emits")
    func feedback_keepsEveryHaptic() {
        #expect(Self.haptics.count == 4)
        #expect(WorkoutSessionUpdate.haptics(from: Self.haptics) == Haptic.allCases)
        #expect(WorkoutSessionUpdate.haptics(from: Self.haptics.reversed()) == Haptic.allCases.reversed())
    }

    @Test("haptics(from:) drops every other effect, whatever it carries, and an empty list stays empty")
    func feedback_dropsEverythingElse() {
        #expect(WorkoutSessionUpdate.haptics(from: Self.others) == [])
        #expect(WorkoutSessionUpdate.haptics(from: []) == [])
        for other in Self.others {
            #expect(WorkoutSessionUpdate.haptics(from: [other]) == [], "\(other)")
        }
    }

    @Test(
        "haptics(from:) keeps order and repeats: seeded shuffles of haptics among the rest",
        arguments: PropertySeed.all
    )
    func feedback_keepsOrderAndRepeats(seed: PropertySeed) {
        var generator = seed.generator
        let pool = Self.haptics + Self.haptics + Self.others
        let effects = (0 ..< Int.random(in: 0 ... 24, using: &generator)).map { _ in
            pool[Int.random(in: 0 ..< pool.count, using: &generator)]
        }
        #expect(WorkoutSessionUpdate.haptics(from: effects) == Self.onlyHaptics(effects), "\(seed)")
    }

    @Test("haptics(from:) of the engine's own effects: a log buzzes, a finish buzzes, nothing else does")
    func feedback_ofTheEnginesEffects() {
        let log = WorkoutEvent.setLogged(
            exerciseIndex: 0,
            setID: EventBuilders.setID(0, 0),
            weight: .pounds(185),
            reps: .one,
            doneAt: EventBuilders.start
        )
        let cases: [(WorkoutEvent, [Haptic])] = [
            (log, [.setLogged]),
            (.finished(endedAt: EventBuilders.start), [.workoutFinished]),
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
            #expect(WorkoutSessionUpdate.haptics(from: effects) == expected, "\(event)")
        }
        let started = WorkoutEngine.reduce(
            nil,
            EventBuilders.envelope(.started(Self.session), seq: 1, at: EventBuilders.start)
        ).1
        #expect(started.count >= 2 && WorkoutSessionUpdate.haptics(from: started) == [])
    }

    @Test("live is the state only while its phase is live", arguments: WorkoutPhase.allCases)
    func live_isTheStateOnlyWhileLive(_ phase: WorkoutPhase) {
        var state = Self.session
        state.phase = phase
        state.endedAt = phase == .live ? nil : EventBuilders.start
        let update = WorkoutSessionUpdate(state: state, haptics: [.workoutFinished])
        #expect(update.live == (phase == .live ? state : nil))
        #expect(update.state == state)
    }

    @Test("An update with no workout has no live workout; effects default to none")
    func update_withoutAWorkout() {
        let update = WorkoutSessionUpdate(state: nil)
        #expect(update.state == nil && update.live == nil && update.haptics == [])
        #expect(update == WorkoutSessionUpdate(state: nil, haptics: []))
        #expect(update != WorkoutSessionUpdate(state: nil, haptics: [.setLogged]))
        #expect(update != WorkoutSessionUpdate(state: Self.session))
    }

    @Test("Updates are equal, and hash alike, exactly when state and effects are; effects compare in order")
    func update_equalityAndHashing() {
        let buzz = WorkoutSessionUpdate(state: Self.session, haptics: [.setLogged, .personalRecord])
        let same = WorkoutSessionUpdate(
            state: EventBuilders.seedSession(),
            haptics: [.setLogged, .personalRecord]
        )
        let reordered = WorkoutSessionUpdate(
            state: Self.session,
            haptics: [.personalRecord, .setLogged]
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
