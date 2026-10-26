import Synchronization

/// A stream's values in the order they come (F12 S2, finding F12-S2-R1-6). One task reads the stream as soon as a
/// value is sent, so none is replaced unseen in an observation's buffer of one, and `next(within:)` waits for the
/// next of them for at most a bound. A clause that says a write emits nothing reads after it with a short bound,
/// and the bound must end the wait: a value sent after the write is then seen, and fails the clause.
final class StreamArrivals<Value: Sendable>: Sendable {
    private struct Received {
        var values: [Value] = []
        var hasEnded = false
    }

    private let received = Mutex(Received())
    private let reader = Mutex<Task<Void, Never>?>(nil)

    /// Starts reading `stream`; the reading task holds this until `cancel()` or the stream's end.
    init(_ stream: AsyncStream<Value>) {
        let task = Task {
            for await value in stream {
                self.received.withLock { $0.values.append(value) }
            }
            self.received.withLock { $0.hasEnded = true }
        }
        reader.withLock { $0 = task }
    }

    /// The next value, or nil when none comes within `wait` or the stream has ended.
    func next(within wait: Duration = .seconds(5)) async -> Value? {
        let deadline = ContinuousClock.now + wait
        while true {
            let (value, hasEnded) = received.withLock { received in
                (received.values.isEmpty ? nil : received.values.removeFirst(), received.hasEnded)
            }
            if let value {
                return value
            }
            if hasEnded || ContinuousClock.now >= deadline {
                return nil
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Stops reading, which ends the stream's observation.
    func cancel() {
        reader.withLock { $0?.cancel() }
    }
}
