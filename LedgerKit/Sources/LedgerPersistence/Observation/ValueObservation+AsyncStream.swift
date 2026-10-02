import GRDB
import os

extension ValueObservation where Reducer: ValueReducer, Reducer.Value: Sendable {
    /// The observation as the `AsyncStream` a repository's `observe…()` returns (ADR-002: a thin bridge
    /// of our own, no GRDBQuery).
    ///
    /// - Values arrive on the cooperative thread pool (GRDB's `.task` scheduler), the current value
    ///   first. Each is a whole state, so a consumer that falls behind gets only the newest.
    /// - The observation stops when the stream terminates, which happens when the consumer's task ends.
    /// - When the observation fails, the error is logged and the stream finishes: an `AsyncStream`
    ///   cannot throw, and the repository protocols return one.
    func stream(in reader: some DatabaseReader) -> AsyncStream<Reducer.Value> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let cancellable = start(in: reader, scheduling: .task) { error in
                Logger.persistence.error("A database observation failed, so its stream ended: \(error)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
}

/// A repository's observation: a fetch, emitted only when its value differs from the last one.
typealias DistinctObservation<Value: Equatable & Sendable> = ValueObservation<
    ValueReducers.RemoveDuplicates<ValueReducers.Fetch<Value>>
>

extension Logger {
    /// LedgerPersistence's log (engineering-standards §8).
    static let persistence = Logger(subsystem: "com.petearevalo.Ledger", category: "persistence")
}
