#if DEBUG
    import Foundation
    import LedgerDomain
    import LedgerFakes
    import SwiftUI

    /// Every preview in FeatureWorkout, one case each: the states of the cover, drawn from the model the
    /// presentation makes of a workout the engine built: its header, and from S5 the page under it. `PreviewTests`
    /// render every case and fail on a
    /// `#Preview` that is not a case here; the snapshot and accessibility tests draw the same states. None
    /// runs a task: the screen only draws, and `WorkoutRoot`, which follows the session, has no preview.
    ///
    /// The workout is the spec's Upper A (`Fixtures.seedSession()`), started at `Fixtures.now`; time stands
    /// still at each case's moment. Upper A is built with no history, so its cards read "No history yet";
    /// `logging` gives every exercise a last workout, and `dropSet` shows the last exercise in kilograms
    /// with a drop set, where nothing remains after it.
    ///
    /// The engine starts a rest at each logged set, so every case with a set logged shows the rest panel
    /// (F10 S6): at "Rest over" where its moment is past the rest's end, as in `logging`, whose second set
    /// was logged four minutes earlier. `resting` is `logging` 75 s into the 150 s rest of that set, and
    /// `restOver` is the same workout five seconds after the rest's end.
    enum WorkoutPreview: String, CaseIterable {
        case started = "Just started"
        case minutes = "After some minutes"
        case hour = "Past an hour"
        case logging = "Logging a set"
        case resting = "Resting"
        case restOver = "Rest over"
        case dropSet = "A drop set, in kilograms"
        case discarding = "Discarding"
        case loading = "Loading"
        case failed = "Could not open"

        /// Stands for whatever kept the workout from being shown.
        struct Unreadable: Error {}

        /// How many sets are logged, in the engine's order, and how long the workout has run.
        var progress: (sets: Int, elapsed: TimeInterval) {
            switch self {
            case .started, .loading, .failed: (0, 0)
            case .logging: (2, 6 * 60 + 5)
            case .resting: (2, 2 * 60 + 75)
            case .restOver: (2, 2 * 60 + 155)
            case .dropSet: (0, 41 * 60 + 12)
            case .minutes, .discarding: (6, 24 * 60 + 22)
            case .hour: (15, 3600 + 65)
            }
        }

        /// The moment the case shows.
        var now: Date {
            Fixtures.now.addingTimeInterval(progress.elapsed)
        }

        /// The live workout of a case that shows one.
        func workout() throws -> WorkoutState {
            var workout = try Fixtures.seedSession()
            switch self {
            case .logging, .resting, .restOver: Self.giveHistory(to: &workout)
            case .dropSet: Self.endWithADropSetInKilograms(&workout)
            default: break
            }
            return try Self.logged(progress.sets, in: workout)
        }

        /// The row the lifter chose: `dropSet` shows the last exercise, as a tap on its row of "REMAINING"
        /// does; every other case shows the engine's cursor.
        var selection: WorkoutSelection? {
            self == .dropSet ? WorkoutSelection(exerciseIndex: 4, setID: nil) : nil
        }

        /// What the screen is handed. A fixture that does not build shows as the failed state, and fails
        /// `PreviewTests`, which asks each case for its workout.
        var model: WorkoutScreenModel {
            let state: Loadable<WorkoutState> = switch self {
            case .loading: .loading
            case .failed: .failed(Unreadable())
            // `try?`: the fixture's own error is of no use to a preview; the failed state shows that it broke.
            default: (try? workout()).map(Loadable.loaded) ?? .failed(Unreadable())
            }
            return WorkoutPresentation.screen(
                state,
                selection: selection,
                now: now,
                isBusy: self == .discarding,
                locale: Fixtures.locale,
                calendar: Fixtures.calendar
            )
        }

        /// The cover in this state, its time standing still at the case's moment.
        var content: some View {
            WorkoutScreen(model: model) { _ in }
                .environment(\.workoutTimeline, .fixed(at: now))
        }

        /// Every exercise did its prescribed sets a week before the workout, one step lighter.
        static func giveHistory(to workout: inout WorkoutState) {
            for index in workout.exercises.indices {
                let exercise = workout.exercises[index]
                workout.exercises[index].lastPerformance = LastPerformance(
                    date: workout.startedAt.addingTimeInterval(-7 * 24 * 3600),
                    sets: exercise.targetSets,
                    reps: exercise.targetReps,
                    load: exercise.targetLoad.advanced(bySteps: -1, of: exercise.step)
                )
            }
        }

        /// The workout in kilograms, its last exercise 3 × 15 @ 10 kg by 1.25 kg with its first set logged
        /// and a drop set at 8.75 kg after the third.
        static func endWithADropSetInKilograms(_ workout: inout WorkoutState) {
            guard let last = workout.exercises.indices.last else {
                return
            }
            workout.units = .kg
            workout.exercises[last].step = .kilograms(1.25)
            workout.exercises[last].targetLoad = .kilograms(10)
            for index in workout.exercises[last].sets.indices {
                workout.exercises[last].sets[index].weight = .kilograms(10)
            }
            workout.exercises[last].sets[0].doneAt = workout.startedAt.addingTimeInterval(40 * 60)
            workout.exercises[last].sets.append(LoggedSet(
                id: .derived(from: workout.exercises[last].id, index: workout.exercises[last].sets.count),
                weight: .kilograms(8.75),
                reps: workout.exercises[last].sets[0].reps,
                kind: .drop
            ))
        }

        /// `workout` after its first `count` rows were logged where the engine's cursor stood, one a
        /// minute, each as prescribed.
        static func logged(_ count: Int, in workout: WorkoutState) throws -> WorkoutState {
            var state = workout
            for number in 0 ..< count {
                guard let cursor = state.checkedCursor else {
                    throw Unreadable()
                }
                let set = state.exercises[cursor.exerciseIndex].sets[cursor.setIndex]
                let event = WorkoutEvent.setLogged(
                    exerciseIndex: cursor.exerciseIndex,
                    setID: set.id,
                    weight: set.weight,
                    reps: set.reps,
                    doneAt: workout.startedAt.addingTimeInterval(TimeInterval(60 * (number + 1)))
                )
                let envelope = EventEnvelope(
                    event: event,
                    workoutID: workout.id,
                    device: workout.originDevice,
                    seq: UInt64(number + 2),
                    wallClock: workout.startedAt
                )
                guard let next = WorkoutEngine.reduce(state, envelope).0 else {
                    throw Unreadable()
                }
                state = next
            }
            return state
        }
    }

    #Preview("Just started") {
        WorkoutPreview.started.content
    }

    #Preview("After some minutes") {
        WorkoutPreview.minutes.content
    }

    #Preview("Past an hour") {
        WorkoutPreview.hour.content
    }

    #Preview("Logging a set") {
        WorkoutPreview.logging.content
    }

    #Preview("Resting") {
        WorkoutPreview.resting.content
    }

    #Preview("Rest over") {
        WorkoutPreview.restOver.content
    }

    #Preview("A drop set, in kilograms") {
        WorkoutPreview.dropSet.content
    }

    #Preview("Discarding") {
        WorkoutPreview.discarding.content
    }

    #Preview("Loading") {
        WorkoutPreview.loading.content
    }

    #Preview("Could not open") {
        WorkoutPreview.failed.content
    }

#endif
