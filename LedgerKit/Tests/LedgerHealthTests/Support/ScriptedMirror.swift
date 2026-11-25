import Foundation
@testable import LedgerHealth
import Synchronization

/// The phone's mirrored sessions, scripted (F16 S3a): the test plays `MirrorEvent`s and reads what was sent.
final class ScriptedMirror: MirrorReceiver {
    let mirrorEvents: AsyncStream<MirrorEvent>
    private let sink: AsyncStream<MirrorEvent>.Continuation
    private let state: Mutex<(sent: [Data], recoverable: Bool)>

    init(recoverable: Bool = false) {
        (mirrorEvents, sink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        state = Mutex(([], recoverable))
    }

    var sent: [Data] {
        state.withLock { $0.sent }
    }

    func play(_ event: MirrorEvent) {
        sink.yield(event)
    }

    func send(_ data: Data) {
        state.withLock { $0.sent.append(data) }
    }

    /// The kept session is taken up once.
    func recover() -> Bool {
        state.withLock { state in
            defer { state.recoverable = false }
            return state.recoverable
        }
    }
}
