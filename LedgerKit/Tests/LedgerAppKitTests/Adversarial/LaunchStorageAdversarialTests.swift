import Dependencies
import Foundation
import GRDB
@testable import LedgerAppKit
import LedgerDependencies
import LedgerDomain
import LedgerFakes
import LedgerPersistence
import Testing

/// F07 S2 adversarial round 1: decisions #28 and #29 and the settings fallback on the iPhone composition, beyond the
/// implementer's cases: a file the process may not read, a directory it may not write, a valid SQLite file that is
/// not Ledger's; programs while the catalog is unseeded; every unreadable settings row across boots; every key
/// bound; and the UI-test database.
@Suite("Adversarial F07 S2 · iPhone launch storage", .timeLimit(.minutes(1)))
struct LaunchStorageAdversarialTests {
    /// The directory listing and every file's bytes, for "untouched".
    static func snapshot(_ directory: URL) throws -> [String: Data] {
        var files: [String: Data] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) {
            let url = directory.appending(path: name)
            files[name] = (try? Data(contentsOf: url)) ?? Data("<unreadable>".utf8)
        }
        return files
    }

    static func setMode(_ mode: Int, _ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path(percentEncoded: false))
    }

    @Test("Decision #29: a file the process may not read is unavailable, untouched, and opens once readable")
    func unreadableFile_isUnavailable_thenRecovers() async throws {
        let harness = Harness()
        defer { harness.remove() }
        try harness.arrange { _ in }
        try Self.setMode(0o000, harness.databaseURL)
        let directory = harness.databaseURL.deletingLastPathComponent()
        let before = try Self.snapshot(directory)
        let composition = harness.booted()
        await composition.resume(in: .active)
        #expect(composition.state == .databaseUnavailable)
        await composition.resume(in: .active)
        #expect(try Self.snapshot(directory) == before)
        try Self.setMode(0o644, harness.databaseURL)
        await composition.resume(in: .active)
        #expect(composition.state == .ready)
        #expect(composition.isCatalogSeeded)
    }

    @Test("Decision #29: a directory the process may not write is unavailable, and no file appears in it")
    func unwritableDirectory_isUnavailable_noFileCreated() async throws {
        let harness = Harness()
        defer {
            try? Self.setMode(0o755, harness.databaseURL.deletingLastPathComponent())
            harness.remove()
        }
        let directory = harness.databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.setMode(0o555, directory)
        let composition = harness.booted()
        await composition.resume(in: .active)
        #expect(composition.state == .databaseUnavailable)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).isEmpty)
        try Self.setMode(0o755, directory)
        await composition.resume(in: .active)
        #expect(composition.state == .ready)
    }

    @Test("Decision #29: a valid SQLite file that is not Ledger's is unavailable, and its bytes stay as they were")
    func foreignDatabase_isUnavailable_andUntouched() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let directory = harness.databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let foreign = try DatabaseQueue(path: harness.databasePath)
        try foreign
            .inDatabase { try $0.execute(sql: "CREATE TABLE exercise (x TEXT); INSERT INTO exercise VALUES ('mine')") }
        try foreign.close()
        let before = try Self.snapshot(directory)
        let composition = harness.booted()
        await composition.resume(in: .active)
        #expect(composition.state == .databaseUnavailable)
        let after = try Self.snapshot(directory)
        #expect(
            after == before,
            "the failed open changed the file: \(before.mapValues(\.count)) → \(after.mapValues(\.count))"
        )
    }

    @Test("Decision #28: while the catalog is unseeded, saving a program naming catalog exercises is refused by name")
    func unseededCatalog_refusesPrograms() async throws {
        let harness = Harness()
        defer { harness.remove() }
        try harness.arrange { database in
            try database
                .execute(sql: "CREATE TRIGGER refuse BEFORE INSERT ON exercise BEGIN SELECT RAISE(ABORT, 'no'); END")
        }
        let composition = harness.booted()
        await composition.resume(in: .active)
        #expect(!composition.isCatalogSeeded)
        let program = try Fixtures.seedProgram()
        let programs = withDependencies { composition.bind(&$0) } operation: {
            @Dependency(\.programRepository) var programs
            return programs
        }
        await #expect(throws: RepositoryError.self) { try await programs.save(program) }
        let active = try await programs.active()
        #expect(active == nil)
    }

    /// Rows a later or damaged writer could leave: a later payload version, a payload that is not UTF-8, invalid
    /// JSON, a version stored as text.
    nonisolated static let unreadableRows: [String] = [
        "INSERT INTO settings VALUES ('singleton', 2, '{\"units\":\"kg\"}', 'then')",
        "INSERT INTO settings VALUES ('singleton', 1, X'FFFE00', 'then')",
        "INSERT INTO settings VALUES ('singleton', 1, '{\"units\":\"stone\"}', 'then')",
        "INSERT INTO settings VALUES ('singleton', 'one', '{}', 'then')"
    ]

    @Test(
        "An unreadable settings row: defaults in memory, and the row byte for byte the same after two more boots",
        arguments: unreadableRows
    )
    func unreadableSettings_untouchedAcrossBoots(sql: String) async throws {
        let harness = Harness("unreadableSettings\(abs(sql.hashValue))")
        defer { harness.remove() }
        try harness.arrange { try $0.execute(sql: sql) }
        let read = { () throws -> [Row] in
            let queue = try DatabaseQueue(path: harness.databasePath)
            defer { try? queue.close() }
            return try queue.read { try Row.fetchAll($0, sql: "SELECT * FROM settings") }
        }
        let before = try read()
        for _ in 0 ..< 3 {
            let composition = harness.booted()
            await composition.resume(in: .active)
            await composition.resume(in: .background)
            await composition.resume(in: .active)
            #expect(composition.settings == .default)
            #expect(composition.state == .ready)
        }
        #expect(try read() == before)
    }

    @Test("After boot every store key and deviceID are bound to the database's, none to a stub or a fake")
    func everyStoreKey_isBound() async {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.booted()
        await composition.resume(in: .active)
        withDependencies { composition.bind(&$0) } operation: {
            @Dependency(\.exerciseRepository) var exercises
            @Dependency(\.programRepository) var programs
            @Dependency(\.workoutRepository) var workouts
            @Dependency(\.workoutEventStore) var events
            @Dependency(\.settingsRepository) var settings
            @Dependency(\.statsQueries) var stats
            @Dependency(\.deviceID) var deviceID
            #expect(exercises is GRDBExerciseRepository)
            #expect(programs is GRDBProgramRepository)
            #expect(workouts is GRDBWorkoutRepository)
            #expect(events is GRDBWorkoutEventStore)
            #expect(settings is GRDBSettingsRepository)
            #expect(stats is GRDBStatsQueries)
            #expect(deviceID.rawValue == Harness.deviceUUID)
        }
    }

    @Test("-LEDGER_UITEST gives every launch a new file in the temporary directory, never the container's database")
    func uiTestArgument_freshTemporaryFile() {
        let first = AppComposition.Environment.live(arguments: ["Ledger", "-LEDGER_UITEST", "1"]).databaseURL
        let second = AppComposition.Environment.live(arguments: ["Ledger", "-LEDGER_UITEST", "1"]).databaseURL
        let plain = AppComposition.Environment.live(arguments: ["Ledger"]).databaseURL
        #expect(first != second)
        #expect(first.path().hasPrefix(URL.temporaryDirectory.path()))
        #expect(first != LedgerStores.defaultURL && plain == LedgerStores.defaultURL)
    }
}
