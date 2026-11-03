import Dependencies
@testable import FeatureHistory
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// An `EditSetsStore` over one workout of in-memory stores, with its writes seen through `DetailWorkouts`.
@MainActor
struct EditScene {
    let memory: InMemoryStores
    let workouts: DetailWorkouts
    let workout: WorkoutState
    let store: EditSetsStore

    init(_ workout: WorkoutState = HistoryFixtures.twelve()[11], units: Units = .lb, saveFailure: (any Error)? = nil) {
        let stores = InMemoryStores(seed: InMemoryStores.Seed(workouts: [workout], settings: Fixtures.settingsLb))
        let seen = DetailWorkouts(
            base: stores.workouts,
            failsDeletes: false,
            endsObservation: false,
            saveFailure: saveFailure
        )
        memory = stores
        workouts = seen
        self.workout = workout
        store = withTestDependencies {
            $0.workoutRepository = seen
            $0.settingsRepository = stores.settings
        } operation: {
            EditSetsStore(EditSetsRequest(workout: workout, units: units))
        }
    }

    /// The first logged set of the workout's first exercise.
    var firstSet: LoggedSet {
        get throws {
            try #require(workout.exercises.first?.sets.first { $0.isDone })
        }
    }
}

/// A workout of two exercises in pounds, the second never logged: every set of its first exercise is done but the last.
nonisolated enum EditFixtures {
    static func partlyLogged() -> WorkoutState {
        var workout = Seeders.workout(number: 7, endedAt: Fixtures.date(2026, 9, 16, hour: 8), [
            .straight(HistoryFixtures.bench, sets: 3, reps: 5, pounds: 185),
            .straight(WorkoutRepositoryContract.exercises[1], sets: 2, reps: 5, pounds: 225)
        ])
        let lastSet = workout.exercises[0].sets.count - 1
        workout.exercises[0].sets[lastSet].doneAt = nil
        for place in workout.exercises[1].sets.indices {
            workout.exercises[1].sets[place].doneAt = nil
        }
        return workout
    }
}
