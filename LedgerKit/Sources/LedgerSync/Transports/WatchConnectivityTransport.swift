import Foundation
import LedgerDomain
import os
import Synchronization

/// The live transport over WatchConnectivity's messages (F17 S7; ADR-005 §3): the frames mirroring carries go here
/// too, while the peer is reachable, so a set reaches the other screen in under a second (criterion 13) and a hung
/// mirrored send still has a way out (criterion 6).
/// - **Only while reachable:** a send while the session says the peer is unreachable throws `unreachable` and
///   sends nothing; the next handshake replays it.
/// - **A send returns once handed to the session.** `sendMessageData` queues the data and returns; a failure comes
///   later through its error handler, and is logged and swallowed: delivery is not guaranteed by design (ADR-005
///   §5), and the host's handshakes heal what is lost. So a send never hangs the host's sender.
/// - Each frame is cut by `WireCodec` (60 000 bytes, under the session's measured 65 536, R1 §2.6), and each part
///   goes as one message; each message that arrives is decoded alone, one that cannot be read is logged and dropped.
///
/// The session reaches the transport through `MessageSession` (sending) and `CompanionSessionActivator`, the
/// session's one delegate, which reports reachability and hands over each message (`reachabilityChanged(_:)`,
/// `received(_:)`). WatchConnectivity calls the delegate on a queue of its own, synchronously, so the last
/// reported reachability sits behind a `Mutex` (engineering-standards §4's exception for state a framework
/// callback writes).
public final class WatchConnectivityTransport: LiveWorkoutTransport {
    public let incoming: AsyncStream<WireFrame>
    /// `false` when made, then each change of the peer's reachability. One consumer.
    public let link: AsyncStream<Bool>

    private let session: any MessageSession
    private let incomingSink: AsyncStream<WireFrame>.Continuation
    private let linkSink: AsyncStream<Bool>.Continuation
    private let isReachable = Mutex(false)
    private let logger = Logger(subsystem: "com.petearevalo.Ledger", category: "sync")

    init(session: any MessageSession) {
        self.session = session
        (incoming, incomingSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        (link, linkSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        linkSink.yield(false)
    }

    /// Hands `frame` to the session, cut to the limit, and returns. Throws `unreachable` while the peer is not
    /// reachable, `tooLarge` (or the codec's `unencodable`) when the frame cannot be encoded; nothing is sent then.
    public func send(_ frame: WireFrame) async throws {
        guard session.isReachable else {
            throw TransportError.unreachable
        }
        let parts: [Data]
        do {
            parts = try WireCodec.encode(frame)
        } catch {
            logger.error("A frame was not encoded: \(String(describing: error), privacy: .public)")
            throw error as? WireCodecError == .tooLarge ? TransportError.tooLarge : error
        }
        let log = logger
        for data in parts {
            session.sendMessageData(data) { error in
                log.notice("A WatchConnectivity message failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// The session reports whether the peer is reachable (after activation, and on each change).
    func reachabilityChanged(_ reachable: Bool) {
        let changed = isReachable.withLock { last in
            defer { last = reachable }
            return last != reachable
        }
        if changed {
            linkSink.yield(reachable)
        }
    }

    /// A message from the peer onto `incoming`; one that cannot be read is dropped, and the next handshake replays
    /// what it held.
    func received(_ data: Data) {
        do {
            try incomingSink.yield(WireCodec.decode(data))
        } catch {
            logger.notice("A WatchConnectivity message was not read: \(String(describing: error), privacy: .public)")
        }
    }
}

/// What the transport needs of WatchConnectivity's session, so its tests hand it a stand-in (testing-strategy §3:
/// no WatchConnectivity in tests). In the app it is `WCSession.default` (`DefaultMessageSession`).
protocol MessageSession: Sendable {
    /// Whether the peer is reachable now (`WCSession.isReachable`).
    var isReachable: Bool { get }
    /// Queues `data` for the peer and returns at once; `failed` is called later if it was not delivered.
    func sendMessageData(_ data: Data, failed: @escaping @Sendable (any Error) -> Void)
}
