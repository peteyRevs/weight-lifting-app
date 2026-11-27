#if DEBUG
    import Dependencies
    import Foundation

    /// The clock of every store test that moves time (the phone's `RestCover`, `RestBench`, `LaggingRestBench` and
    /// hosted root; the watch's store, F18 S2b): time moves only when the test moves it, and the clock says the
    /// moment the rest's task's sleep is registered, so the test can wait for that rather than poll for it.
    ///
    /// Never a `TestClock`. A registered sleep on one can only be told by `checkSuspension()`, which first runs
    /// `megaYield` (20 detached tasks, one after another), and each `advance` runs three more: four `megaYield`s
    /// for every second of a rest, 92% of the announcement walk's time (measured 2026-11-12). Those tasks are of
    /// background priority, which any other work on the machine goes before: on the PR runner, with the
    /// simulator busy, a 150 s rest stepped a second at a time took over a minute (issue #121, 0.3 s on an idle
    /// Mac). Here a sleep is registered under the clock's lock in the step that suspends the task, so `due` is
    /// set exactly when moving time to it wakes it; `advance` wakes what is due without yielding, so the test
    /// then waits for what it wants to see (the task asleep again, or ended); and `changed()` returns once a
    /// sleep has been registered or `signal()` called.
    public final class RestCoverClock: Clock, Sendable {
        public typealias Instant = TestClock<Duration>.Instant
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

        public init() {}

        public var now: Instant {
            state.value.now
        }

        public var minimumResolution: Duration {
            .zero
        }

        /// The time since the clock was made.
        public var elapsed: Duration {
            Instant().duration(to: now)
        }

        /// How many sleeps have begun.
        public var sleeps: Int {
            state.value.sleeps
        }

        /// How many sleeps are registered: one for each task asleep on the clock.
        public var asleep: Int {
            state.value.sleepers.count
        }

        /// Whether a sleep begun after the first `sleeps` is registered: for a test with one task on the clock,
        /// that the task woken last is asleep again, so that moving time ends its wait. A sleep is counted when it
        /// begins and registered a step later, and time moved in between would leave the wait at a deadline that
        /// time has already reached, which nothing then ends.
        public func isAsleep(after sleeps: Int) -> Bool {
            state.withValue { $0.sleeps > sleeps && !$0.sleepers.isEmpty }
        }

        /// When the first registered sleep ends, so that `advance(to: due)` wakes it (and any other that ends
        /// then); nil while none is registered.
        public var due: Instant? {
            state.value.sleepers.values.map(\.deadline).min()
        }

        /// As `TestClock.sleep(until:tolerance:)`: a deadline already past returns at once; any other waits until
        /// time is moved to it, or the task is cancelled.
        public func sleep(until deadline: Instant, tolerance _: Duration?) async throws {
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
        public func advance(to deadline: Instant) {
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

        /// Moves time on by `duration` (`advance(to:)`): every sleep that ends by then is woken.
        public func advance(by duration: Duration) {
            advance(to: now.advanced(by: duration))
        }

        /// Returns once a sleep has been registered, or `signal()` called, since it last returned: at once if one
        /// has. One caller waits at a time: a second is a misuse, and stops the test.
        public func changed() async {
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
        public func signal() {
            state.withValue { $0.takeWatcher() }?.resume()
        }
    }

    public extension RestCoverClock {
        /// How a `wait(within:until:)` ended.
        enum WaitOutcome: Equatable, Sendable {
            case held, cancelled, timedOut
        }

        /// Waits until `condition`, on what the tasks asleep on the clock do, holds: looked at again each time the
        /// clock registers a sleep or `signal()` is called (`changed()`), never by polling. It gives up when the
        /// condition has not come in `limit` of the wall clock, or when its task is cancelled (a time limit), and
        /// says which: the caller records the issue, in the words of its own target.
        func wait(
            isolation _: isolated (any Actor)? = #isolation,
            within limit: Duration = .seconds(10),
            until condition: () -> Bool
        ) async -> WaitOutcome {
            guard !condition() else {
                return .held
            }
            let deadline = ContinuousClock.now.advanced(by: limit)
            let guarding = Task { [self] in
                guard await (try? Task.sleep(for: limit)) != nil else {
                    return
                }
                signal()
            }
            defer { guarding.cancel() }
            while !condition() {
                guard !Task.isCancelled else {
                    return .cancelled
                }
                guard ContinuousClock.now < deadline else {
                    return .timedOut
                }
                await withTaskCancellationHandler {
                    await changed()
                } onCancel: { [self] in
                    signal()
                }
            }
            return .held
        }
    }
#endif
