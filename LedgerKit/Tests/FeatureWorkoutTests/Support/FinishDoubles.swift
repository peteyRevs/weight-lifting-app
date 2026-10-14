import Foundation
import LedgerDomain
import LedgerTestSupport

/// The fake session whose `finish` answers with the workout still live: a session that says neither that
/// the workout is finished nor why not (F10 S7a, criterion 15).
struct UnfinishingSession: WorkoutSessionClient {
    let base: FakeWorkoutSessionClient

    func updates() async -> AsyncStream<WorkoutSessionUpdate> {
        await base.updates()
    }

    func current() async throws -> WorkoutState? {
        await base.current()
    }

    func start(_ initial: WorkoutState) async throws {
        try await base.start(initial)
    }

    func apply(_ event: WorkoutEvent) async throws -> WorkoutState {
        try await base.apply(event)
    }

    func finish(endedAt _: Date) async throws -> WorkoutState {
        guard let live = await base.current() else {
            throw WorkoutSessionError.noLiveWorkout
        }
        return live
    }

    func discard(endedAt: Date) async throws {
        try await base.discard(endedAt: endedAt)
    }
}

/// The fake session whose `finish` waits at a gate, then saves whatever became of its caller, as a host
/// does in a task of its own: a caller cancelled meanwhile is thrown `CancellationError` and the workout
/// is in history all the same (F10 S7a, criterion 18).
struct HeldFinishSession: WorkoutSessionClient {
    let base: FakeWorkoutSessionClient
    let gate: Gate

    func updates() async -> AsyncStream<WorkoutSessionUpdate> {
        await base.updates()
    }

    func current() async throws -> WorkoutState? {
        await base.current()
    }

    func start(_ initial: WorkoutState) async throws {
        try await base.start(initial)
    }

    func apply(_ event: WorkoutEvent) async throws -> WorkoutState {
        try await base.apply(event)
    }

    func finish(endedAt: Date) async throws -> WorkoutState {
        await gate.pass()
        let finished = try await base.finish(endedAt: endedAt)
        try Task.checkCancellation()
        return finished
    }

    func discard(endedAt: Date) async throws {
        try await base.discard(endedAt: endedAt)
    }
}

/// The fake session whose first `finish` calls throw and store nothing, and which keeps the end each call
/// asked for: a session that does not remember a first end by itself, so the caller's own is seen.
actor RefusingFinishSession: WorkoutSessionClient {
    struct Refused: Error {}

    private let base: FakeWorkoutSessionClient
    private var refusals: Int
    /// The end every `finish` asked for, in call order.
    private(set) var askedToEndAt: [Date] = []

    init(base: FakeWorkoutSessionClient, refusals: Int = 1) {
        self.base = base
        self.refusals = refusals
    }

    func updates() async -> AsyncStream<WorkoutSessionUpdate> {
        await base.updates()
    }

    func current() async throws -> WorkoutState? {
        await base.current()
    }

    func start(_ initial: WorkoutState) async throws {
        try await base.start(initial)
    }

    func apply(_ event: WorkoutEvent) async throws -> WorkoutState {
        try await base.apply(event)
    }

    func finish(endedAt: Date) async throws -> WorkoutState {
        askedToEndAt.append(endedAt)
        guard refusals == 0 else {
            refusals -= 1
            throw Refused()
        }
        return try await base.finish(endedAt: endedAt)
    }

    func discard(endedAt: Date) async throws {
        try await base.discard(endedAt: endedAt)
    }
}
