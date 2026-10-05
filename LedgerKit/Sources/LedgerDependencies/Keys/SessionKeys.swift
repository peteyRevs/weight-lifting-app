import Dependencies
import LedgerDomain
#if DEBUG
    import LedgerFakes
#endif

// The live workout's key (architecture §13; F10). `liveValue` is the `UnimplementedWorkoutSession` stub until the
// composition root binds the host (F10 S2); `testValue` is the library's default, which fails the test naming
// the key; `previewValue` is a fake with no workout.

public extension DependencyValues {
    /// The live workout's host: what Today, the workout screen and the watch call and watch.
    var workoutSession: any WorkoutSessionClient {
        get { self[WorkoutSessionKey.self] }
        set { self[WorkoutSessionKey.self] = newValue }
    }
}

enum WorkoutSessionKey: DependencyKey {
    static let liveValue: any WorkoutSessionClient = UnimplementedWorkoutSession()
    #if DEBUG
        /// No workout: a preview that shows one binds `FakeWorkoutSessionClient(live:)` with `withDependencies`.
        /// Computed, as the stores' are: the library reads it once per test (and once in a preview process),
        /// so a workout one test starts in it is never another test's.
        static var previewValue: any WorkoutSessionClient {
            FakeWorkoutSessionClient()
        }
    #endif
}
