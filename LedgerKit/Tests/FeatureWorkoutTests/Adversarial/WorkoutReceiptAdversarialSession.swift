import Foundation
import LedgerDomain
import LedgerTestSupport

// MARK: - A session that ends the workout and holds its answer

/// The fake session whose `finish` ends the workout (the stream says so) and then waits for `answer()` before
/// it answers; with `keptEnd`, it ends the workout at that end whatever the caller asked, as the host does
/// when an end already waits in the log. With `answerFirst` the stream's ending update is held back until the
/// answer has been given.
actor KeptEndSession: WorkoutSessionClient {
    private let base: FakeWorkoutSessionClient
    private let keptEnd: Date?
    private let answerFirst: Bool
    private var ended: CheckedContinuation<Void, Never>?
    private var hasEnded = false
    private var answering: CheckedContinuation<Void, Never>?
    private var held: [AsyncStream<WorkoutSessionUpdate>.Continuation] = []
    private var heldUpdate: WorkoutSessionUpdate?

    init(live: WorkoutState, keptEnd: Date?, answerFirst: Bool) {
        base = FakeWorkoutSessionClient(live: live)
        self.keptEnd = keptEnd
        self.answerFirst = answerFirst
    }

    func updates() async -> AsyncStream<WorkoutSessionUpdate> {
        let source = await base.updates()
        let (stream, continuation) = AsyncStream<WorkoutSessionUpdate>.makeStream()
        let forward = Task {
            for await update in source {
                if update.live == nil, update.state != nil, await self.holdsBack(update, for: continuation) {
                    continue
                }
                continuation.yield(update)
            }
            if await !self.isHolding(continuation) {
                continuation.finish()
            }
        }
        continuation.onTermination = { _ in forward.cancel() }
        return stream
    }

    private func holdsBack(
        _ update: WorkoutSessionUpdate,
        for continuation: AsyncStream<WorkoutSessionUpdate>.Continuation
    ) -> Bool {
        guard answerFirst else {
            return false
        }
        heldUpdate = update
        held.append(continuation)
        return true
    }

    private func isHolding(_: AsyncStream<WorkoutSessionUpdate>.Continuation) -> Bool {
        answerFirst && heldUpdate != nil
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
        let finished = try await base.finish(endedAt: keptEnd ?? endedAt)
        hasEnded = true
        ended?.resume()
        ended = nil
        await withCheckedContinuation { answering = $0 }
        if answerFirst {
            // The answer reaches the caller first; the ending update follows it.
            Task { await self.release() }
        }
        return finished
    }

    private func release() {
        guard let update = heldUpdate else {
            return
        }
        heldUpdate = nil
        for continuation in held {
            continuation.yield(update)
            continuation.finish()
        }
        held = []
    }

    func discard(endedAt: Date) async throws {
        try await base.discard(endedAt: endedAt)
    }

    /// Returns once the workout has ended in the session.
    func waitUntilEnded() async {
        if hasEnded {
            return
        }
        await withCheckedContinuation { ended = $0 }
    }

    /// Lets `finish` answer.
    func answer() async {
        while answering == nil {
            await Task.yield()
        }
        answering?.resume()
        answering = nil
    }
}
