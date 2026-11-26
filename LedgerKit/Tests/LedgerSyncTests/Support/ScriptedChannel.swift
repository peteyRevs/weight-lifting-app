import Foundation
import LedgerDomain
import Synchronization

/// A `RemoteSessionChannel` a test plays (F17 S6): it reports the connection and hands over batches when told,
/// and answers each send as its script says, in order (then `.sent`). Every send is announced on `sends` as it
/// begins, so a test waits for one without polling. A `.hang` answers only when `release()` is called, and not
/// when its task is cancelled: HealthKit's `sendToRemoteWorkoutSession` may never return (R1 §2.5 #2).
final class ScriptedChannel: RemoteSessionChannel {
    enum Answer {
        case sent
        case fails(any Error)
        case hang
    }

    let connection: AsyncStream<Bool>
    let incoming: AsyncStream<[Data]>
    /// Each send's data as it begins. One consumer.
    let sends: AsyncStream<Data>

    private struct State {
        var script: [Answer] = []
        var hanging: [CheckedContinuation<Void, Never>] = []
    }

    private let connectionSink: AsyncStream<Bool>.Continuation
    private let incomingSink: AsyncStream<[Data]>.Continuation
    private let sendsSink: AsyncStream<Data>.Continuation
    private let state = Mutex(State())

    init() {
        (connection, connectionSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        (incoming, incomingSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        (sends, sendsSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    /// The answers of the next sends, after any not yet used.
    func script(_ answers: Answer...) {
        state.withLock { $0.script += answers }
    }

    func connect(_ isUp: Bool) {
        connectionSink.yield(isUp)
    }

    func deliver(_ batch: [Data]) {
        incomingSink.yield(batch)
    }

    /// Lets every hanging send return, as if it had been sent late.
    func release() {
        let hanging = state.withLock { state in
            defer { state.hanging = [] }
            return state.hanging
        }
        hanging.forEach { $0.resume() }
    }

    func send(_ data: Data) async throws {
        let answer = state.withLock { state in
            state.script.isEmpty ? .sent : state.script.removeFirst()
        }
        sendsSink.yield(data)
        switch answer {
        case .sent:
            return
        case let .fails(error):
            throw error
        case .hang:
            await withCheckedContinuation { continuation in
                state.withLock { $0.hanging.append(continuation) }
            }
        }
    }
}

/// The one frame `data` holds.
func frame(of data: Data?) throws -> WireFrame? {
    try data.map(WireCodec.decode)
}
