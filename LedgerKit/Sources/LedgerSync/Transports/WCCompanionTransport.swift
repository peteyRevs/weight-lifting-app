import Foundation
import LedgerDomain
import os
import Synchronization

/// `CompanionTransport` over WatchConnectivity's queued calls (F19 S4; architecture §8, ADR-005 §5–6): the context
/// as the application context, a finished workout as user info, a program or a large workout as a file.
/// - **Each payload is `CompanionCodec` bytes under one key** (`payloadKey`) of the dictionary the call carries; a
///   file holds the bytes alone. F17's live frames travel as message data, never as a dictionary, and a live frame
///   is never read as a companion payload (nor one as the other: their magic bytes differ).
/// - **Queue and forget.** Each send encodes first (so a payload the codec refuses is never handed over), then
///   throws `CompanionTransportError.unavailable`, handing over nothing, unless the session is activated and the
///   peer app is installed; otherwise it hands the payload to the session and returns.
/// - A file is written to `outbox` and handed to `transferFile`, which reads it later: it is removed once the
///   session reports the transfer finished (`finishedTransfer(of:error:)`), delivered or failed.
/// - Each payload that arrives is decoded alone; one that cannot be read is logged and dropped.
/// - The Simulator delivers no user info and no file (R1 §2.6, criterion 11): there the first such send logs that
///   once, and is handed to the session all the same.
///
/// The session reaches it through `CompanionWCSession` (sending) and `CompanionSessionActivator`, the session's
/// one delegate, which hands over what arrives and each finished file transfer. The delegate is called on a queue
/// of WatchConnectivity's own, synchronously: a received file is read before its callback returns, since the
/// session deletes it then.
public final class WCCompanionTransport: CompanionTransport {
    /// The key of the dictionary entry that holds a payload's bytes.
    static let payloadKey = "com.petearevalo.Ledger.companion"

    public let receivedContext: AsyncStream<CompanionContext>
    public let receivedFiles: AsyncStream<CompanionFile>
    public let receivedRecords: AsyncStream<FinishedWorkoutRecord>

    private let session: any CompanionWCSession
    private let outbox: URL
    private let log: @Sendable (String) -> Void
    private let readFile: @Sendable (URL) -> Data?
    private let contextSink: AsyncStream<CompanionContext>.Continuation
    private let fileSink: AsyncStream<CompanionFile>.Continuation
    private let recordSink: AsyncStream<FinishedWorkoutRecord>.Continuation
    private let hasLoggedUnsupported = Mutex(false)

    /// A transport over `session` that writes outgoing files into `outbox`, reads arriving ones with `readFile`
    /// and reports through `log`.
    init(
        session: any CompanionWCSession,
        outbox: URL = URL.temporaryDirectory.appending(path: "CompanionOutbox", directoryHint: .isDirectory),
        readFile: @escaping @Sendable (URL) -> Data? = { try? Data(contentsOf: $0) },
        log: @escaping @Sendable (String) -> Void = WCCompanionTransport.notice
    ) {
        self.session = session
        self.outbox = outbox
        self.readFile = readFile
        self.log = log
        (receivedContext, contextSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        (receivedFiles, fileSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        (receivedRecords, recordSink) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    public var isPaired: Bool {
        session.isPaired
    }

    public var isWatchAppInstalled: Bool {
        session.isCounterpartAppInstalled
    }

    public func updateContext(_ context: CompanionContext) async throws {
        let data = try CompanionCodec.encode(context)
        try checkAvailable()
        do {
            try session.updateApplicationContext([Self.payloadKey: data])
        } catch {
            log("The application context was not updated: \(error)")
            throw error
        }
    }

    public func transfer(_ file: CompanionFile) async throws {
        let data = try CompanionCodec.encode(file)
        try checkAvailable()
        let url = outbox.appending(path: "\(UUID().uuidString).ledger")
        try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        noteIfUnsupported()
        session.transferFile(url, metadata: nil)
    }

    public func enqueue(_ record: FinishedWorkoutRecord) async throws {
        let data = try CompanionCodec.encode(record)
        guard CompanionCodec.delivery(forEncodedSize: data.count) == .userInfo else {
            throw CompanionCodecError.tooLarge
        }
        try checkAvailable()
        noteIfUnsupported()
        session.transferUserInfo([Self.payloadKey: data])
    }

    /// The peer's application context arrived.
    func received(context dictionary: [String: Any]) {
        if let context = decode(CompanionContext.self, from: dictionary[Self.payloadKey] as? Data, kind: "context") {
            contextSink.yield(context)
        }
    }

    /// User info the peer queued arrived.
    func received(userInfo dictionary: [String: Any]) {
        let data = dictionary[Self.payloadKey] as? Data
        if let record = decode(FinishedWorkoutRecord.self, from: data, kind: "user info") {
            recordSink.yield(record)
        }
    }

    /// A file the peer sent arrived at `url`: read here, before the caller returns and the session deletes it.
    func received(fileAt url: URL) {
        if let file = decode(CompanionFile.self, from: readFile(url), kind: "file") {
            fileSink.yield(file)
        }
    }

    /// The session finished a file transfer, delivered or not: the file is removed when it is one of `outbox`'s.
    func finishedTransfer(of url: URL, error: (any Error)?) {
        if let error {
            log("A file transfer failed: \(error)")
        }
        guard url.deletingLastPathComponent().resolvingSymlinksInPath() == outbox.resolvingSymlinksInPath() else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    private func checkAvailable() throws {
        guard session.isActivated, session.isCounterpartAppInstalled else {
            throw CompanionTransportError.unavailable
        }
    }

    private func noteIfUnsupported() {
        guard !session.supportsQueuedTransfers else {
            return
        }
        let isFirst = hasLoggedUnsupported.withLock { logged in
            defer { logged = true }
            return !logged
        }
        if isFirst {
            log("This device delivers no user info and no file (the Simulator): they are queued and never arrive")
        }
    }

    private func decode<Payload: CompanionPayload>(_ type: Payload.Type, from data: Data?, kind: String) -> Payload? {
        guard let data else {
            log("A companion \(kind) without a payload was dropped")
            return nil
        }
        do {
            return try CompanionCodec.decode(type, from: data)
        } catch {
            log("A companion \(kind) was not read: \(error)")
            return nil
        }
    }

    @Sendable static func notice(_ message: String) {
        Logger(subsystem: "com.petearevalo.Ledger", category: "sync").notice("\(message, privacy: .public)")
    }
}

/// What the companion transport needs of WatchConnectivity's session, so its tests hand it a stand-in
/// (testing-strategy §3: no WatchConnectivity in tests). In the app it is `WCSession.default`
/// (`DefaultCompanionWCSession`).
protocol CompanionWCSession: Sendable {
    /// Whether the session is activated (`activationState == .activated`): only then may it queue anything.
    var isActivated: Bool { get }
    /// Whether a watch is paired with this phone (`isPaired`); the watch answers `true`.
    var isPaired: Bool { get }
    /// Whether Ledger is installed on the peer (`isWatchAppInstalled`; on the watch, `isCompanionAppInstalled`).
    var isCounterpartAppInstalled: Bool { get }
    /// Whether queued user info and files are delivered: false in the Simulator.
    var supportsQueuedTransfers: Bool { get }
    /// `updateApplicationContext(_:)`.
    func updateApplicationContext(_ context: [String: Any]) throws
    /// `transferUserInfo(_:)`.
    func transferUserInfo(_ userInfo: [String: Any])
    /// `transferFile(_:metadata:)`.
    func transferFile(_ url: URL, metadata: [String: Any]?)
}
