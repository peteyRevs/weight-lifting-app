import Foundation

/// Non-live phone ⇄ watch transfer (architecture §8, ADR-005 §5–6; F19): the phone's context and program file to
/// the watch, finished workouts from the watch. LedgerSync builds it on WatchConnectivity's queued calls; LedgerFakes'
/// `FakeCompanionNetwork` joins two in memory.
///
/// Every call is queue-and-forget: returning means the payload was handed to the system, never that it arrived,
/// and nothing waits for the peer. Payloads travel as `CompanionCodec` bytes, so a peer on another version of
/// Ledger refuses them whole.
public protocol CompanionTransport: Sendable {
    /// Replaces the context the peer reads (`updateApplicationContext`): only the latest one sent is delivered.
    /// Throws `CompanionCodecError.tooLarge` for a context over `CompanionCodec.contextLimit`, and
    /// `CompanionTransportError.unavailable` when there is no peer app to send to.
    func updateContext(_ context: CompanionContext) async throws
    /// Queues `file` for the peer (`transferFile`): every file is delivered, in time. A finished workout goes this
    /// way when `CompanionCodec.delivery(for:)` says `.file`.
    func transfer(_ file: CompanionFile) async throws
    /// Queues `record` for the peer (`transferUserInfo`): delivered once, in the order queued, even after the app
    /// is suspended. Throws `CompanionCodecError.tooLarge` for a record `CompanionCodec.delivery(for:)` sends as a
    /// file.
    func enqueue(_ record: FinishedWorkoutRecord) async throws
    /// Each context the peer sent that arrived, newest last. One consumer.
    var receivedContext: AsyncStream<CompanionContext> { get }
    /// Each file the peer sent that arrived. One consumer.
    var receivedFiles: AsyncStream<CompanionFile> { get }
    /// Each record the peer queued that arrived, in its order. One consumer.
    var receivedRecords: AsyncStream<FinishedWorkoutRecord> { get }
    /// Whether a watch is paired with this phone (the watch answers `true`).
    var isPaired: Bool { get async }
    /// Whether Ledger is installed on the paired watch (on the watch: on its phone).
    var isWatchAppInstalled: Bool { get async }
}

/// Why a `CompanionTransport` did not take a payload.
public enum CompanionTransportError: Error, Equatable, Sendable {
    /// No paired device has the peer app installed: nothing was queued.
    case unavailable
}
