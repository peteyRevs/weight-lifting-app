import Synchronization

/// A task that can be cancelled from inside what it runs (F11 S3): `fire()` cancels the task `run(_:)` started,
/// from wherever it is called. A test hands `fire` to the code under test (a closure a store calls inside its
/// write, a statement trace), so the cancellation lands at that exact point and needs no clock.
public final class TaskCancelSwitch: Sendable {
    private let cancel = Mutex<(@Sendable () -> Void)?>(nil)

    public init() {}

    /// Runs `body` in a new task. The task waits until `fire()` can reach it, so a `fire()` made by `body`,
    /// however early, cancels it.
    public func run<Value: Sendable>(_ body: @escaping @Sendable () async throws -> Value) -> Task<Value, any Error> {
        let (reachable, reach) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in reachable {
                break
            }
            return try await body()
        }
        cancel.withLock { $0 = { task.cancel() } }
        reach.yield()
        return task
    }

    /// Cancels the task `run(_:)` started; before `run(_:)`, does nothing.
    public func fire() {
        let armed = cancel.withLock { $0 }
        armed?()
    }
}
