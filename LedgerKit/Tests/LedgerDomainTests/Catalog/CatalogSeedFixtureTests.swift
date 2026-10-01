import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// Criterion 8: the fixture F05's `seedIfNeeded` contract test uses. The contract test itself lives
/// in F05; this suite only proves the fixture sets up the cases it claims to.
@Suite("CatalogSeedFixture", .tags(.domain))
struct CatalogSeedFixtureTests {
    @Test("Criterion 8: upgrade() is base() plus two new entries, one version higher")
    func upgrade_isAdditive() throws {
        let base = try CatalogSeedFixture.base()
        let upgrade = try CatalogSeedFixture.upgrade()
        #expect(base.version == ExerciseCatalog.version)
        #expect(try base.exercises == (ExerciseCatalog.seed()))
        #expect(upgrade.version == base.version + 1)
        #expect(upgrade.exercises == base.exercises + [CatalogSeedFixture.added, CatalogSeedFixture.clash])
        let ids = Set(base.exercises.map(\.id))
        #expect(!ids.contains(CatalogSeedFixture.added.id))
        #expect(!ids.contains(CatalogSeedFixture.clash.id))
        #expect(!ids.contains(CatalogSeedFixture.custom.id))
    }

    @Test("Criterion 8: custom is the lifter's; only clash shares its name, and only when case is ignored")
    func custom_clashesOnlyWithClash() throws {
        let custom = CatalogSeedFixture.custom
        let clash = CatalogSeedFixture.clash
        let baseNames = try Set(CatalogSeedFixture.base().exercises.map { $0.name.lowercased() })
        #expect(custom.isCustom)
        #expect(!clash.isCustom && !CatalogSeedFixture.added.isCustom)
        #expect(!baseNames.contains(custom.name.lowercased()))
        #expect(!baseNames.contains(CatalogSeedFixture.added.name.lowercased()))
        #expect(clash.name != custom.name)
        #expect(clash.name.lowercased() == custom.name.lowercased())
    }
}
