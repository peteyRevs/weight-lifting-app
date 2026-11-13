import Dependencies
import Foundation
import Testing

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

    /// How many sleeps are registered: one for each task asleep on the clock.
    var asleep: Int {
        state.value.sleepers.count
    }

    /// When the first registered sleep ends, so that `advance(to: due)` wakes it (and any other that ends
    /// then); nil while none is registered.
    var due: Instant? {
        state.value.sleepers.values.map(\.deadline).min()
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

    /// Moves time to `deadline` (never back) and wakes every sleep that ends by then, by its deadline and
    /// then in the order the sleeps began. Unlike `TestClock`, which steps `now` through each deadline, `now`
    /// jumps to `deadline` before anything is woken, so every task woken here reads `deadline`: the cover
    /// moves time one wait at a time, so a wait ends exactly at `deadline` there.
    func advance(to deadline: Instant) {
        let woken = state.withValue { state in
            state.now = max(state.now, deadline)
            let ending = state.sleepers.filter { $0.value.deadline <= state.now }
            for id in ending.keys {
                state.sleepers[id] = nil
            }
            return ending.sorted { ($0.value.deadline, $0.key) < ($1.value.deadline, $1.key) }.map(\.value.wake)
        }
        for wake in woken {
            wake.resume()
        }
    }

    /// Returns once a sleep has been registered, or `signal()` called, since it last returned: at once if one
    /// has. One caller waits at a time: a second is a misuse, and stops the test.
    func changed() async {
        await withCheckedContinuation { (watcher: Watcher) in
            let isChanged = state.withValue { state in
                precondition(state.watcher == nil, "RestCoverClock.changed() has one waiter at a time")
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

extension RestCover {
    /// Waits until `condition`, on what the rest's task and the clock do, holds: looked at again each time
    /// the clock registers a sleep or the task ends (`RestCoverClock.changed()`), never by polling. As
    /// `eventually`, a wait that has not come in 10 s of the wall clock, or whose task is cancelled (a time
    /// limit), records an issue that names it and returns.
    func keeperWait(
        _ what: String,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () -> Bool
    ) async {
        guard !condition() else {
            return
        }
        let limit = Duration.seconds(10)
        let deadline = ContinuousClock.now.advanced(by: limit)
        let guarding = Task { [clock] in
            guard await (try? Task.sleep(for: limit)) != nil else {
                return
            }
            clock.signal()
        }
        defer { guarding.cancel() }
        while !condition() {
            guard !Task.isCancelled else {
                Issue.record("cancelled while waiting for: \(what)", sourceLocation: sourceLocation)
                return
            }
            guard ContinuousClock.now < deadline else {
                Issue.record("never came in \(limit): \(what)", sourceLocation: sourceLocation)
                return
            }
            await withTaskCancellationHandler {
                await clock.changed()
            } onCancel: { [clock] in
                clock.signal()
            }
        }
    }
}
