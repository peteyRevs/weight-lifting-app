import Foundation
import LedgerDomain
@testable import LedgerSync
import LedgerTestSupport
import Synchronization
import Testing

/// A WatchConnectivity session that answers as told and keeps what it is handed: each dictionary's keys and the
/// bytes under the payload key, and each file's URL and its bytes, read when it is handed over.
final class StandInCompanionSession: CompanionWCSession {
    struct State {
        var isActivated = true
        var isPaired = true
        var isCounterpartAppInstalled = true
        var supportsQueuedTransfers = true
        var failsContext = false
        var contexts: [[String: Data]] = []
        var userInfos: [[String: Data]] = []
        var files: [(url: URL, bytes: Data?)] = []
    }

    let state = Mutex(State())

    var isActivated: Bool {
        state.withLock(\.isActivated)
    }

    var isPaired: Bool {
        state.withLock(\.isPaired)
    }

    var isCounterpartAppInstalled: Bool {
        state.withLock(\.isCounterpartAppInstalled)
    }

    var supportsQueuedTransfers: Bool {
        state.withLock(\.supportsQueuedTransfers)
    }

    /// How many payloads it was handed, of every kind.
    var handedCount: Int {
        state.withLock { $0.contexts.count + $0.userInfos.count + $0.files.count }
    }

    func updateApplicationContext(_ context: [String: Any]) throws {
        let copy = Self.bytes(context)
        try state.withLock { state in
            if state.failsContext {
                throw TransportError.unreachable
            }
            state.contexts.append(copy)
        }
    }

    func transferUserInfo(_ userInfo: [String: Any]) {
        let copy = Self.bytes(userInfo)
        state.withLock { $0.userInfos.append(copy) }
    }

    func transferFile(_ url: URL, metadata: [String: Any]?) {
        #expect(metadata == nil)
        let bytes = try? Data(contentsOf: url)
        state.withLock { $0.files.append((url, bytes)) }
    }

    private static func bytes(_ dictionary: [String: Any]) -> [String: Data] {
        dictionary.mapValues { $0 as? Data ?? Data() }
    }
}

/// What a transport logged, in order.
final class LogSink: Sendable {
    private let lines = Mutex<[String]>([])

    var all: [String] {
        lines.withLock { $0 }
    }

    func log(_ line: String) {
        lines.withLock { $0.append(line) }
    }
}

/// F19 S4: `WCCompanionTransport` over a stand-in session (testing-strategy §3, criterion 11): each payload under its
/// one key, the codec's and the session's refusals, files written to and cleared from the outbox, and what arrives.
@Suite("WCCompanionTransport", .tags(.sync), .timeLimit(.minutes(1)))
struct WCCompanionTransportTests {
    let session = StandInCompanionSession()
    let logs = LogSink()
    let outbox = URL.temporaryDirectory.appending(path: "WCCompanionTransportTests-\(UUID().uuidString)")
    let transport: WCCompanionTransport
    /// The peer's transport, which `deliver` hands what `session` was handed.
    let peer = WCCompanionTransport(session: StandInCompanionSession(), outbox: URL.temporaryDirectory, log: { _ in })

    init() {
        let sink = logs
        transport = WCCompanionTransport(session: session, outbox: outbox, log: { sink.log($0) })
    }

    @Test("A context goes as the application context, under its one key, and the peer reads it back")
    func context_roundTrips() async throws {
        try await transport.updateContext(FakeCompanionTransportTests.context(7))
        let handed = session.state.withLock(\.contexts)
        #expect(handed.map { Array($0.keys) } == [[WCCompanionTransport.payloadKey]])
        try peer.received(context: #require(handed.first))
        let arrived = await FakeLiveWorkoutTransportTests.next(1, of: peer.receivedContext)
        #expect(arrived == [FakeCompanionTransportTests.context(7)])
    }

    @Test("A record goes as user info, under its one key, and the peer reads it back")
    func record_roundTrips() async throws {
        try await transport.enqueue(FakeCompanionTransportTests.record(3))
        let handed = session.state.withLock(\.userInfos)
        #expect(handed.map { Array($0.keys) } == [[WCCompanionTransport.payloadKey]])
        try peer.received(userInfo: #require(handed.first))
        let arrived = await FakeLiveWorkoutTransportTests.next(1, of: peer.receivedRecords).map(\.workoutID)
        #expect(arrived == [FakeCompanionTransportTests.workout(3)])
    }

    @Test("A file is written to the outbox and handed over; the peer reads it; a finished transfer removes it")
    func file_roundTrips_thenIsRemoved() async throws {
        defer { try? FileManager.default.removeItem(at: outbox) }
        let file = try CompanionFile.program(Fixtures.seedProgram(), customExercises: [], lastPerformance: [:])
        try await transport.transfer(file)
        let handed = try #require(session.state.withLock(\.files).first)
        #expect(handed.url.deletingLastPathComponent().lastPathComponent == outbox.lastPathComponent)
        peer.received(fileAt: handed.url)
        let arrived = await FakeLiveWorkoutTransportTests.next(1, of: peer.receivedFiles)
        let same = arrived == [file]
        #expect(same, "the program file did not arrive as sent")
        #expect(handed.bytes == (try? Data(contentsOf: handed.url)))
        transport.finishedTransfer(of: handed.url, error: TransportError.unreachable)
        #expect(!FileManager.default.fileExists(atPath: handed.url.path(percentEncoded: false)))
        #expect(logs.all.count == 1, "the failed transfer is logged")
    }

    @Test("A finished transfer of a file outside the outbox leaves it")
    func finishedTransfer_outsideTheOutbox_keepsTheFile() throws {
        let elsewhere = URL.temporaryDirectory.appending(path: "WCCompanionTransportTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        try Data([1]).write(to: elsewhere)
        transport.finishedTransfer(of: elsewhere, error: nil)
        #expect(FileManager.default.fileExists(atPath: elsewhere.path(percentEncoded: false)))
    }

    @Test("A record over 60 000 bytes is refused as user info and hands nothing over; it goes as a file")
    func enqueue_refusesALargeRecord() async throws {
        defer { try? FileManager.default.removeItem(at: outbox) }
        var large = FakeCompanionTransportTests.record(1)
        large.log = (1 ... 600).map { seq in
            EventBuilders.envelope(.restSkipped, device: EventBuilders.watch, seq: UInt64(seq), at: EventBuilders.start)
        }
        await #expect(throws: CompanionCodecError.tooLarge) {
            try await transport.enqueue(large)
        }
        #expect(session.handedCount == 0)
        try await transport.transfer(.workoutLog(large))
        #expect(session.state.withLock(\.files).count == 1)
    }

    @Test("A context over the limit is refused and hands nothing over")
    func updateContext_refusesALargeContext() async {
        var context = FakeCompanionTransportTests.context(1)
        context.programName = String(repeating: "x", count: CompanionCodec.contextLimit)
        await #expect(throws: CompanionCodecError.tooLarge) {
            try await transport.updateContext(context)
        }
        #expect(session.handedCount == 0)
    }

    @Test("Unactivated, or without the peer app, every send throws unavailable and hands nothing over", arguments: [
        (activated: false, installed: true), (activated: true, installed: false)
    ])
    func unavailable_refusesEverySend(activated: Bool, installed: Bool) async throws {
        session.state.withLock { ($0.isActivated, $0.isCounterpartAppInstalled) = (activated, installed) }
        await #expect(throws: CompanionTransportError.unavailable) {
            try await transport.updateContext(FakeCompanionTransportTests.context(1))
        }
        await #expect(throws: CompanionTransportError.unavailable) {
            try await transport.transfer(.workoutLog(FakeCompanionTransportTests.record(1)))
        }
        await #expect(throws: CompanionTransportError.unavailable) {
            try await transport.enqueue(FakeCompanionTransportTests.record(1))
        }
        #expect(session.handedCount == 0)
        #expect(!FileManager.default.fileExists(atPath: outbox.path(percentEncoded: false)))
        #expect(transport.isWatchAppInstalled == installed && transport.isPaired)
    }

    @Test("The session's refusal of a context is logged and thrown")
    func updateContext_sessionFails_logsAndThrows() async {
        session.state.withLock { $0.failsContext = true }
        await #expect(throws: TransportError.unreachable) {
            try await transport.updateContext(FakeCompanionTransportTests.context(1))
        }
        #expect(logs.all.count == 1)
    }

    @Test("Where queued transfers are not delivered (the Simulator) the first one logs that, once; all are handed over")
    func unsupportedTransfers_logOnce() async throws {
        defer { try? FileManager.default.removeItem(at: outbox) }
        session.state.withLock { $0.supportsQueuedTransfers = false }
        try await transport.enqueue(FakeCompanionTransportTests.record(1))
        try await transport.enqueue(FakeCompanionTransportTests.record(2))
        try await transport.transfer(.workoutLog(FakeCompanionTransportTests.record(3)))
        #expect(logs.all.count == 1)
        #expect(session.handedCount == 3)
    }

    @Test("What cannot be read is logged and dropped; what follows arrives")
    func unreadable_isDropped() async throws {
        let live = try #require(WireCodec.encode(.handshake(workoutID: Sample.session.id, contiguousSeq: [:])).first)
        transport.received(context: ["other": Data([1])])
        transport.received(context: [WCCompanionTransport.payloadKey: live])
        transport.received(userInfo: [WCCompanionTransport.payloadKey: Data([0x43, 1, 0xFF])])
        transport.received(userInfo: [WCCompanionTransport.payloadKey: "not data"])
        transport.received(fileAt: outbox.appending(path: "missing"))
        #expect(logs.all.count == 5)
        let context = try CompanionCodec.encode(FakeCompanionTransportTests.context(2))
        transport.received(context: [WCCompanionTransport.payloadKey: context])
        let arrived = await FakeLiveWorkoutTransportTests.next(1, of: transport.receivedContext).map(\.revision)
        #expect(arrived == [2])
    }

    @Test("A received file is read on the caller's thread, inside the call: never after it returns")
    func receivedFile_isReadInsideTheCall() async throws {
        let readOn = Mutex<UInt?>(nil)
        let reading = WCCompanionTransport(session: session, outbox: outbox, readFile: { url in
            readOn.withLock { $0 = UInt(bitPattern: pthread_self()) }
            return try? Data(contentsOf: url)
        }, log: { _ in })
        let url = URL.temporaryDirectory.appending(path: "WCCompanionTransportTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try CompanionCodec.encode(CompanionFile.workoutLog(FakeCompanionTransportTests.record(6))).write(to: url)
        let caller = UInt(bitPattern: pthread_self())
        reading.received(fileAt: url)
        // Read now, on this thread, with no suspension since the call: a read in a task of its own could not be.
        let wasReadInside = readOn.withLock { $0 == caller }
        #expect(wasReadInside)
        let arrived = await FakeLiveWorkoutTransportTests.next(1, of: reading.receivedFiles)
        #expect(arrived.map(FakeCompanionTransportTests.workoutID) == [FakeCompanionTransportTests.workout(6)])
    }

    @Test("A received file is read before the call returns: removing it right after loses nothing")
    func receivedFile_isReadBeforeReturning() async throws {
        let url = URL.temporaryDirectory.appending(path: "WCCompanionTransportTests-\(UUID().uuidString)")
        try CompanionCodec.encode(CompanionFile.workoutLog(FakeCompanionTransportTests.record(4))).write(to: url)
        transport.received(fileAt: url)
        try FileManager.default.removeItem(at: url)
        let arrived = await FakeLiveWorkoutTransportTests.next(1, of: transport.receivedFiles)
        #expect(arrived.map(FakeCompanionTransportTests.workoutID) == [FakeCompanionTransportTests.workout(4)])
    }
}
