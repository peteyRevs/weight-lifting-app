import Foundation
import LedgerDomain
@testable import LedgerHealth
import Synchronization
import Testing

/// The phone's `LiveHealthStore` (F16 S3a; criterion 7) over a scripted mirror: no HealthKit.
@Suite("Live health store on the phone", .timeLimit(.minutes(1)))
struct LiveHealthStorePhoneTests {
    static func store(
        mirror: ScriptedMirror = ScriptedMirror(),
        onMirrorStart: @escaping @Sendable (WorkoutID?) async -> Void = { _ in }
    ) -> LiveHealthStore {
        LiveHealthStore(
            provider: ScriptedProvider(),
            clock: ManualClock(),
            mirror: mirror,
            onMirrorStart: onMirrorStart
        )
    }

    @Test("Each mirrored session is reported connected, then the hook runs; a drop and the watch's batches follow")
    func mirror_eventsReachTheStore() async {
        let mirror = ScriptedMirror()
        let starts = Mutex<[WorkoutID?]>([])
        let store = Self.store(mirror: mirror, onMirrorStart: { id in starts.withLock { $0.append(id) } })
        mirror.play(.connected)
        mirror.play(.disconnected)
        mirror.play(.connected)
        mirror.play(.received([Data([5])]))
        #expect(await HealthStoreContractTests.next(3, of: store.events) == [
            .mirrorConnected, .mirrorDisconnected, .mirrorConnected
        ])
        #expect(await HealthStoreContractTests.next(3, of: store.remoteChannel.connection) == [true, false, true])
        #expect(await HealthStoreContractTests.next(1, of: store.remoteChannel.incoming) == [[Data([5])]])
        #expect(starts.withLock { $0 } == [nil, nil])
    }

    @Test("A send goes over the newest mirrored session; recovery takes up the kept one, once")
    func mirror_sendAndRecovery() async throws {
        let mirror = ScriptedMirror(recoverable: true)
        let store = Self.store(mirror: mirror)
        try await store.remoteChannel.send(Data([1, 2]))
        #expect(mirror.sent == [Data([1, 2])])
        #expect(try await store.recoverActiveSession())
        #expect(try await !store.recoverActiveSession())
        #expect(await HealthStoreContractTests.next(1, of: store.events) == [.recovered])
    }

    @Test("The phone's request to start, as the watch app is handed it, is reported")
    func startRequestedByPhone() async {
        let store = LiveHealthStore(provider: ScriptedProvider())
        store.noteStartRequestedByPhone()
        #expect(await HealthStoreContractTests.next(1, of: store.events) == [.startRequestedByPhone])
    }

    @Test("By default a mirror start runs no hook; without a mirror a send has nowhere to go")
    func defaults_noHook() async {
        let mirror = ScriptedMirror()
        let store = LiveHealthStore(provider: ScriptedProvider(), mirror: mirror)
        mirror.play(.connected)
        #expect(await HealthStoreContractTests.next(1, of: store.events) == [.mirrorConnected])
        await #expect(throws: HealthError.noActiveSession) {
            try await LiveHealthStore(provider: ScriptedProvider()).send(Data([1]))
        }
    }
}
