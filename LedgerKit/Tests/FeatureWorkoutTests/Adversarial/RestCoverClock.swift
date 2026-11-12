import Dependencies
import Foundation

/// The rest cover's clock (`RestCover`): time moves only when the cover moves it, and the clock says the
/// moment the rest's task's sleep is registered, so the cover can wait for that rather than poll for it.
///
/// The cover moves time one wait at a time and lets the task sleep again after each (`RestCover.run`). On
/// `RestProbeClock`, a `TestClock`, a registered sleep can only be told by `checkSuspension()`, which first
/// runs `megaYield` (20 detached tasks, one after another), and each `advance` runs three more: four
/// `megaYield`s for every second of a rest, 92% of the announcement walk's time (measured 2026-11-12). Here
/// a sleep is registered under the clock's lock in the step that suspends the task, so `due` is set exactly
/// when moving time to it wakes it; `advance` wakes what is due without yielding; and `changed()` returns
/// once a sleep has been registered or `signal()` called.
final nonisolated class RestCoverClock: Clock, Sendable {
    typealias Instant = TestClock<Duration>.Instant
    private typealias Wake = CheckedContinuation<Void, any Error>
    private typealias Watcher = CheckedContinuation<Void, Never>

    private struct Sleeper {
        let deadline: Instant
        let wake: Wake
    }

    private struct State {
        var now = Instant()
        var sleeps = 0
        var sleepers: [Int: Sleeper] = [:]
        /// The sleep registered last.
        var newest: Int?
        /// Sleeps cancelled before they were registered.
        var cancelled: Set<Int> = []
        var watcher: Watcher?
        var isChanged = false

        /// The waiting `changed()`, or, with none waiting, a note that the next one returns at once.
        mutating func takeWatcher() -> Watcher? {
            defer { watcher = nil }
            isChanged = watcher == nil
            return watcher
        }
    }

    private let state = LockIsolated(State())

    var now: Instant {
        state.value.now
    }

    var minimumResolution: Duration {
        .zero
    }

    /// The time since the clock was made.
    var elapsed: Duration {
        Instant().duration(to: now)
    }

    /// How many sleeps have begun.
    var sleeps: Int {
        state.value.sleeps
    }

    /// When the sleep registered last ends, so that `advance(to: due)` wakes it; nil once it has been woken
    /// or cancelled. (A second task sleeping on the clock, as in `twoWaits_oneBuzz`, may have registered a
    /// wait before it; `advance(to: due)` wakes that one too.)
    var due: Instant? {
        let current = state.value
        return current.newest.flatMap { current.sleepers[$0]?.deadline }
    }

    /// As `TestClock.sleep(until:tolerance:)`: a deadline already past returns at once; any other waits until
    /// time is moved to it, or the task is cancelled.
    func sleep(until deadline: Instant, tolerance _: Duration?) async throws {
        try Task.checkCancellation()
        let id = state.withValue { state in
            state.sleeps += 1
            return state.sleeps
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (wake: Wake) in
                let (answer, watcher) = state.withValue { state -> (Result<Void, any Error>?, Watcher?) in
                    if state.cancelled.remove(id) != nil {
                        return (.failure(CancellationError()), nil)
                    }
                    guard deadline >= state.now else {
                        return (.success(()), nil)
                    }
                    state.sleepers[id] = Sleeper(deadline: deadline, wake: wake)
                    state.newest = id
                    return (nil, state.takeWatcher())
                }
                if let answer {
                    wake.resume(with: answer)
                }
                watcher?.resume()
            }
        } onCancel: {
            let sleeper = state.withValue { state in
                guard let sleeper = state.sleepers.removeValue(forKey: id) else {
                    state.cancelled.insert(id)
                    return Sleeper?.none
                }
                return sleeper
            }
            sleeper?.wake.resume(throwing: CancellationError())
        }
    }

    /// Moves time to `deadline` (never back) and wakes every sleep that ends by then, in order.
    func advance(to deadline: Instant) {
        let woken = state.withValue { state in
            state.now = max(state.now, deadline)
            let ending = state.sleepers.filter { $0.value.deadline <= state.now }
            for id in ending.keys {
                state.sleepers[id] = nil
            }
            return ending.values.sorted { $0.deadline < $1.deadline }.map(\.wake)
        }
        for wake in woken {
            wake.resume()
        }
    }

    /// Returns once a sleep has been registered, or `signal()` called, since it last returned: at once if one
    /// has. One caller waits at a time.
    func changed() async {
        await withCheckedContinuation { (watcher: Watcher) in
            let isChanged = state.withValue { state in
                guard state.isChanged else {
                    state.watcher = watcher
                    return false
                }
                state.isChanged = false
                return true
            }
            if isChanged {
                watcher.resume()
            }
        }
    }

    /// Lets `changed()` return: for a change the clock does not see, such as the rest's task ending.
    func signal() {
        state.withValue { $0.takeWatcher() }?.resume()
    }
}
