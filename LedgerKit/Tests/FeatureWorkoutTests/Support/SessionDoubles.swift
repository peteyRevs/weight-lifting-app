import Foundation
import LedgerDomain
import LedgerTestSupport

/// Where a double's call waits until the test lets it on, so a test can act while the call is running.
actor Gate {
    private var isOpen = false
    private var arrived = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var watchers: [CheckedContinuation<Void, Never>] = []

    /// Waits here until `open()`.
    func pass() async {
        arrived = true
        watchers.forEach { $0.resume() }
        watchers = []
        guard !isOpen else {
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Returns once a call is waiting at the gate.
    func waitForArrival() async {
        guard !arrived else {
            return
        }
        await withCheckedContinuation { watchers.append($0) }
    }

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

/// The fake session behind a gate: `current()` and `discard` first wait there, and throw
/// `CancellationError` when their task was cancelled meanwhile, as a store's call does, before anything
/// reached the fake.
struct GatedSession: WorkoutSessionClient {
    let base: FakeWorkoutSessionClient
    let gate: Gate

    private func held() async throws {
        await gate.pass()
        try Task.checkCancellation()
    }

    func updates() async -> AsyncStream<WorkoutSessionUpdate> {
        await base.updates()
    }

    func current() async throws -> WorkoutState? {
        try await held()
        return await base.current()
    }

    func start(_ initial: WorkoutState) async throws {
        try await base.start(initial)
    }

    func apply(_ event: WorkoutEvent) async throws -> WorkoutState {
        try await base.apply(event)
    }

    func finish(endedAt: Date) async throws -> WorkoutState {
        try await base.finish(endedAt: endedAt)
    }

    func discard(endedAt: Date) async throws {
        try await held()
        try await base.discard(endedAt: endedAt)
    }
}

/// A session with no workout whose updates end at once and whose calls throw, as the key's stub does: what
/// a cover meets when no session was bound.
struct EndedSession: WorkoutSessionClient {
    struct Unbound: Error {}

    /// What the stream holds before it ends.
    var first: [WorkoutSessionUpdate] = []
    /// What the calls throw.
    var error: any Error = Unbound()

    func updates() async -> AsyncStream<WorkoutSessionUpdate> {
        AsyncStream { continuation in
            for update in first {
                continuation.yield(update)
            }
            continuation.finish()
        }
    }

    func current() async throws -> WorkoutState? {
        throw error
    }

    func start(_: WorkoutState) async throws {
        throw error
    }

    func apply(_: WorkoutEvent) async throws -> WorkoutState {
        throw error
    }

    func finish(endedAt _: Date) async throws -> WorkoutState {
        throw error
    }

    func discard(endedAt _: Date) async throws {
        throw error
    }
}

/// The fake session whose first `current()` throws and whose later ones answer: a read that failed once.
actor FlakySession: WorkoutSessionClient {
    struct Unread: Error {}

    private let base: FakeWorkoutSessionClient
    private var hasFailed = false

    init(base: FakeWorkoutSessionClient) {
        self.base = base
    }

    func updates() async -> AsyncStream<WorkoutSessionUpdate> {
        await base.updates()
    }

    func current() async throws -> WorkoutState? {
        guard hasFailed else {
            hasFailed = true
            throw Unread()
        }
        return await base.current()
    }

    func start(_ initial: WorkoutState) async throws {
        try await base.start(initial)
    }

    func apply(_ event: WorkoutEvent) async throws -> WorkoutState {
        try await base.apply(event)
    }

    func finish(endedAt: Date) async throws -> WorkoutState {
        try await base.finish(endedAt: endedAt)
    }

    func discard(endedAt: Date) async throws {
        try await base.discard(endedAt: endedAt)
    }
}
