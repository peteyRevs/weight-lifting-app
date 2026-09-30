import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F05 S1 adversarial round 1: rows written by an earlier Codable shape, and appends in cancelled tasks.
/// Test finding 1 pinned what an app update that changes a payload's shape did to stored rows; the fix round
/// applies the orchestrator's decision (2026-09-30): versioned payloads, an unreadable event row left out of
/// its log but kept and counted, and settings that decode with a default for every missing key.
@Suite("Adversarial S1 · payload evolution and cancellation", .tags(.persistence), .timeLimit(.minutes(1)))
struct PayloadEvolutionAdversarialTests {
    typealias Contract = WorkoutEventStoreContract

    /// `envelope`'s payload as an app version before F04's label rename wrote it (`setLogged(…, at:)`).
    static func legacyPayload(_ envelope: EventEnvelope) throws -> Data {
        let json = try #require(String(data: EnvelopeCodec.encode(envelope), encoding: .utf8))
        return Data(json.replacingOccurrences(of: "\"doneAt\"", with: "\"at\"").utf8)
    }

    @Test("Decided: one payload the current codec cannot read is left out and kept; the rest of its log reads")
    func oneLegacyPayload_isLeftOut_andTheLogStillReads() async throws {
        let queue = try LedgerDatabase.inMemory()
        let store = GRDBWorkoutEventStore(queue, now: { EventBuilders.start })
        let legacy = Contract.logged(set: 0, doneAt: 5, seq: 1, stamp: 5)
        let readable = [Contract.start(Contract.workout), Contract.skip(2)]
        _ = try await store.append(readable)
        try await queue.write { database in
            try database.execute(
                sql: """
                INSERT INTO workout_event (workout_id, device_id, seq, wall_clock, payload_version, payload, created_at)
                VALUES (?, ?, 1, 5, 1, ?, 'then')
                """,
                arguments: [
                    ColumnCodec.text(legacy.workoutID),
                    ColumnCodec.text(legacy.device),
                    Self.legacyPayload(legacy)
                ]
            )
        }
        // The two readable envelopes still read back, so replay (and recovery, ADR-004 rule 6) can start.
        #expect(try await store.envelopes(for: Contract.workout) == readable)
        #expect(try await store.unreadableCount(for: Contract.workout) == 1)
        // A redelivery of that key is skipped, and the legacy row is kept for a version that can read it.
        #expect(try await store.append([legacy]).isEmpty)
        #expect(try await queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM workout_event") } == 3)
        #expect(try await store.uncompactedWorkoutIDs() == [Contract.workout])
        #expect(try await store.highestSeq(for: Contract.workout, device: EventBuilders.watch) == 2)
    }

    @Test("Decided: a settings row written before a Settings field existed loads with that field's default")
    func settingsWithoutANewerField_loadWithItsDefault() async throws {
        let queue = try LedgerDatabase.inMemory()
        let repository = GRDBSettingsRepository(queue, now: { EventBuilders.start })
        var saved = Settings.default
        saved.watchBuzz = false
        saved.units = .kg
        try await repository.save(saved)
        // F28 adds `Settings.iCloudEnabled: Bool`; every stored row then lacks that key. Here the stored row
        // lacks an existing key, which is the same decoding problem.
        try await queue.write { database in
            try database.execute(sql: "UPDATE settings SET payload = json_remove(payload, '$.watchBuzz')")
        }
        var expected = saved
        expected.watchBuzz = Settings.default.watchBuzz
        #expect(try await repository.load() == expected)
        var values = repository.observe().makeAsyncIterator()
        #expect(await values.next() == expected)
    }

    @Test("An append in a task cancelled before it starts stores its whole batch or none of it")
    func appendInCancelledTask_isAllOrNothing() async throws {
        let queue = try LedgerDatabase.inMemory()
        let store = GRDBWorkoutEventStore(queue, now: { EventBuilders.start })
        let batch = (1 ... 50).map { Contract.skip(UInt64($0)) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.append(batch)
        }
        let result = await task.result
        let stored = try await queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM workout_event") }
        switch result {
        case let .success(fresh):
            #expect(fresh == batch && stored == 50)
        case let .failure(error):
            #expect(error is CancellationError && stored == 0, "\(error); \(String(describing: stored)) rows")
        }
    }

    @Test("Appends cancelled while they run store each batch whole or not at all", arguments: [1, 10, 100, 1000])
    func appendsCancelledWhileRunning_areAllOrNothing(_ size: Int) async throws {
        let queue = try LedgerDatabase.inMemory()
        let store = GRDBWorkoutEventStore(queue, now: { EventBuilders.start })
        for round in 0 ..< 10 {
            let batch = (1 ... size).map { Contract.skip(UInt64(round * size + $0)) }
            let task = Task { try await store.append(batch) }
            task.cancel()
            let result = await task.result
            let kept = try await Set(store.envelopes(for: Contract.workout))
            let stored = batch.filter(kept.contains).count
            switch result {
            case .success:
                #expect(stored == size, "round \(round): returned but stored \(stored) of \(size)")
            case .failure:
                #expect(stored == 0, "round \(round): threw but stored \(stored) of \(size)")
            }
        }
    }
}
