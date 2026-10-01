import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// `GRDBExerciseRepository`: the shared contract (search per product decision #23, criterion 11's seeding,
/// observation), then how it lays exercises out in `exercise`.
@Suite("GRDBExerciseRepository", .tags(.persistence), .timeLimit(.minutes(1)))
struct ExerciseRepositoryTests {
    typealias Contract = ExerciseRepositoryContract

    @Test("The GRDB repository keeps the contract clause", arguments: ExerciseRepositoryContract.clauses)
    func contract_clauseHolds(_ clause: ExerciseRepositoryContract.Clause) async throws {
        let issue = try await clause.check(Repositories().exercises)
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }

    @Test("A saved exercise is one row: exact loads, JSON arrays as text, no catalog version; stamped on change")
    func save_writesTheDocumentedColumns() async throws {
        let repositories = try Repositories()
        var exercise = Contract.landmine
        exercise.defaultStartLoad = [.lb: .pounds(Decimal(string: "47.25") ?? 0), .kg: .kilograms(20)]
        exercise.curatedAlternatives = [Seeders.catalogID(1)]
        try await repositories.exercises.save(exercise)
        let created = repositories.clock.timestamp
        let columns = """
        SELECT quote(start_load_lb_e7g) || ' ' || quote(start_load_kg_e7g) || ' ' || is_custom || ' '
            || quote(catalog_version) || ' ' || typeof(secondary_muscles) || ' ' || secondary_muscles || ' '
            || curated_alternatives || ' ' || created_at || ' ' || updated_at || ' ' || quote(deleted_at)
        FROM exercise
        """
        let alternative = Seeders.catalogID(1).rawValue.uuidString
        #expect(try await repositories.texts(columns) == [
            "214322394825 200000000000 1 NULL text [\"triceps\",\"shoulders\"] [\"\(alternative)\"] "
                + "\(created) \(created) NULL"
        ])
        // Saved again unchanged, the row is left alone (review N1: M4's last-writer-wins sync reads updated_at).
        repositories.clock.advance()
        try await repositories.exercises.save(exercise)
        let stamps = "SELECT created_at || ' ' || updated_at FROM exercise"
        #expect(try await repositories.texts(stamps) == ["\(created) \(created)"])
        exercise.shortName = "Landmine (edited)"
        try await repositories.exercises.save(exercise)
        #expect(try await repositories.texts(stamps) == ["\(created) \(repositories.clock.timestamp)"])
    }

    @Test("An inexact start load is refused by name; a seed rolls back the entries before it")
    func inexactStartLoad_isRefused() async throws {
        let repositories = try Repositories()
        var exercise = Contract.landmine
        let eighth = Weight.pounds(Decimal(string: "0.125") ?? 0)
        exercise.defaultStartLoad = [.lb: eighth]
        await #expect(throws: LedgerPersistenceError.inexactWeight(eighth.grams)) {
            try await repositories.exercises.save(exercise)
        }
        var catalog = Seeders.catalog(count: 4, version: 1).exercises
        catalog[2].defaultStartLoad = [.lb: eighth]
        await #expect(throws: LedgerPersistenceError.inexactWeight(eighth.grams)) {
            try await repositories.exercises.seedIfNeeded(catalog, version: 1)
        }
        #expect(try await repositories.count("SELECT COUNT(*) FROM exercise") == 0)
    }

    @Test("A deleted exercise is never returned, and saving it again brings it back")
    func deletedRow_isHidden_untilSavedAgain() async throws {
        let repositories = try Repositories()
        let exercises = repositories.exercises
        try await exercises.save(Contract.landmine)
        try await repositories.execute("UPDATE exercise SET deleted_at = 'then'")
        #expect(try await exercises.all().isEmpty)
        #expect(try await exercises.search("land", equipment: nil, muscle: nil).isEmpty)
        #expect(try await exercises.exercise(id: Contract.landmine.id) == nil)
        try await exercises.save(Contract.landmine)
        #expect(try await exercises.all() == [Contract.landmine])
    }

    @Test("Seeding writes catalog rows with their version, whatever an entry's isCustom says")
    func seed_writesCatalogRows_withTheirVersion() async throws {
        let repositories = try Repositories()
        var catalog = Seeders.catalog(count: 3, version: 4).exercises
        catalog[1].isCustom = true
        try await repositories.exercises.save(Contract.landmine)
        try await repositories.exercises.seedIfNeeded(catalog, version: 4)
        let rows = "SELECT name || ' ' || is_custom || ' ' || quote(catalog_version) FROM exercise ORDER BY name"
        #expect(try await repositories.texts(rows) == [
            "Catalog barbell horizontalPush 0 0 4",
            "Catalog cable verticalPush 2 0 4",
            "Catalog dumbbell horizontalPull 1 0 4",
            "Landmine Press 1 NULL"
        ])
    }

    @Test("An upgrade records its version on every catalog row it lists, even when it adds nothing")
    func upgrade_recordsItsVersion_evenWhenItAddsNothing() async throws {
        let repositories = try Repositories()
        let exercises = repositories.exercises
        try await exercises.seedIfNeeded(Seeders.catalog(count: 3, version: 1).exercises, version: 1)
        let fewer = Array(Seeders.catalog(count: 3, version: 2).exercises.prefix(2))
        repositories.clock.advance()
        try await exercises.seedIfNeeded(fewer, version: 2)
        let versions = "SELECT catalog_version FROM exercise ORDER BY id"
        #expect(try await repositories.texts(versions) == ["2", "2", "1"])
        // The entries version 2 lists are refreshed with no change, so no updated_at moves; the entry it dropped
        // stays as it was.
        #expect(try await Set(exercises.all()) == Set(Seeders.catalog(count: 3, version: 1).exercises))
        let stamps = "SELECT DISTINCT updated_at FROM exercise"
        #expect(try await repositories.texts(stamps) == [ColumnCodec.timestamp(EventBuilders.start)])
    }

    @Test("A stored id is never seeded again, even when that exercise was deleted")
    func seed_neverRevivesADeletedCatalogRow() async throws {
        let repositories = try Repositories()
        let exercises = repositories.exercises
        try await exercises.seedIfNeeded(Seeders.catalog(count: 2, version: 1).exercises, version: 1)
        try await repositories.execute("UPDATE exercise SET deleted_at = 'then' WHERE id = ?", [
            ColumnCodec.text(Seeders.catalogID(0))
        ])
        try await exercises.seedIfNeeded(Seeders.catalog(count: 3, version: 2).exercises, version: 2)
        #expect(try await Set(exercises.all().map(\.id)) == [Seeders.catalogID(1), Seeders.catalogID(2)])
        #expect(try await repositories.count("SELECT COUNT(*) FROM exercise") == 3)
    }

    @Test("Seeding 214 entries stores them all, with one insert and one version mark each")
    func seed_214Entries_storesThemAll() async throws {
        let repositories = try Repositories()
        let catalog = Seeders.catalog(count: 214, version: 1)
        let commits = try await repositories.queue.write { database in database.totalChangesCount }
        try await repositories.exercises.seedIfNeeded(catalog.exercises, version: catalog.version)
        #expect(try await Set(repositories.exercises.all()) == Set(catalog.exercises))
        let after = try await repositories.queue.write { database in database.totalChangesCount }
        #expect(after - commits == 2 * 214) // an insert and a version mark per entry, and nothing else
    }
}
