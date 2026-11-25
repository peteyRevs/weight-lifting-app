import Foundation
import LedgerDomain
import LedgerFakes
@testable import LedgerHealth
import Synchronization
import Testing

/// The phone's `LiveHealthStore` (F16 S3a, S3b; criteria 7, 8 and 12) over a scripted mirror and scripted phone calls:
/// no HealthKit, and time moves only on `ManualClock`.
@Suite("Live health store on the phone", .timeLimit(.minutes(1)))
struct LiveHealthStorePhoneTests {
    static let metadata = HealthStoreContractTests.metadata
    static let start = Fixtures.now
    static let end = Fixtures.now.addingTimeInterval(3600)

    static func store(
        mirror: ScriptedMirror = ScriptedMirror(),
        phone: ScriptedPhone = ScriptedPhone(),
        status: HealthAuthorization = .authorized,
        clock: ManualClock = ManualClock(),
        watchTookPart: @escaping @Sendable (WorkoutID) async -> Bool = { _ in false },
        onMirrorStart: @escaping @Sendable (WorkoutID?) async -> Void = { _ in }
    ) -> LiveHealthStore {
        LiveHealthStore(
            provider: ScriptedProvider(status: status),
            brandName: "Ledger",
            clock: clock,
            mirror: mirror,
            phone: phone,
            watchTookPart: watchTookPart,
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

    @Test("Asking the watch to start returns once it opens; any failure, or no answer in 10 s, is watchAppUnavailable")
    func requestWatchStart() async throws {
        try await Self.store().requestWatchStart()
        let failing = Self.store(phone: ScriptedPhone(watchStart: .fails(.underlying(code: 4))))
        await #expect(throws: HealthError.watchAppUnavailable) { try await failing.requestWatchStart() }
        let refused = Self.store(phone: ScriptedPhone(watchStart: .fails(.notAuthorized)))
        await #expect(throws: HealthError.notAuthorized) { try await refused.requestWatchStart() }
        let clock = ManualClock()
        let silent = Self.store(phone: ScriptedPhone(watchStart: .hangs), clock: clock)
        let asking = Task { try await silent.requestWatchStart() }
        #expect(await clock.nextSleep(skipping: .zero) == .seconds(10))
        clock.advance(by: .seconds(10))
        await #expect(throws: HealthError.watchAppUnavailable) { try await asking.value }
    }

    @Test("A phone-only save writes the metadata and returns no heart rate or energy; it needs authorization")
    func saveWorkout_phoneOnly_hasNoHeartRate() async throws {
        let phone = ScriptedPhone()
        let record = try await Self.store(phone: phone).saveWorkout(
            metadata: Self.metadata,
            start: Self.start,
            end: Self.end
        )
        #expect(record.healthKitUUID == ScriptedSession.workout.uuid)
        #expect(record.start == Self.start && record.end == Self.end)
        #expect(record.avgHeartRate == nil && record.maxHeartRate == nil && record.activeEnergyKcal == nil)
        #expect(phone.saves.first?.metadata == Self.metadata.healthKitEntries(brandName: "Ledger"))
        await #expect(throws: HealthError.notAuthorized) {
            try await Self.store(status: .denied).saveWorkout(metadata: Self.metadata, start: Self.start, end: Self.end)
        }
    }

    @Test("A workout a watch took part in is refused: the watch's session writes it")
    func saveWorkout_refusedWhenWatchParticipant() async {
        let phone = ScriptedPhone()
        let asked = Mutex<[WorkoutID]>([])
        let store = Self.store(phone: phone, watchTookPart: { id in
            asked.withLock { $0.append(id) }
            return true
        })
        await #expect(throws: HealthError.watchSavesThisWorkout) {
            try await store.saveWorkout(metadata: Self.metadata, start: Self.start, end: Self.end)
        }
        #expect(phone.saves.isEmpty)
        #expect(asked.withLock { $0 } == [Self.metadata.workoutID])
    }

    @Test("A saved workout is read back with its statistics; one Health does not hold is nil")
    func workoutRecord() async throws {
        let store = Self.store()
        let record = try #require(try await store.workoutRecord(healthKitUUID: ScriptedSession.workout.uuid))
        #expect(record.avgHeartRate == 118 && record.maxHeartRate == 162 && record.activeEnergyKcal == 240)
        #expect(try await store.workoutRecord(healthKitUUID: Fixtures.uuid(99)) == nil)
    }

    @Test("The phone's request to start, as the watch app is handed it, is reported")
    func startRequestedByPhone() async {
        let store = LiveHealthStore(provider: ScriptedProvider())
        store.noteStartRequestedByPhone()
        #expect(await HealthStoreContractTests.next(1, of: store.events) == [.startRequestedByPhone])
    }

    @Test("By default a workout counts as the phone's alone and a mirror start runs no hook; no mirror, no send")
    func defaults_phoneOnlyAndNoHook() async throws {
        let mirror = ScriptedMirror()
        let store = LiveHealthStore(provider: ScriptedProvider(), mirror: mirror, phone: ScriptedPhone())
        mirror.play(.connected)
        #expect(await HealthStoreContractTests.next(1, of: store.events) == [.mirrorConnected])
        _ = try await store.saveWorkout(metadata: Self.metadata, start: Self.start, end: Self.end)
        await #expect(throws: HealthError.noActiveSession) {
            try await LiveHealthStore(provider: ScriptedProvider()).send(Data([1]))
        }
    }
}
