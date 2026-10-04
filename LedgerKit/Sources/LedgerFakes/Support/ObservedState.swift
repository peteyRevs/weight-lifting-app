#if DEBUG
    import Synchronization

    /// An in-memory store's state behind a `Mutex`, with the streams its `observe…()` methods return.
    ///
    /// A `Mutex` rather than an actor (ADR-008): the protocols' `observe…()` are synchronous, and no write made
    /// after the call may be missed. GRDB guarantees that by queueing the observation's first fetch on the writer
    /// before any later write; here the observer is registered, and its first value yielded, under the lock
    /// before `observe…()` returns. Every write runs whole under the lock, then each stream yields its value if it
    /// changed (GRDB's `removeDuplicates()`). A stream buffers only its newest value, as GRDB's bridge does
    /// (`.bufferingNewest(1)`): a consumer that falls behind sees the latest state, not every one in between.
    final class ObservedState<State: Sendable, Value: Equatable & Sendable>: Sendable {
        private struct Observer {
            let value: @Sendable (State) -> Value
            let continuation: AsyncStream<Value>.Continuation
            var last: Value
        }

        private struct Guarded {
            var state: State
            var observers: [Int: Observer] = [:]
            var nextObserver = 0
        }

        private let guarded: Mutex<Guarded>

        init(_ state: State) {
            guarded = Mutex(Guarded(state: state))
        }

        /// Reads the state.
        func read<Result: Sendable, Failure: Error>(
            _ body: (State) throws(Failure) -> Result
        ) throws(Failure) -> Result {
            try guarded.withLock { guarded throws(Failure) in try body(guarded.state) }
        }

        /// Changes the state, all or nothing: when `body` throws, the state stays as it was and no stream
        /// yields. Then each stream whose value changed yields it.
        @discardableResult
        func write<Result: Sendable, Failure: Error>(
            _ body: (inout State) throws(Failure) -> Result
        ) throws(Failure) -> Result {
            try guarded.withLock { guarded throws(Failure) in
                var state = guarded.state
                let result = try body(&state)
                guarded.state = state
                for id in guarded.observers.keys {
                    guard var observer = guarded.observers[id] else {
                        continue
                    }
                    let value = observer.value(state)
                    if value != observer.last {
                        observer.last = value
                        observer.continuation.yield(value)
                        guarded.observers[id] = observer
                    }
                }
                return result
            }
        }

        /// `value` of the state now, then after every write that changes it. Ending the stream (its consumer's
        /// task cancelled, or the iterator dropped) stops the observation.
        func observe(_ value: @escaping @Sendable (State) -> Value) -> AsyncStream<Value> {
            let (stream, continuation) = AsyncStream<Value>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let id = guarded.withLock { guarded in
                let current = value(guarded.state)
                let id = guarded.nextObserver
                guarded.nextObserver += 1
                guarded.observers[id] = Observer(value: value, continuation: continuation, last: current)
                continuation.yield(current)
                return id
            }
            continuation.onTermination = { [weak self] _ in
                self?.guarded.withLock { $0.observers[id] = nil }
            }
            return stream
        }
    }
#endif
