@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2 round 2, F10 S4 criteria 13, 15 and 16: the rulings after round 1, attacked.
@MainActor
@Suite("Workout rulings of round 1 (adversarial)", .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutRulingsAdversarialTests {
    typealias World = AdversarialWorld
    typealias Spec = EventBuilders.ExerciseSpec

    static let sets = [3, 1, 4, 2]

    func session() -> (state: WorkoutState, fake: FakeWorkoutSessionClient) {
        let specs = Self.sets.enumerated().map {
            Spec("Exercise \($0.offset)", .barbell, sets: $0.element, reps: 5, pounds: 100, restSeconds: 60)
        }
        let state = EventBuilders.session(specs)
        return (state, FakeWorkoutSessionClient(live: state))
    }

    /// What criterion 13 allows of `state`, or what is wrong.
    func wrong(_ state: WorkoutState) -> String? {
        let segments = WorkoutPresentation.header(state, isBusy: false, locale: Fixtures.locale).segments
        let picture = segments.map { $0.state == .done ? "d" : $0.state == .current ? "c" : "u" }.joined()
        for (exercise, segment) in zip(state.exercises, segments) {
            let isDone = exercise.sets.allSatisfy { $0.doneAt != nil }
            if isDone != (segment.state == .done) {
                return "\(picture): a segment is done exactly when its every set is"
            }
        }
        let allDone = segments.allSatisfy { $0.state == .done }
        let current = segments.count { $0.state == .current }
        let cursor = String(describing: state.cursor)
        return current == (allDone ? 0 : 1) ? nil : "\(picture): \(current) current, cursor \(cursor)"
    }

    @Test("Logged in order, at every count: one segment is current until all are done, then none")
    func segments_everyCountInOrder() async throws {
        var (state, fake) = session()
        #expect(wrong(state) == nil)
        for (exercise, rows) in Self.sets.enumerated() {
            for row in 0 ..< rows {
                let set = state.exercises[exercise].sets[row]
                state = try await fake.apply(
                    .setLogged(
                        exerciseIndex: exercise,
                        setID: set.id,
                        weight: set.weight,
                        reps: set.reps,
                        doneAt: EventBuilders.start
                    )
                )
                #expect(wrong(state) == nil, "after \(exercise).\(row)")
            }
        }
        let header = WorkoutPresentation.header(state, isBusy: false, locale: Fixtures.locale)
        #expect(header.segments.allSatisfy { $0.state == .done })
    }

    /// The lifter logs rows in any order and takes some back (the engine moves the cursor as rule 20 says).
    @Test(
        "Logged and unlogged in any order: one segment is current until all are done",
        arguments: Array(1 ... 60) as [UInt64]
    )
    func segments_anyOrder(seed: UInt64) async throws {
        var generator = SplitMix64(seed: seed)
        var (state, fake) = session()
        var trail: [String] = []
        for _ in 0 ..< 40 {
            let exercise = Int.random(in: 0 ..< Self.sets.count, using: &generator)
            let set = state.exercises[exercise].sets[Int.random(in: 0 ..< Self.sets[exercise], using: &generator)]
            let event: WorkoutEvent = set.doneAt == nil || Int.random(in: 0 ..< 4, using: &generator) > 0
                ? .setLogged(
                    exerciseIndex: exercise,
                    setID: set.id,
                    weight: set.weight,
                    reps: set.reps,
                    doneAt: EventBuilders.start
                )
                : .setUnlogged(exerciseIndex: exercise, setID: set.id)
            state = try await fake.apply(event)
            trail.append("\(set.doneAt == nil ? "+" : "±")\(exercise)")
            if let wrong = wrong(state) {
                Issue.record("seed \(seed): \(wrong) after \(trail.joined(separator: " "))")
                return
            }
        }
    }

    func words(_ rig: AdversarialRig) -> String {
        guard case let .failed(failure) = rig.phase else {
            return "no alert (\(rig.phase))"
        }
        let alert = WorkoutPresentation.alert(for: failure)
        return "\(alert.title) / \(alert.message)"
    }

    /// One fault on a start with nothing live, with the session readable afterwards or not.
    nonisolated enum StartFault: String, Sendable, CaseIterable {
        case programStore, firstRead, secondRead, start, startAnswerLost
    }

    @Test(
        "Criterion 16: a failed start says nothing was changed only when the session was read again and shows it",
        arguments: StartFault.allCases, [true, false]
    )
    func failedStart_claimsOnlyWhatIsKnown(fault: StartFault, readable: Bool) async throws {
        try await World.run(.host) { world in
            let rig = AdversarialRig()
            // The reads of a start: the launcher's, the use case's, then the one after a failure.
            var reads = 2
            switch fault {
            case .programStore:
                await world.launcherStores.fail(.activeProgram)
                reads = 1
            case .firstRead: reads = 0
            case .secondRead: reads = 1
            case .start: await world.session.fail(.start)
            case .startAnswerLost: await world.session.fail(.start, afterwards: true)
            }
            let failsRead = fault == .firstRead || fault == .secondRead
            if !readable || failsRead {
                await world.session.fail(.current, times: readable ? 1 : 9, skipping: reads)
            }
            await rig.start(world.source(day: 0))
            await world.session.heal()
            let live = try await world.live()
            if readable, live != nil {
                #expect(rig.phase == .cover, "the workout is live and the session said so: \(rig.phase)")
            } else if readable {
                #expect(words(rig) == "Couldn't start this workout / Nothing was changed. Try again.")
            } else {
                #expect(words(rig) == "Couldn't start this workout / Try again.", "live: \(live != nil)")
            }
            #expect(fault == .startAnswerLost || live == nil, "only a start that went through leaves a workout")
            await rig.answer(.dismissFailure)
            await rig.start(world.source(day: 0))
            #expect(rig.phase == .cover, "the next try opens the workout: \(rig.phase)")
            #expect(await world.session.count(.start) <= 2)
        }
    }
}
