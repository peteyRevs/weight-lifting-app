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
    /// Set, once, when a stream has ended: read and set under no lock (a stream's `onTermination` must take none
    /// that a yield holds).
    public final class EndedFlag: Sendable {
        private let value = Atomic(false)

        public init() {}

        public var isSet: Bool {
            value.load(ordering: .acquiring)
        }

        public func set() {
            value.store(true, ordering: .releasing)
        }
    }

    final class ObservedState<State: Sendable>: Sendable {
        /// One stream's observer: it yields its value of a state when it differs from the last one it yielded,
        /// until its stream has ended.
        private struct Observer {
            let ended: EndedFlag
            let yield: (State) -> Void
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
                guarded.observers = guarded.observers.filter { !$0.value.ended.isSet }
                for observer in guarded.observers.values {
                    observer.yield(state)
                }
                return result
            }
        }

        /// `value` of the state now, then after every write that changes it. Ending the stream (its consumer's
        /// task cancelled, or the iterator dropped) stops the observation.
        func observe<Value: Equatable & Sendable>(
            _ value: @escaping @Sendable (State) -> Value
        ) -> AsyncStream<Value> {
            let (stream, continuation) = AsyncStream<Value>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let ended = EndedFlag()
            guarded.withLock { guarded in
                var last = value(guarded.state)
                guarded.observers[guarded.nextObserver] = Observer(ended: ended) { state in
                    let next = value(state)
                    if next != last {
                        last = next
                        continuation.yield(next)
                    }
                }
                guarded.nextObserver += 1
                continuation.yield(last)
            }
            // Takes no lock (F14 S1a fix round 3): a stream ends when its consumer's task is cancelled, and the
            // runtime calls this holding that task's lock; a write yielding under the `Mutex` takes the same task's
            // lock to resume it. Taking the `Mutex` here could deadlock the two. The next write drops the observer.
            continuation.onTermination = { _ in ended.set() }
            return stream
        }
    }
#endif
