import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// `GRDBCompanionStore` (F19 S3a): the contract, then what only the database can do: rows it cannot read, the
/// columns it writes, v003 over a v002 database with data, the erase, and `LocalDevice.recordPeer`.
@Suite("GRDBCompanionStore", .tags(.persistence), .timeLimit(.minutes(1)))
struct CompanionStoreTests {
    static let now = CompanionStoreContract.now

    static func store() throws -> (GRDBCompanionStore, DatabaseQueue) {
        let queue = try LedgerDatabase.inMemory()
        return (GRDBCompanionStore(queue, now: { now }), queue)
    }

    @Test("The GRDB store keeps the contract clause", arguments: CompanionStoreContract.clauses)
    func contract_clauseHolds(_ clause: CompanionStoreContract.Clause) async throws {
        let issue = try await clause.check(Self.store().0)
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test("A finished log is one row: the record's codec bytes, its device and HealthKit UUID, dates in seconds")
    func finishedLog_columns() async throws {
        let (store, queue) = try Self.store()
        let record = CompanionStoreContract.record(1)
        try await store.saveFinishedLog(record, createdAt: Self.now)
        try await store.markEnqueued([record.workoutID], at: Self.now.addingTimeInterval(2))
        let (payload, ids, dates) = try await queue.read { database in
            let row = try Row.fetchOne(database, sql: "SELECT * FROM finished_log")
            let ids: [String?] = [row?["workout_id"], row?["device_id"], row?["health_uuid"]]
            let dates: [Double?] = [row?["created_at"], row?["enqueued_at"], row?["acked_at"]]
            return (row?["payload"] as Data?, ids, dates)
        }
        #expect(try payload == CompanionCodec.encode(record))
        let expected = [record.workoutID.rawValue, EventBuilders.watch.rawValue, EventBuilders.uuid(0xBEEF)]
        #expect(ids == expected.map(\.uuidString))
        #expect(dates == [Self.now.timeIntervalSinceReferenceDate, Self.now.timeIntervalSinceReferenceDate + 2, nil])
    }

    @Test("A finished log it cannot read is left out of the list and stays stored; the rest are listed")
    func unreadableLog_isLeftOut() async throws {
        let (store, queue) = try Self.store()
        try await store.saveFinishedLog(CompanionStoreContract.record(1), createdAt: Self.now)
        try await store.saveFinishedLog(CompanionStoreContract.record(2), createdAt: Self.now)
        let later = Data([CompanionCodec.magic, CompanionCodec.version + 1]) + Data("{}".utf8)
        try await queue.write { database in
            try database.execute(
                sql: "UPDATE finished_log SET payload = ? WHERE workout_id = ?",
                arguments: [later, CompanionStoreContract.record(1).workoutID.rawValue.uuidString]
            )
        }
        let listed = try await store.unacknowledgedLogs().map(\.record.workoutID)
        #expect(listed == [CompanionStoreContract.record(2).workoutID])
        #expect(try await queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM finished_log") } == 2)
    }

    @Test("The state is one stamped row; one it cannot read throws rather than reading as empty")
    func unreadableState_throws() async throws {
        let (store, queue) = try Self.store()
        try await store.saveState(.empty)
        try await store.saveState(CompanionState(context: nil, programFileSHA256: Data([1])))
        let rows = try await queue.read { try String.fetchAll($0, sql: "SELECT id || updated_at FROM companion_state") }
        #expect(rows == ["singleton" + ColumnCodec.timestamp(Self.now)])
        try await queue.write { database in
            try database.execute(sql: "UPDATE companion_state SET program_sha256 = 42")
        }
        await #expect(throws: LedgerPersistenceError.malformedColumn("companion_state.program_sha256")) {
            try await store.state()
        }
        try await queue.write { database in
            try database.execute(sql: "UPDATE companion_state SET program_sha256 = NULL, context = x'4302'")
        }
        await #expect(throws: CompanionCodecError.unsupportedVersion(2)) { try await store.state() }
    }

    @Test("A last-performance row of the wrong kind throws malformedColumn")
    func damagedLastPerformance_throws() async throws {
        let (store, queue) = try Self.store()
        try await queue.write { database in
            try database.execute(sql: """
            INSERT INTO companion_last_performance (exercise_id, date, sets, reps, load_e7g)
            VALUES ('00000000-0000-0000-0000-000000000001', 1.5, 5, 5, 1.5)
            """)
        }
        await #expect(throws: LedgerPersistenceError.malformedColumn("companion_last_performance.load_e7g")) {
            try await store.lastPerformance()
        }
    }
}

/// `LocalDevice.recordPeer` (F19 S3a): the paired device's row.
extension CompanionStoreTests {
    static let peer = DeviceID(EventBuilders.uuid(0xF002))

    @Test("recordPeer inserts the peer once, of its kind; this device stays the oldest of its own kind")
    func recordPeer_insertsOnce() throws {
        let queue = try LedgerDatabase.inMemory()
        let phone = try LocalDevice.id(in: queue, kind: .phone, now: Self.now, newID: { EventBuilders.uuid(0xF001) })
        try LocalDevice.recordPeer(Self.peer, kind: .watch, in: queue, now: Self.now.addingTimeInterval(60))
        try LocalDevice.recordPeer(Self.peer, kind: .phone, in: queue, now: Self.now.addingTimeInterval(120))
        try LocalDevice.recordPeer(phone, kind: .watch, in: queue, now: Self.now.addingTimeInterval(180))
        let rows = try queue.read { try Row.fetchAll($0, sql: "SELECT id, kind, name FROM device ORDER BY created_at") }
        #expect(rows.map { $0["kind"] as String } == ["phone", "watch"])
        #expect(rows.last?["id"] == Self.peer.rawValue.uuidString)
        #expect(rows.last?["name"] == "Apple Watch")
        let again = try LocalDevice.id(in: queue, kind: .phone, now: Self.now, newID: { EventBuilders.uuid(9) })
        #expect(again == phone)
    }
}

/// v003 is additive: a v002 database with data migrates, keeps every row, and takes companion writes.
extension CompanionStoreTests {
    @Test("v003 on a v002 database with data keeps every row and adds three empty tables that take writes")
    func v003_onAV002DatabaseWithData() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let queue = try DatabaseQueue(
            path: MigrationCompatibilityTests.fixtureCopy(in: directory).path(percentEncoded: false)
        )
        try LedgerDatabase.migrator.migrate(queue, upTo: "v002_workoutStartedIndex")
        try LedgerDatabase.migrator.migrate(queue)
        let (applied, orphans, added) = try await queue.read { database in
            try (
                LedgerDatabase.migrator.appliedIdentifiers(database),
                Row.fetchAll(database, sql: "PRAGMA foreign_key_check").count,
                Int.fetchOne(database, sql: """
                SELECT (SELECT COUNT(*) FROM finished_log) + (SELECT COUNT(*) FROM companion_state)
                    + (SELECT COUNT(*) FROM companion_last_performance)
                """)
            )
        }
        #expect(applied.contains("v003_companionSync") && orphans == 0 && added == 0)
        // Every v002 row is there and reads back (`SchemaTests` pins that v003 only adds tables and an index).
        let keepsEveryRow = try await MigrationCompatibilityTests.rowCounts(in: queue)
            == MigrationCompatibilityTests.rowCounts
        #expect(keepsEveryRow)
        let store = GRDBCompanionStore(queue, now: { Self.now })
        try await store.saveFinishedLog(CompanionStoreContract.record(1), createdAt: Self.now)
        #expect(try await store.unacknowledgedLogs()
            .map(\.record.workoutID) == [CompanionStoreContract.record(1).workoutID])
        try await MigrationCompatibilityTests.expectTheFixturesData(in: queue)
    }
}
