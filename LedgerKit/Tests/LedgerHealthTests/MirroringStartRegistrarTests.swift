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
