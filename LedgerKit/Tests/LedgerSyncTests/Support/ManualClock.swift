import Foundation
import Synchronization

/// A clock a test moves (F16's `ManualClock` in LedgerHealthTests, the `RestCoverClock` pattern): a sleep is
/// registered, and announced on `sleeps`, in the step that suspends its task, and `advance(by:)` wakes what is due
/// without yielding. No sleep of the wall clock, no `TestClock`.
final class ManualClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        let offset: Duration

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct Sleeper {
        let deadline: Instant
        let wake: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var begun = 0
        var sleepers: [Int: Sleeper] = [:]
        /// Sleeps cancelled before they were registered.
        var cancelled: Set<Int> = []
    }

    /// Each registered sleep's length, in the order they were registered.
    let sleeps: AsyncStream<Duration>
    private let sleepsSink: AsyncStream<Duration>.Continuation
    private let state = Mutex(State())

    init() {
        (sleeps, sleepsSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    var now: Instant {
        state.withLock { $0.now }
    }

    var minimumResolution: Duration {
        .zero
    }

    func sleep(until deadline: Instant, tolerance _: Duration?) async throws {
        try Task.checkCancellation()
        let id = state.withLock { state in
            state.begun += 1
            return state.begun
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (wake: CheckedContinuation<Void, any Error>) in
                let answer = state.withLock { state -> Result<Void, any Error>? in
                    if state.cancelled.remove(id) != nil {
                        return .failure(CancellationError())
                    }
                    guard deadline > state.now else {
                        return .success(())
                    }
                    state.sleepers[id] = Sleeper(deadline: deadline, wake: wake)
                    sleepsSink.yield(state.now.duration(to: deadline))
                    return nil
                }
                if let answer {
                    wake.resume(with: answer)
                }
            }
        } onCancel: {
            let sleeper = state.withLock { state in
                guard let sleeper = state.sleepers.removeValue(forKey: id) else {
                    state.cancelled.insert(id)
                    return Sleeper?.none
                }
                return sleeper
            }
            sleeper?.wake.resume(throwing: CancellationError())
        }
    }

    /// Moves time on by `duration` and wakes every sleep that ends by then.
    func advance(by duration: Duration) {
        let woken = state.withLock { state in
            state.now = state.now.advanced(by: duration)
            let due = state.sleepers.filter { $0.value.deadline <= state.now }
            for id in due.keys {
                state.sleepers[id] = nil
            }
            return due.values.map(\.wake)
        }
        for wake in woken {
            wake.resume()
        }
    }

    /// The next registered sleep that is not `skipped`'s length.
    func nextSleep(skipping skipped: Duration) async -> Duration? {
        for await sleep in sleeps where sleep != skipped {
            return sleep
        }
        return nil
    }
}
