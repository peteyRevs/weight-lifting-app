import Foundation

/// The raw data channel of a mirrored workout session (ADR-005), which F17's `MirroringTransport` encodes
/// envelopes over. It survives the session underneath it being replaced: each reconnect rebinds it.
public protocol RemoteSessionChannel: Sendable {
    /// `true` while a mirrored session is connected, `false` when it drops. One consumer.
    var connection: AsyncStream<Bool> { get }
    /// Each batch the other device sent (`didReceiveDataFromRemoteWorkoutSession`), in arrival order. One
    /// consumer.
    var incoming: AsyncStream<[Data]> { get }
    /// Sends `data` as it is (`sendToRemoteWorkoutSession`). It has no timeout of its own: F17's watchdog owns
    /// that.
    func send(_ data: Data) async throws
}
