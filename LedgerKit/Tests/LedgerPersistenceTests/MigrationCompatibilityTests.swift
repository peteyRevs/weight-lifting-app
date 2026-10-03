import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// Criterion 12: a database created at schema v001, with data, survives later migrations.
///
/// `Fixtures/db-v001.sqlite` is a database file that v001's code wrote (F05 S3), through the repositories: a
/// seeded catalog and a custom exercise, an active program and a deleted one, three finished workouts (one
/// with personal records and edited sets, one deleted), settings, an uncompacted event log (the 13 payload
/// version 1 envelopes of `PayloadV1`), and a `workout_health` and a `device` row. Databases in that shape
/// exist on lifters' devices.
///
/// **Never regenerate or edit the fixture.** Every later migration `vNNN` adds a fixture of its own
/// (`db-vNNN.sqlite`, written by that version) and is tested here from every earlier one. The values this
/// suite expects are written out, not taken from `Seeders`, so a change to a seeder cannot move them.
@Suite("Migration compatibility", .tags(.persistence), .timeLimit(.minutes(1)))
struct MigrationCompatibilityTests {
    static let bench = ExerciseID(EventBuilders.uuid(0x0CA0_0000))
    static let landmine = ExerciseID(EventBuilders.uuid(0x0E00_001A))
    static let edited = WorkoutID(EventBuilders.uuid(0x0D00_0001))
    /// 2026-09-16T05:20:00Z, when the fixture's newest live workout ended.
    static let ended = Date(timeIntervalSinceReferenceDate: 811_228_800)

    /// Rows per table, soft-deleted ones included, in the fixture.
    static let rowCounts = [
        "exercise": 7, "program": 2, "program_week": 16, "day_template": 8, "slot": 40, "slot_miss": 33,
        "workout": 3, "workout_exercise": 15, "logged_set": 57, "personal_record": 2, "workout_health": 1,
        "workout_event": 13, "settings": 1, "device": 1
    ]

    /// A migration no released version has: additive, as every migration must be (ADR-002). It adds a
    /// column to a synced table, a table with a foreign key to one, and an index.
    static var migratorWithV003: DatabaseMigrator {
        var migrator = LedgerDatabase.migrator
        migrator.registerMigration("v003_testOnly") { database in
            try database.execute(sql: """
            ALTER TABLE workout ADD COLUMN notes TEXT;
            CREATE TABLE workout_photo (
                id TEXT PRIMARY KEY NOT NULL,
                workout_id TEXT NOT NULL REFERENCES workout(id) ON DELETE CASCADE,
                created_at TEXT NOT NULL
            );
            CREATE INDEX idx_workout_photo_workout ON workout_photo(workout_id);
            """)
        }
        return migrator
    }

    /// A writable copy of the committed fixture, in `directory`.
    static func fixtureCopy(in directory: TemporaryDirectory) throws -> URL {
        let fixture = try #require(Bundle.module.url(
            forResource: "db-v001",
            withExtension: "sqlite",
            subdirectory: "Fixtures"
        ))
        try FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
        let copy = directory.file("ledger.sqlite")
        try FileManager.default.copyItem(at: fixture, to: copy)
        return copy
    }

    static func rowCounts(in queue: DatabaseQueue) async throws -> [String: Int] {
        try await queue.read { database in
            var counts: [String: Int] = [:]
            for table in rowCounts.keys {
                counts[table] = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM \(table)")
            }
            return counts
        }
    }

    @Test("The fixture is a sound database at exactly v001, with the committed schema")
    func fixture_isAtV001() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let queue = try DatabaseQueue(path: Self.fixtureCopy(in: directory).path(percentEncoded: false))
        let (applied, schema, integrity, orphans) = try await queue.read { database in
            try (
                LedgerDatabase.migrator.appliedIdentifiers(database),
                SchemaTests.dump(database),
                String.fetchAll(database, sql: "PRAGMA integrity_check"),
                Row.fetchAll(database, sql: "PRAGMA foreign_key_check").count
            )
        }
        #expect(applied == ["v001_createSchema"])
        let committed = try #require(Bundle.module.url(
            forResource: "schema-v001",
            withExtension: "sql",
            subdirectory: "Fixtures"
        ))
        #expect(try schema == String(contentsOf: committed, encoding: .utf8))
        #expect(integrity == ["ok"])
        #expect(orphans == 0)
        #expect(try await Self.rowCounts(in: queue) == Self.rowCounts)
    }

    @Test("Criterion 12: migrating the v001 fixture to a later schema keeps every row, and it reads back")
    func v003_keepsTheData() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let queue = try DatabaseQueue(path: Self.fixtureCopy(in: directory).path(percentEncoded: false))
        try Self.migratorWithV003.migrate(queue)
        let (applied, orphans, notes) = try await queue.read { database in
            try (
                Self.migratorWithV003.appliedIdentifiers(database),
                Row.fetchAll(database, sql: "PRAGMA foreign_key_check").count,
                String.fetchAll(database, sql: "SELECT quote(notes) FROM workout")
            )
        }
        // Through the real v002 (product decision #26's index), then the test-only v003.
        #expect(applied == ["v001_createSchema", "v002_workoutStartedIndex", "v003_testOnly"])
        #expect(orphans == 0)
        #expect(notes == ["NULL", "NULL", "NULL"])
        #expect(try await Self.rowCounts(in: queue) == Self.rowCounts)
        try await Self.expectTheFixturesData(in: queue)
        // The migrated database takes writes: to the new column and table, and through the repositories.
        try await queue.write { database in
            try database.execute(sql: "UPDATE workout SET notes = 'felt strong' WHERE id = ?", arguments: [
                ColumnCodec.text(Self.edited)
            ])
            try database.execute(
                sql: "INSERT INTO workout_photo (id, workout_id, created_at) VALUES ('P', ?, 'now')",
                arguments: [ColumnCodec.text(Self.edited)]
            )
        }
        try await Self.expectTheFixturesData(in: queue)
    }

    @Test("The app's own open migrates a copy of the fixture, reads it, and writes to it")
    func open_readsAndWritesTheFixture() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let queue = try LedgerDatabase.open(at: Self.fixtureCopy(in: directory))
        try await Self.expectTheFixturesData(in: queue)
        let workouts = GRDBWorkoutRepository(queue, now: { Self.ended })
        let stored = try #require(try await workouts.workout(id: Self.edited))
        let added = Seeders.workout(number: 7, endedAt: Self.ended.addingTimeInterval(86400), [
            Seeders.ExerciseLog(ProgramRepositoryContract.exercises[0], [.init(190, 5)])
        ])
        let stores = HistoryStores(
            workouts: workouts,
            stats: GRDBStatsQueries(queue, now: { Self.ended }),
            programs: GRDBProgramRepository(queue, now: { Self.ended })
        )
        try await stores.materialize(added)
        try await stores.materialize(stored) // a stored workout materialised again changes nothing
        #expect(try await workouts.recent(limit: 2) == [added, stored])
        #expect(try await stores.stats.lastPerformance(exerciseID: Self.bench)?.load == .pounds(190))
    }
}

/// What the fixture holds, read through the repositories and the stats queries.
extension MigrationCompatibilityTests {
    static func expectTheFixturesData(in queue: DatabaseQueue) async throws {
        let program = try await expectTheProgram(in: queue)
        try await expectTheHistory(in: queue, of: program)
        try await expectTheLocalRows(in: queue)
    }

    /// The catalog, the custom exercise, the settings and the active program.
    static func expectTheProgram(in queue: DatabaseQueue) async throws -> Program {
        let now: @Sendable () -> Date = { ended }
        let exercises = try await GRDBExerciseRepository(queue, now: now).all()
        #expect(exercises.count == 7)
        #expect(exercises.first { $0.id == landmine }?.name == "Landmine Press")
        #expect(exercises.first { $0.id == bench }?.defaultStartLoad[.kg] == .zero)
        let settings = try await GRDBSettingsRepository(queue, now: now).load()
        #expect(settings.units == .kg && settings.weekStart == .monday && settings.defaultRest.seconds == 90)
        let program = try #require(try await GRDBProgramRepository(queue, now: now).active())
        #expect(program.name == "Block 0" && program.startDate.description == "2026-08-17")
        #expect(program.weeks.count == 8 && program.days.map(\.slots.count) == [5, 5, 5, 5])
        #expect(program.days[0].slots[0].misses == [3])
        #expect(program.days.flatMap(\.slots).map(\.misses.count).reduce(0, +) == 17)
        #expect(program.days[1].slots[1].startLoad == .kilograms(21))
        return program
    }

    /// The two live workouts, newest first, and the stats over them.
    static func expectTheHistory(in queue: DatabaseQueue, of program: Program) async throws {
        let now: @Sendable () -> Date = { ended }
        let workouts = try await GRDBWorkoutRepository(queue, now: now).recent(limit: 10)
        #expect(workouts.map(\.name) == ["Workout 1 — Seeded", "Workout 0 — Seeded"])
        #expect(workouts.map(\.doneSets) == [17, 18] && workouts.map(\.totalSets) == [18, 19])
        #expect(workouts[0].endedAt == ended && workouts[0].units == .lb && workouts[0].source == nil)
        #expect(workouts[1].source?.weekIndex == 3 && workouts[1].source?.programID == program.id)
        #expect(workouts[0].exercises[1].sets.map(\.weight) == [.kilograms(27.5), .pounds(55), .pounds(55)])
        #expect(workouts[0].exercises[4].sets[0].weight == .kilograms(12.5))

        let stats = GRDBStatsQueries(queue, now: now)
        #expect(try await stats.bestE1RM(exerciseID: bench) == Weight(grams: 94404))
        // The Last line's date is the workout's start, an hour before its end (product decision #26).
        #expect(try await stats.lastPerformance(exerciseID: bench) == LastPerformance(
            date: ended.addingTimeInterval(-3600),
            sets: 5,
            reps: 5,
            load: .pounds(185)
        ))
        let volume = try await stats.weeklyVolume(in: .distantPast ..< .distantFuture)
        #expect(volume == Volume(gramReps: Decimal(string: "11593702.221") ?? 0))
        let records = try await stats.personalRecords(exerciseID: bench)
        #expect(records.map(\.kind) == [
            .estimatedOneRepMax(Weight(grams: 94404)), .weightAtReps(.pounds(185), Reps(clamping: 5))
        ])
        #expect(records.map(\.previous) == [
            .estimatedOneRepMax(Weight(grams: 91853)), .weightAtReps(.pounds(180), Reps(clamping: 5))
        ])
    }

    /// The tables that never sync: the event log, `workout_health` and `device`.
    static func expectTheLocalRows(in queue: DatabaseQueue) async throws {
        let store = GRDBWorkoutEventStore(queue, now: { ended })
        #expect(try await store.uncompactedWorkoutIDs() == [PayloadV1.workout])
        #expect(try await store.envelopes(for: PayloadV1.workout).count == 13)
        #expect(try await store.unreadableCount(for: PayloadV1.workout) == 0)
        let local = try await queue.read { database in
            try String.fetchAll(database, sql: """
            SELECT avg_heart_rate || ' ' || max_heart_rate || ' ' || active_energy_kcal FROM workout_health
            UNION ALL SELECT kind || ' ' || name FROM device
            """)
        }
        #expect(local == ["128 171 412.5", "phone Pete's iPhone"])
    }
}
