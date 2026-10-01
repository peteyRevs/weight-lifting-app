import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S3 adversarial round 1, criterion 12: is `Fixtures/db-v001.sqlite` really a v001 database as
/// `Migrations.swift` makes one, and does its data survive migrations harsher than the implementer's additive
/// `v002`? Every test works on a copy: the committed file is never opened for writing.
@Suite("Adversarial S3 · the v001 fixture", .tags(.persistence), .timeLimit(.minutes(1)))
struct MigrationFixtureAdversarialTests {
    static func copy(in directory: TemporaryDirectory) throws -> DatabaseQueue {
        let fixture = try #require(Bundle.module.url(
            forResource: "db-v001",
            withExtension: "sqlite",
            subdirectory: "Fixtures"
        ))
        try FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
        let copy = directory.file("fixture.sqlite")
        try FileManager.default.copyItem(at: fixture, to: copy)
        return try DatabaseQueue(path: copy.path(percentEncoded: false))
    }

    /// Everything SQLite knows of a schema: each object of `sqlite_master` with its `CREATE` text, and each
    /// table's columns, foreign keys and indexes as the pragmas report them.
    static func schema(_ database: Database) throws -> [String] {
        var lines = try Row.fetchAll(database, sql: "SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY name")
            .map(\.description)
        let tables = try String.fetchAll(
            database,
            sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
        )
        for table in tables {
            for pragma in ["table_xinfo", "foreign_key_list", "index_list"] {
                lines += try Row.fetchAll(database, sql: "PRAGMA \(pragma)(\(table))")
                    .map { "\(table) \(pragma): \($0)" }
            }
        }
        return lines
    }

    /// Every row of every table, as text.
    static func rows(_ database: Database) throws -> [String] {
        let tables = try String.fetchAll(database, sql: """
        SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'grdb%' ORDER BY name
        """)
        return try tables.flatMap { table in
            try Row.fetchAll(database, sql: "SELECT * FROM \(table) ORDER BY rowid").map { "\(table): \($0)" }
        }
    }

    @Test("The fixture's schema is what the migrator builds today: every object, column, key and index, and no more")
    func fixtureSchema_equalsAFreshDatabase() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only
        let fixture = try Self.copy(in: directory)
        let fresh = try LedgerDatabase.inMemory()
        let stored = try await fixture.read { try Self.schema($0) }
        let built = try await fresh.read { try Self.schema($0) }
        #expect(stored == built)
        #expect(stored.count > 100)
        let header = try await fixture.read { database in
            try ["user_version", "application_id", "auto_vacuum", "freelist_count"].map { pragma in
                try "\(pragma) \(Int.fetchOne(database, sql: "PRAGMA \(pragma)") ?? -1)"
            }
        }
        #expect(header == ["user_version 0", "application_id 0", "auto_vacuum 0", "freelist_count 0"])
    }

    @Test("Migrating the fixture with today's migrator, and opening it as the app does, changes no row")
    func migratingTheFixture_changesNoRow() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only
        let fixture = try Self.copy(in: directory)
        let before = try await fixture.read { try Self.rows($0) }
        #expect(try await fixture.read { try LedgerDatabase.migrator.hasCompletedMigrations($0) })
        try LedgerDatabase.migrator.migrate(fixture)
        #expect(try await fixture.read { try Self.rows($0) } == before)
        try fixture.close()
        let opened = try LedgerDatabase.open(at: directory.file("fixture.sqlite"))
        #expect(try await opened.read { try Self.rows($0) } == before)
        #expect(try await opened.read { try String.fetchOne($0, sql: "PRAGMA journal_mode") } == "wal")
    }

    @Test("Every stored estimate and total of the fixture is what today's code computes from its rows")
    func fixtureValues_areConsistent() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only
        let fixture = try Self.copy(in: directory)
        let sets = try await fixture.read { database in
            try Row.fetchAll(database, sql: "SELECT weight_e7g, reps, done_at, e1rm_e7g FROM logged_set").map { row in
                (
                    weight: row["weight_e7g"] as Int64,
                    reps: row["reps"] as Int,
                    tick: row["done_at"] as Double?,
                    estimate: row["e1rm_e7g"] as Int64?
                )
            }
        }
        #expect(sets.count == 57)
        for set in sets {
            let estimate = try OneRepMax.brzycki(weight: Weight(e7g: set.weight), reps: Reps(clamping: set.reps))?.e7g()
            #expect(set.estimate == (set.tick == nil ? nil : estimate), "\(set)")
        }
        let live = try await GRDBWorkoutRepository(fixture).recent(limit: 100)
        let totals = try await fixture.read { database in
            try String.fetchAll(database, sql: """
            SELECT id || ' ' || volume_e7g_reps || ' ' || done_sets || ' ' || total_sets || ' ' ||
                (pr_count = (SELECT COUNT(*) FROM personal_record WHERE workout_id = workout.id AND deleted_at IS NULL))
            FROM workout WHERE deleted_at IS NULL ORDER BY ended_at DESC
            """)
        }
        #expect(live.count == 2)
        #expect(try totals == live.map { workout in
            let id = workout.id.rawValue.uuidString
            return try "\(id) \(workout.volume.e7gReps()) \(workout.doneSets) \(workout.totalSets) 1"
        })
        // The deleted workout's rows are all deleted with it: nothing live hangs under a deleted parent.
        let orphans = try await fixture.read { database in
            try Int.fetchOne(database, sql: """
            SELECT (SELECT COUNT(*) FROM workout_exercise JOIN workout ON workout.id = workout_id
                    WHERE workout.deleted_at IS NOT NULL AND workout_exercise.deleted_at IS NULL)
                 + (SELECT COUNT(*) FROM logged_set JOIN workout_exercise ON workout_exercise.id = workout_exercise_id
                    WHERE workout_exercise.deleted_at IS NOT NULL AND logged_set.deleted_at IS NULL)
            """)
        }
        #expect(orphans == 0)
    }

    @Test("A fixture workout materialised again through today's code writes no row: the rows are in today's shape")
    func fixtureWorkouts_rematerialiseAsNoOps() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only
        let fixture = try Self.copy(in: directory)
        let workouts = GRDBWorkoutRepository(fixture)
        let before = try await fixture.read { try Self.rows($0) }
        for workout in try await workouts.recent(limit: 100) {
            let records = try await GRDBStatsQueries(fixture)
                .personalRecords(exerciseID: MigrationCompatibilityTests.bench)
                .filter { $0.workoutID == workout.id }
            let summary = WorkoutEngine.summary(workout, prs: records)
            try await workouts.materialize(workout, summary: summary, prs: records, slotUpdates: [])
        }
        let after = try await fixture.read { try Self.rows($0) }
        #expect(after == before, "\(zip(after, before).first { $0 != $1 }.map { "\($0)" } ?? "")")
    }
}

extension MigrationFixtureAdversarialTests {
    /// A migration that rebuilds two synced tables the way SQLite's documentation prescribes (new table, copy,
    /// drop, rename) and drops an index. With foreign keys left on, dropping `workout` would cascade through
    /// its exercises, sets, records and health row.
    static var migratorWithARebuild: DatabaseMigrator {
        var migrator = LedgerDatabase.migrator
        migrator.registerMigration("v002_rebuildTestOnly") { database in
            try database.execute(sql: """
            CREATE TABLE workout_new AS SELECT * FROM workout;
            DROP TABLE workout;
            CREATE TABLE workout (
                id TEXT PRIMARY KEY NOT NULL, program_id TEXT, week_index INTEGER, day_template_id TEXT,
                name TEXT NOT NULL, tag TEXT NOT NULL, is_deload INTEGER NOT NULL DEFAULT 0, started_at REAL NOT NULL,
                ended_at REAL, phase TEXT NOT NULL, units TEXT NOT NULL, volume_e7g_reps INTEGER NOT NULL,
                done_sets INTEGER NOT NULL, total_sets INTEGER NOT NULL, pr_count INTEGER NOT NULL DEFAULT 0,
                origin_device TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT,
                rating INTEGER
            );
            INSERT INTO workout SELECT *, NULL FROM workout_new;
            DROP TABLE workout_new;
            CREATE INDEX idx_workout_ended ON workout(ended_at);
            DROP INDEX idx_pr_exercise;
            ALTER TABLE logged_set RENAME COLUMN position TO place;
            ALTER TABLE logged_set RENAME COLUMN place TO position;
            """)
        }
        return migrator
    }

    @Test("A migration that rebuilds the workout table keeps every row of every table, and the history reads the same")
    func tableRebuild_keepsEveryRow() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only
        let fixture = try Self.copy(in: directory)
        let before = try await fixture.read { try Self.rows($0).filter { !$0.hasPrefix("workout:") } }
        let history = try await GRDBWorkoutRepository(fixture).recent(limit: 100)
        let volume = try await GRDBStatsQueries(fixture).weeklyVolume(in: .distantPast ..< .distantFuture)
        try Self.migratorWithARebuild.migrate(fixture)
        #expect(try await fixture.read { try Self.rows($0).filter { !$0.hasPrefix("workout:") } } == before)
        #expect(try await fixture.read { try Row.fetchAll($0, sql: "PRAGMA foreign_key_check").count } == 0)
        #expect(try await fixture.read { try String.fetchAll($0, sql: "PRAGMA integrity_check") } == ["ok"])
        #expect(try await GRDBWorkoutRepository(fixture).recent(limit: 100) == history)
        #expect(try await GRDBStatsQueries(fixture).weeklyVolume(in: .distantPast ..< .distantFuture) == volume)
        #expect(try await fixture.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM workout") } == 3)
    }
}
