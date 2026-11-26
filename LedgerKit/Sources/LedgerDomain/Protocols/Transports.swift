import Foundation

/// One live phone ⇄ watch channel for a workout's frames (architecture §8, ADR-005; F17). LedgerSync has two, over
/// HealthKit's mirrored session and WatchConnectivity, and one that fans out to both; LedgerFakes' fake runs over
/// an in-memory network.
///
/// A transport does not guarantee delivery: a frame may be lost, arrive twice or overtake another. The host makes
/// that harmless: envelopes are idempotent by `(device, seq)`, and a handshake on every link-up replays the gaps
/// (ADR-005 §3).
public protocol LiveWorkoutTransport: Sendable {
    /// Every frame the peer sent that arrived, in arrival order, for the life of the transport. One consumer.
    var incoming: AsyncStream<WireFrame> { get }
    /// Whether the peer is reachable on this transport: the state when the transport was made first, then each
    /// change, and `true` again each time a channel comes up while another already reaches the peer (a new
    /// channel must carry a handshake first). One consumer. The host sends its handshake on every `true`.
    var link: AsyncStream<Bool> { get }
    /// Hands `frame` to the transport. Returning means the frame left this device, not that it arrived. Throws a
    /// `TransportError`. A send may also never return (a mirrored session's send can hang, R1 §2.5): the caller
    /// bounds it with its own timeout and cancels it, and a cancelled send throws `CancellationError`.
    func send(_ frame: WireFrame) async throws
}

/// Why a `LiveWorkoutTransport` did not send a frame.
public enum TransportError: Error, Equatable, Sendable {
    /// The peer is not reachable on this transport now; nothing was sent.
    case unreachable
    /// The send did not return in time (the transport's watchdog).
    case timeout
    /// The frame cannot be cut to the transport's limit (`WireCodecError.tooLarge`).
    case tooLarge
}

/// A live transport the workout's frames can travel on.
public enum Channel: Hashable, Sendable {
    /// HealthKit's mirrored workout session (`sendToRemoteWorkoutSession`).
    case mirroring
    /// `WCSession.sendMessageData`, while the peer is reachable.
    case watchConnectivity
}

/// What the workout screen says about the other device (F17 criterion 12): logging never waits on it.
public enum LiveConnectionState: Hashable, Sendable {
    /// No other device takes part, or it has been out of reach for longer than a reconnect takes.
    case solo
    /// Frames reach the other device on this channel.
    case connected(Channel)
    /// The other device dropped out of reach a short while ago.
    case reconnecting
    /// This channel failed and stays failed for the workout (a hung mirrored send, R1 §2.5, gives
    /// `.degraded(.mirroring)`); frames go on the other channel while it reaches the other device.
    case degraded(Channel)
}

public extension LiveConnectionState {
    /// F17 criterion 12 (S8, decision 1), one rule for both devices: whether a workout screen says the other device
    /// is out of reach. It does while `connection` is `.reconnecting`, and in `.solo` once the screen has heard any
    /// other state (`hasHeardThePeer`): the other device took part and is still away. Connected says nothing, nor
    /// degraded, whose other channel still reaches it, nor a solo never preceded by another state, so a lifter with
    /// one device never reads the line. Nil is a connection not heard yet.
    static func isPeerAway(_ connection: LiveConnectionState?, hasHeardThePeer: Bool) -> Bool {
        switch connection {
        case .reconnecting: true
        case .solo: hasHeardThePeer
        case .connected, .degraded, nil: false
        }
    }
}

/// The live connection to the other device, as the workout screen shows it (F17 S7b, criterion 12). Any number of
/// readers: each call is a stream of its own.
public protocol LiveConnectionClient: Sendable {
    /// The state now, then each change, until the connection's owner stops.
    func states() async -> AsyncStream<LiveConnectionState>
}

/// Non-live phone ⇄ watch transfer: programs, settings, finished workouts (architecture §8).
/// Shape only: full contract in F19.
public protocol CompanionTransport: Sendable {}
