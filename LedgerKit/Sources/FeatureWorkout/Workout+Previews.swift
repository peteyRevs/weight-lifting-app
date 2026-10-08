#if DEBUG
    import Foundation
    import LedgerDomain
    import LedgerFakes
    import SwiftUI

    /// Every preview in FeatureWorkout, one case each: the states of the cover, drawn from the model the
    /// presentation makes of a workout the engine built. `PreviewTests` render every case and fail on a
    /// `#Preview` that is not a case here; the snapshot and accessibility tests draw the same states. None
    /// runs a task: the screen only draws, and `WorkoutRoot`, which follows the session, has no preview.
    ///
    /// The workout is the spec's Upper A (`Fixtures.seedSession()`), started at `Fixtures.now`; time stands
    /// still at each case's moment.
    enum WorkoutPreview: String, CaseIterable {
        case started = "Just started"
        case minutes = "After some minutes"
        case hour = "Past an hour"
        case discarding = "Discarding"
        case loading = "Loading"
        case failed = "Could not open"

        /// Stands for whatever kept the workout from being shown.
        struct Unreadable: Error {}

        /// How many sets are logged, in the engine's order, and how long the workout has run.
        var progress: (sets: Int, elapsed: TimeInterval) {
            switch self {
            case .started, .loading, .failed: (0, 0)
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
            try Self.logged(progress.sets, in: Fixtures.seedSession())
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
            return WorkoutPresentation.screen(state, isBusy: self == .discarding, locale: Fixtures.locale)
        }

        /// The cover in this state, its time standing still at the case's moment.
        var content: some View {
            WorkoutScreen(model: model) { _ in }
                .environment(\.workoutTimeline, .fixed(at: now))
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
