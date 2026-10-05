import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S1: what an element of `WorkoutSessionClient.updates()` carries, and the one rule for which of the
/// engine's effects reach a screen.
@Suite("WorkoutSessionUpdate", .tags(.domain))
struct WorkoutSessionUpdateTests {
    static let session = EventBuilders.seedSession()
    static let envelope = EventBuilders.envelope(.restSkipped, seq: 1, at: EventBuilders.start)

    /// Every effect that is not a haptic.
    static let hostEffects: [Effect] = [
        .persist(envelope),
        .transmit(envelope),
        .scheduleRestNotification(endsAt: EventBuilders.start),
        .cancelRestNotification,
        .updateLiveActivity,
        .materialize(session),
        .discardLog
    ]

    @Test("haptics(from:) keeps the haptics, in the engine's order, and drops every other effect")
    func haptics_keepsTheHapticsInOrder() {
        let mixed: [Effect] = [.persist(Self.envelope), .haptic(.setLogged), .transmit(Self.envelope)]
            + [.scheduleRestNotification(endsAt: EventBuilders.start), .haptic(.workoutFinished)]
            + [.materialize(Self.session), .haptic(.personalRecord), .updateLiveActivity, .haptic(.setLogged)]
        // Not the same read backwards: an implementation that reversed the order would show.
        let expected: [Haptic] = [.setLogged, .workoutFinished, .personalRecord, .setLogged]
        #expect(WorkoutSessionUpdate.haptics(from: mixed) == expected)
        #expect(WorkoutSessionUpdate.haptics(from: []).isEmpty)
    }

    @Test("haptics(from:) forwards each haptic", arguments: Haptic.allCases)
    func haptics_forwardsEachHaptic(_ haptic: Haptic) {
        #expect(WorkoutSessionUpdate.haptics(from: [.haptic(haptic)]) == [haptic])
    }

    @Test("haptics(from:) forwards nothing for an effect the host runs itself")
    func haptics_dropsWhatTheHostRuns() {
        for effect in Self.hostEffects {
            #expect(WorkoutSessionUpdate.haptics(from: [effect]).isEmpty, "\(effect)")
        }
        #expect(WorkoutSessionUpdate.haptics(from: Self.hostEffects).isEmpty)
    }

    @Test("Of the engine's effects for a logged set, a finish and a discard, the screen gets the haptics alone")
    func haptics_ofTheEnginesEffects() {
        let logged = WorkoutEvent.setLogged(
            exerciseIndex: 0,
            setID: EventBuilders.setID(0, 0),
            weight: .pounds(185),
            reps: Reps(clamping: 5),
            doneAt: EventBuilders.start.addingTimeInterval(60)
        )
        let later = EventBuilders.start.addingTimeInterval(600)
        func effects(of event: WorkoutEvent) -> [Effect] {
            WorkoutEngine.reduce(Self.session, EventBuilders.envelope(event, seq: 2, at: later)).1
        }
        // Persist, transmit, the haptic, the rest notification and the Live Activity: one of five is the screen's.
        #expect(effects(of: logged).count == 5)
        #expect(WorkoutSessionUpdate.haptics(from: effects(of: logged)) == [.setLogged])
        #expect(WorkoutSessionUpdate.haptics(from: effects(of: .finished(endedAt: later))) == [.workoutFinished])
        #expect(WorkoutSessionUpdate.haptics(from: effects(of: .discarded(endedAt: later))).isEmpty)
        let selected = effects(of: .exerciseSelected(exerciseIndex: 1, setIndex: 0))
        #expect(!selected.isEmpty && WorkoutSessionUpdate.haptics(from: selected).isEmpty)
    }

    @Test("live is the state while its workout is live, and nil once it ended or when there is none")
    func live_followsThePhase() {
        var finished = Self.session
        finished.phase = .finished
        var discarded = Self.session
        discarded.phase = .discarded
        #expect(WorkoutSessionUpdate(state: Self.session).live == Self.session)
        #expect(WorkoutSessionUpdate(state: finished).live == nil)
        #expect(WorkoutSessionUpdate(state: discarded).live == nil)
        #expect(WorkoutSessionUpdate(state: nil).live == nil)
        // An ended workout's update still carries its state: the screen that ends it shows the receipt from it,
        // and tells a finish from a discard by its phase.
        #expect(WorkoutSessionUpdate(state: finished).state?.phase == .finished)
        #expect(WorkoutSessionUpdate(state: discarded).state?.phase == .discarded)
    }

    @Test("An update has no haptics unless given some, and two updates are equal when both parts are")
    func update_defaultsAndEquality() {
        let plain = WorkoutSessionUpdate(state: Self.session)
        #expect(plain.haptics.isEmpty)
        #expect(plain == WorkoutSessionUpdate(state: Self.session, haptics: []))
        #expect(plain != WorkoutSessionUpdate(state: Self.session, haptics: [.setLogged]))
        #expect(plain != WorkoutSessionUpdate(state: nil))
        #expect(Set([plain, plain, WorkoutSessionUpdate(state: nil)]).count == 2)
    }
}
