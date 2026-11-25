import Foundation
import LedgerDomain
@testable import LedgerHealth
import Synchronization
import Testing

/// `MirroringStartRegistrar` (ADR-005) over a stand-in handler slot and session type: no HealthKit in tests
/// (testing-strategy §3). The handler it installs keeps every session it is handed, from whatever thread.
@Suite("Mirroring start registrar", .timeLimit(.minutes(1)))
struct MirroringStartRegistrarTests {
    final class Session: Sendable {}

    /// Stands in for `HKHealthStore.workoutSessionMirroringStartHandler`.
    final class HandlerSlot: Sendable {
        private let slot = Mutex<(@Sendable (Session) -> Void)?>(nil)

        var handler: (@Sendable (Session) -> Void)? {
            slot.withLock { $0 }
        }

        func install(_ handler: @escaping @Sendable (Session) -> Void) {
            slot.withLock { $0 = handler }
        }
    }

    static func identities(_ sessions: [Session]) -> [ObjectIdentifier] {
        sessions.map(ObjectIdentifier.init)
    }

    @Test("register() installs the handler, and nothing before it")
    func register_installsTheHandler() {
        let slot = HandlerSlot()
        let registrar = MirroringStartRegistrar(install: slot.install)
        #expect(slot.handler == nil)
        registrar.register()
        #expect(slot.handler != nil)
    }

    @Test("The handler keeps every session it is handed, in order")
    func handler_keepsEverySession() throws {
        let slot = HandlerSlot()
        let registrar = MirroringStartRegistrar(install: slot.install)
        registrar.register()
        let handler = try #require(slot.handler)
        let sessions = [Session(), Session(), Session()]
        sessions.forEach(handler)
        #expect(Self.identities(registrar.mirroredSessions) == Self.identities(sessions))
    }

    @Test("Sessions handed over concurrently are all kept")
    func handler_concurrentCalls_keepAll() async throws {
        let slot = HandlerSlot()
        let registrar = MirroringStartRegistrar(install: slot.install)
        registrar.register()
        let handler = try #require(slot.handler)
        let sessions = (0 ..< 50).map { _ in Session() }
        await withTaskGroup { group in
            for session in sessions {
                group.addTask { handler(session) }
            }
        }
        #expect(Set(Self.identities(registrar.mirroredSessions)) == Set(Self.identities(sessions)))
    }

    @Test("The handler does not keep its registrar alive")
    func handler_doesNotRetainTheRegistrar() throws {
        let slot = HandlerSlot()
        weak var weakRegistrar: MirroringStartRegistrar<Session>?
        do {
            let registrar = MirroringStartRegistrar(install: slot.install)
            registrar.register()
            weakRegistrar = registrar
        }
        #expect(weakRegistrar == nil)
        let handler = try #require(slot.handler)
        handler(Session()) // reaches no registrar, and does not crash
    }
}

/// Each kept session's delegate and channel (F16 S3; criterion 7), over stand-ins for HealthKit's.
extension MirroringStartRegistrarTests {
    static func registrar(
        _ delegates: MirroredDelegates,
        recover: @escaping @Sendable () -> Session? = { nil }
    ) -> MirroringStartRegistrar<Session> {
        MirroringStartRegistrar(
            install: { _ in },
            observe: delegates.observe,
            send: { delegates.send($0, $1) },
            recover: recover
        )
    }

    static func next(_ count: Int, of registrar: MirroringStartRegistrar<Session>) async -> [MirrorEvent] {
        await HealthStoreContractTests.next(count, of: registrar.mirrorEvents)
    }

    @Test("Every session the handler is handed is kept and observed, each reported connected")
    func startHandler_retainsEverySession() async {
        let delegates = MirroredDelegates()
        let registrar = Self.registrar(delegates)
        let sessions = [Session(), Session(), Session()]
        sessions.forEach(registrar.keep)
        #expect(Self.identities(registrar.mirroredSessions) == Self.identities(sessions))
        #expect(delegates.observed == 3)
        #expect(await Self.next(3, of: registrar) == [.connected, .connected, .connected])
    }

    @Test("A send goes to the newest session, and to the next one as soon as it is kept")
    func startHandler_rebindsChannelToNewest() async throws {
        let delegates = MirroredDelegates()
        let registrar = Self.registrar(delegates)
        await #expect(throws: HealthError.noActiveSession) { try await registrar.send(Data([1])) }
        let first = Session()
        let second = Session()
        registrar.keep(first)
        try await registrar.send(Data([1]))
        registrar.keep(second)
        try await registrar.send(Data([2]))
        #expect(delegates.sent == Self.identities([first, second]))
    }

    @Test("A disconnect drops only that session; sends go to the newest left; batches arrive in order")
    func disconnect_dropsOnlyThatSession() async throws {
        let delegates = MirroredDelegates()
        let registrar = Self.registrar(delegates)
        let sessions = [Session(), Session(), Session()]
        sessions.forEach(registrar.keep)
        delegates.report(.received([Data([7])]), from: sessions[0])
        delegates.report(.disconnected, from: sessions[1])
        #expect(Self.identities(registrar.mirroredSessions) == Self.identities([sessions[0], sessions[2]]))
        delegates.report(.disconnected, from: sessions[2])
        try await registrar.send(Data([1]))
        #expect(delegates.sent == Self.identities([sessions[0]]))
        #expect(await Self.next(6, of: registrar).suffix(3) == [.received([Data([7])]), .disconnected, .disconnected])
    }

    @Test("Recovery keeps the session the system kept, as the newest; without one it keeps nothing")
    func recover_keepsTheSession() async throws {
        let delegates = MirroredDelegates()
        let kept = Session()
        let registrar = Self.registrar(delegates, recover: { kept })
        #expect(try await registrar.recover())
        #expect(Self.identities(registrar.mirroredSessions) == Self.identities([kept]))
        #expect(await Self.next(1, of: registrar) == [.connected])
        #expect(try await !Self.registrar(MirroredDelegates()).recover())
    }

    @Test("A registrar given only its handler slot keeps sessions, sends nowhere and recovers nothing")
    func defaults_observeNothing() async throws {
        let registrar = MirroringStartRegistrar<Session>(install: { _ in })
        registrar.keep(Session())
        try await registrar.send(Data([1]))
        #expect(try await !registrar.recover())
        #expect(registrar.mirroredSessions.count == 1)
    }
}

private typealias TestSession = MirroringStartRegistrarTests.Session
private typealias Report = @Sendable (MirroringStartRegistrar<TestSession>.Callback) -> Void

/// Stands in for each session's delegate and for `sendToRemoteWorkoutSession`: what each was handed.
final class MirroredDelegates: Sendable {
    private let state = Mutex((reports: [ObjectIdentifier: Report](), sent: [ObjectIdentifier]()))

    func observe(
        _ session: MirroringStartRegistrarTests.Session,
        _ report: @escaping @Sendable (MirroringStartRegistrar<MirroringStartRegistrarTests.Session>.Callback) -> Void
    ) -> any Sendable {
        state.withLock { $0.reports[ObjectIdentifier(session)] = report }
        return ()
    }

    func send(_ session: MirroringStartRegistrarTests.Session, _: Data) {
        state.withLock { $0.sent.append(ObjectIdentifier(session)) }
    }

    /// The session's delegate reports `callback`, as HealthKit would call it.
    func report(
        _ callback: MirroringStartRegistrar<MirroringStartRegistrarTests.Session>.Callback,
        from session: MirroringStartRegistrarTests.Session
    ) {
        state.withLock { $0.reports[ObjectIdentifier(session)] }?(callback)
    }

    var observed: Int {
        state.withLock { $0.reports.count }
    }

    var sent: [ObjectIdentifier] {
        state.withLock { $0.sent }
    }
}
