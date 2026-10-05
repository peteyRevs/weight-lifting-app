import Foundation
import LedgerDomain

/// The live workout's live value until the composition root binds the host (F10 S2). Like the store stubs:
/// each method logs at fault level and throws `LedgerDependencyError.unimplemented(key:)`; `updates()`, which
/// cannot throw, logs and returns a stream that ends at once, so a screen that listens shows no workout.
struct UnimplementedWorkoutSession: WorkoutSessionClient {
    let stub = Unimplemented(key: "workoutSession")

    func updates() async -> AsyncStream<WorkoutSessionUpdate> {
        stub.emptyStream()
    }

    func current() async throws -> WorkoutState? {
        throw stub.failure()
    }

    func start(_: WorkoutState) async throws {
        throw stub.failure()
    }

    func apply(_: WorkoutEvent) async throws -> WorkoutState {
        throw stub.failure()
    }

    func finish(endedAt _: Date) async throws -> WorkoutState {
        throw stub.failure()
    }

    func discard(endedAt _: Date) async throws {
        throw stub.failure()
    }
}
