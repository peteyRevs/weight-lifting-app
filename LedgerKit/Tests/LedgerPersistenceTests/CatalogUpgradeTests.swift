import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// Product decision #24 (Pete, 2026-09-30): a catalog upgrade refreshes the live catalog rows it lists in place,
/// and never touches a custom exercise, a catalog exercise the lifter saved, or a deleted row. The contract
/// clauses `seedRefresh`, `seedLeavesTheLifters` and `seedBundledCatalog` (F03 criterion 8) hold the
/// behaviour; these tests hold the columns.
@Suite("GRDBExerciseRepository · catalog upgrades", .tags(.persistence), .timeLimit(.minutes(1)))
struct CatalogUpgradeTests {
    @Test("A lifter's save of a catalog exercise clears its catalog version, changed or not, and stamps no change")
    func save_ofACatalogExercise_clearsItsVersion() async throws {
        let repositories = try Repositories()
        try await repositories.exercises.seedIfNeeded(Seeders.catalog(count: 2, version: 1).exercises, version: 1)
        repositories.clock.advance()
        try await repositories.exercises.save(Seeders.catalogEntry(0))
        let rows = "SELECT quote(catalog_version) || ' ' || updated_at FROM exercise ORDER BY id"
        let seeded = ColumnCodec.timestamp(EventBuilders.start)
        #expect(try await repositories.texts(rows) == ["NULL \(seeded)", "1 \(seeded)"])
    }

    @Test("An upgrade refreshes a listed catalog row in place: id and created_at kept, updated_at only on change")
    func upgrade_refreshesListedCatalogRows_inPlace() async throws {
        let repositories = try Repositories()
        let first = Seeders.catalog(count: 3, version: 1).exercises
        try await repositories.exercises.seedIfNeeded(first, version: 1)
        let seeded = repositories.clock.timestamp
        repositories.clock.advance()
        var corrected = first[0]
        corrected.defaultStartLoad = [.kg: .kilograms(60)]
        corrected.secondaryMuscles = [.core]
        // Version 2: entry 0 corrected, entry 1 as it was, entry 2 no longer listed, entry 3 new.
        try await repositories.exercises.seedIfNeeded([corrected, first[1], Seeders.catalogEntry(3)], version: 2)
        let upgraded = repositories.clock.timestamp
        let rows = """
        SELECT id || ' ' || created_at || ' ' || updated_at || ' ' || catalog_version || ' ' || start_load_kg_e7g
        FROM exercise ORDER BY id
        """
        let ids = (0 ..< 4).map { Seeders.catalogID($0).rawValue.uuidString }
        #expect(try await repositories.texts(rows) == [
            "\(ids[0]) \(seeded) \(upgraded) 2 600000000000", // 60 kg, corrected from 0 kg
            "\(ids[1]) \(seeded) \(seeded) 2 25000000000", // 2.5 kg, as it was
            "\(ids[2]) \(seeded) \(seeded) 1 50000000000", // not listed
            "\(ids[3]) \(upgraded) \(upgraded) 2 75000000000" // new
        ])
        #expect(try await repositories.exercises.exercise(id: corrected.id) == corrected)
    }

    @Test("An upgrade leaves a deleted catalog row as it was: its content, its version and its deletion")
    func upgrade_leavesADeletedCatalogRow() async throws {
        let repositories = try Repositories()
        try await repositories.exercises.seedIfNeeded(Seeders.catalog(count: 2, version: 1).exercises, version: 1)
        let id = ColumnCodec.text(Seeders.catalogID(0))
        try await repositories.execute("UPDATE exercise SET deleted_at = 'then' WHERE id = ?", [id])
        let row = "SELECT * FROM exercise WHERE id = ?"
        let before = try await repositories.queue.read { try Row.fetchOne($0, sql: row, arguments: [id])?.description }
        var corrected = Seeders.catalogEntry(0)
        corrected.name = "Corrected"
        try await repositories.exercises.seedIfNeeded([corrected, Seeders.catalogEntry(1)], version: 2)
        let after = try await repositories.queue.read { try Row.fetchOne($0, sql: row, arguments: [id])?.description }
        #expect(after == before && before != nil)
        #expect(try await repositories.texts("SELECT catalog_version FROM exercise ORDER BY id") == ["1", "2"])
    }

    @Test("F03 criterion 8 on the bundled catalog: one row per entry; the upgrade stamps only its new rows")
    func bundledCatalog_upgradeStampsOnlyNewRows() async throws {
        let repositories = try Repositories()
        let base = try CatalogSeedFixture.base()
        let upgrade = try CatalogSeedFixture.upgrade()
        try await repositories.exercises.seedIfNeeded(base.exercises, version: base.version)
        let seeded = repositories.clock.timestamp
        repositories.clock.advance()
        try await repositories.exercises.save(CatalogSeedFixture.custom)
        let customRow = { @Sendable (database: Database) in
            try Row.fetchOne(
                database,
                sql: "SELECT * FROM exercise WHERE id = ?",
                arguments: [ColumnCodec.text(CatalogSeedFixture.custom.id)]
            )?.description
        }
        let saved = try await repositories.queue.read(customRow)
        repositories.clock.advance()
        try await repositories.exercises.seedIfNeeded(base.exercises, version: base.version)
        repositories.clock.advance()
        try await repositories.exercises.seedIfNeeded(upgrade.exercises, version: upgrade.version)
        let upgraded = repositories.clock.timestamp
        let after = try await repositories.queue.read(customRow)
        let rows = """
        SELECT created_at || ' ' || updated_at || ' ' || catalog_version, COUNT(*) FROM exercise
        WHERE is_custom = 0 GROUP BY 1 ORDER BY 1
        """
        let groups = try await repositories.queue.read { database in
            try Row.fetchAll(database, sql: rows).map { "\($0[0] as String) × \($0[1] as Int)" }
        }
        #expect(base.exercises.count == 224)
        #expect(groups == [
            "\(seeded) \(seeded) \(upgrade.version) × 224", // refreshed, unchanged: only the version moves
            "\(upgraded) \(upgraded) \(upgrade.version) × 2" // added and clash
        ])
        #expect(after == saved && saved != nil, "the custom exercise's row, byte for byte")
    }

    @Test("Seeding writes rows in the catalog's order, the same on every launch (review N-c)")
    func seed_writesInCatalogOrder() async throws {
        let repositories = try Repositories()
        let base = try CatalogSeedFixture.base()
        let inserts = try await repositories.statements(startingWith: "INSERT INTO exercise") {
            try await repositories.exercises.seedIfNeeded(base.exercises, version: base.version)
        }
        #expect(inserts.count == base.exercises.count)
        let order = try await repositories.texts("SELECT id FROM exercise ORDER BY rowid")
        #expect(order == base.exercises.map { ColumnCodec.text($0.id) })
    }
}
