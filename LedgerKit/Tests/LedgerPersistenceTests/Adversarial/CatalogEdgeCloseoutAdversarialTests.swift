import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S2 close-out round, decision #24's edges: lower and equal versions, alternatives naming exercises that
/// are not stored, an inexact entry in a refresh, a row the catalog stops listing and lists again, and a
/// damaged catalog row that an upgrade repairs.
@Suite("Adversarial S2 close-out · catalog refresh edges", .tags(.persistence), .timeLimit(.minutes(1)))
struct CatalogEdgeCloseoutAdversarialTests {
    static let catalog = CatalogRefreshCloseoutAdversarialTests.catalog

    @Test("A lower or equal version changes no byte, even when its entries differ")
    func lowerOrEqualVersion_changesNothing() async throws {
        let kit = try S2CatalogKit()
        try await kit.exercises.seedIfNeeded(Self.catalog, version: 1)
        try await kit.exercises.seedIfNeeded(Self.catalog + [S2Kit.exercise(104, "Dip")], version: 3)
        let before = try await kit.dump()
        let different = Self.catalog.map { entry in
            var copy = entry
            copy.shortName = "X"
            return copy
        } + [S2Kit.exercise(105, "Curl")]
        for version in [3, 2, 1, 0, -1, Int.min] {
            kit.clock.advance()
            try await kit.exercises.seedIfNeeded(different, version: version)
            #expect(try await kit.dump() == before, "version \(version)")
        }
    }

    @Test("Refreshed alternatives naming exercises that are not stored are kept as given, and the row reads")
    func danglingAlternatives_refreshAndRead() async throws {
        let kit = try S2CatalogKit()
        try await kit.exercises.seedIfNeeded(Self.catalog, version: 1)
        var changed = Self.catalog
        changed[2].curatedAlternatives = [S2Kit.exerciseID(999), S2Kit.exerciseID(100), S2Kit.exerciseID(999)]
        try await kit.exercises.seedIfNeeded(changed, version: 2)
        #expect(try await kit.exercise(102) == changed[2])
        #expect(try await kit.exercises.all().contains(changed[2]))
        #expect(try await kit.exercises.search("romanian", equipment: nil, muscle: nil) == [changed[2]])
    }

    @Test("An upgrade with one inexact entry refreshes nothing and leaves the version unapplied; the fix then applies")
    func inexactEntry_refreshesNothing() async throws {
        let kit = try S2CatalogKit()
        try await kit.exercises.seedIfNeeded(Self.catalog, version: 1)
        let before = try await kit.dump()
        var changed = Self.catalog
        changed[0].name = "Squat (v2)"
        changed[3].defaultStartLoad = [.lb: Weight(grams: Decimal(string: "0.000000001") ?? 0)]
        kit.clock.advance()
        await #expect(throws: LedgerPersistenceError.self) {
            try await kit.exercises.seedIfNeeded(changed, version: 2)
        }
        #expect(try await kit.dump() == before)
        changed[3] = Self.catalog[3]
        try await kit.exercises.seedIfNeeded(changed, version: 2)
        #expect(try await kit.exercise(100)?.name == "Squat (v2)")
        #expect(try await kit.meta(103).first == 2.databaseValue)
    }

    @Test("A row the catalog stops listing keeps its version, and is refreshed when a later catalog lists it again")
    func unlistedThenRelisted_isRefreshedLater() async throws {
        let kit = try S2CatalogKit()
        try await kit.exercises.seedIfNeeded(Self.catalog, version: 1)
        try await kit.exercises.seedIfNeeded(Array(Self.catalog.prefix(2)), version: 2)
        #expect(try await kit.meta(103).first == 1.databaseValue)
        var relisted = Self.catalog
        relisted[3].shortName = "Chin"
        try await kit.exercises.seedIfNeeded(relisted, version: 5)
        #expect(try await kit.exercise(103)?.shortName == "Chin")
        #expect(try await kit.meta(103).first == 5.databaseValue)
        let settled = try await kit.dump()
        for _ in 0 ..< 3 {
            kit.clock.advance()
            try await kit.exercises.seedIfNeeded(relisted, version: 5)
        }
        #expect(try await kit.dump() == settled)
    }

    @Test("A damaged catalog row the catalog lists is repaired by the next upgrade, even with no content change")
    func damagedCatalogRow_isRepairedByUpgrade() async throws {
        let kit = try S2CatalogKit()
        try await kit.exercises.seedIfNeeded(Self.catalog, version: 1)
        try await S2Kit.damage(kit.queue, "UPDATE exercise SET equipment = 'hovercraft' WHERE id = ?", [
            ColumnCodec.text(S2Kit.exerciseID(101))
        ])
        #expect(try await kit.exercises.all().count == 3)
        try await kit.exercises.seedIfNeeded(Self.catalog, version: 2)
        #expect(try await kit.exercises.all() == ExerciseSearch.sorted(Self.catalog))
    }
}
