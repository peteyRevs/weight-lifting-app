import Foundation
import LedgerDomain

/// Criterion 11, product decision #24, F03 criterion 8 and observation. `all()` is compared as a set where the
/// clause is not about order.
extension ExerciseRepositoryContract {
    static func seedIdempotent(_ repository: any ExerciseRepository) async throws -> String? {
        let catalog = Seeders.catalog(count: 5, version: 1)
        try await repository.save(landmine)
        try await repository.seedIfNeeded(catalog.exercises, version: catalog.version)
        let first = try await Set(repository.all())
        try await repository.seedIfNeeded(catalog.exercises, version: catalog.version)
        let second = try await Set(repository.all())
        let custom = try await repository.exercise(id: landmine.id)
        return ContractCheck.expect(first, Set(catalog.exercises + [landmine]), "all() after seeding once")
            ?? ContractCheck.expect(second, first, "all() after seeding the same version again")
            ?? ContractCheck.expect(custom, landmine, "the custom exercise")
    }

    static func seedUpgrade(_ repository: any ExerciseRepository) async throws -> String? {
        let first = Seeders.catalog(count: 5, version: 1)
        let second = Seeders.catalog(count: 8, version: 2)
        try await repository.save(landmine)
        try await repository.seedIfNeeded(first.exercises, version: first.version)
        try await repository.seedIfNeeded(second.exercises, version: second.version)
        let upgraded = try await Set(repository.all())
        let added = try await repository.exercise(id: Seeders.catalogID(7))
        // An older app's catalog, or a catalog relabelled lower, adds nothing.
        try await repository.seedIfNeeded(Seeders.catalog(count: 12, version: 1).exercises, version: 1)
        try await repository.seedIfNeeded(Seeders.catalog(count: 12, version: 2).exercises, version: 2)
        let after = try await Set(repository.all())
        return ContractCheck.expect(upgraded, Set(second.exercises + [landmine]), "all() after the upgrade")
            ?? ContractCheck.expect(added, Seeders.catalogEntry(7), "a new entry by id")
            ?? ContractCheck.expect(after, upgraded, "all() after seeding versions 1 and 2 again")
    }

    static func seedNameClash(_ repository: any ExerciseRepository) async throws -> String? {
        let catalog = Seeders.catalog(count: 3, version: 1)
        // The lifter's own exercise, named like catalog entry 1 in another case.
        let mine = custom(0x2B, catalog.exercises[1].name.uppercased(), "Mine", .band, .core)
        try await repository.save(mine)
        try await repository.seedIfNeeded(catalog.exercises, version: catalog.version)
        let all = try await Set(repository.all())
        let entry = try await repository.exercise(id: catalog.exercises[1].id)
        let kept = try await repository.exercise(id: mine.id)
        return ContractCheck.expect(all, Set(catalog.exercises + [mine]), "all() after seeding")
            ?? ContractCheck.expect(entry, catalog.exercises[1], "the catalog entry by id")
            ?? ContractCheck.expect(kept, mine, "the custom exercise")
    }

    static func seedCatalogRows(_ repository: any ExerciseRepository) async throws -> String? {
        var catalog = Seeders.catalog(count: 2, version: 1).exercises
        catalog[1].isCustom = true
        try await repository.seedIfNeeded(catalog, version: 1)
        var expected = catalog[1]
        expected.isCustom = false
        return try await ContractCheck.expect(repository.exercise(id: expected.id), expected, "an entry marked custom")
    }

    static func seedRefresh(_ repository: any ExerciseRepository) async throws -> String? {
        let first = Seeders.catalog(count: 3, version: 1).exercises
        try await repository.seedIfNeeded(first, version: 1)
        // Version 2 corrects entry 0, lists entry 1 as it was, and no longer lists entry 2.
        var corrected = first[0]
        corrected.name += " (corrected)"
        corrected.defaultStartLoad = [.lb: .pounds(135)]
        corrected.curatedAlternatives = [Seeders.catalogID(2)]
        try await repository.seedIfNeeded([corrected, first[1]], version: 2)
        let upgraded = try await Set(repository.all())
        // The same version again, with other content, changes nothing.
        var ignored = corrected
        ignored.name = "Ignored"
        try await repository.seedIfNeeded([ignored], version: 2)
        let again = try await repository.exercise(id: corrected.id)
        return ContractCheck.expect(upgraded, [corrected, first[1], first[2]], "all() after the upgrade")
            ?? ContractCheck.expect(again, corrected, "entry 0 after seeding version 2 again")
    }

    static func seedLeavesTheLifters(_ repository: any ExerciseRepository) async throws -> String? {
        // The lifter's own exercise, holding the id of entry 2, which version 2 adds.
        var mine = Seeders.catalogEntry(2)
        mine.name = "Mine"
        mine.isCustom = true
        try await repository.save(mine)
        let first = Seeders.catalog(count: 2, version: 1).exercises
        try await repository.seedIfNeeded(first, version: 1)
        var edited = first[0]
        edited.name = "My Row"
        try await repository.save(edited)
        let second = Seeders.catalog(count: 3, version: 2).exercises.map { entry in
            var changed = entry
            changed.name += " v2"
            return changed
        }
        try await repository.seedIfNeeded(second, version: 2)
        let custom = try await repository.exercise(id: mine.id)
        let saved = try await repository.exercise(id: edited.id)
        let refreshed = try await repository.exercise(id: second[1].id)
        return ContractCheck.expect(custom, mine, "the custom exercise")
            ?? ContractCheck.expect(saved, edited, "the catalog exercise the lifter saved")
            ?? ContractCheck.expect(refreshed, second[1], "a catalog exercise the upgrade lists")
    }

    /// F03 criterion 8's scenario, as `CatalogSeedFixture` documents it, over the real bundled catalog.
    static func seedBundledCatalog(_ repository: any ExerciseRepository) async throws -> String? {
        let base = try CatalogSeedFixture.base()
        let upgrade = try CatalogSeedFixture.upgrade()
        try await repository.seedIfNeeded(base.exercises, version: base.version)
        let seeded = try await repository.all()
        try await repository.save(CatalogSeedFixture.custom)
        try await repository.seedIfNeeded(base.exercises, version: base.version)
        let reseeded = try await Set(repository.all())
        try await repository.seedIfNeeded(upgrade.exercises, version: upgrade.version)
        let upgraded = try await Set(repository.all())
        let clash = try await repository.exercise(id: CatalogSeedFixture.clash.id)
        let custom = try await repository.exercise(id: CatalogSeedFixture.custom.id)
        return ContractCheck.expect(seeded.count, base.exercises.count, "one exercise per entry after seeding")
            ?? ContractCheck.expect(Set(seeded), Set(base.exercises), "all() after seeding")
            ?? ContractCheck.expect(
                reseeded,
                Set(base.exercises + [CatalogSeedFixture.custom]),
                "all() after seeding the same version again"
            )
            ?? ContractCheck.expect(
                upgraded,
                Set(upgrade.exercises + [CatalogSeedFixture.custom]),
                "all() after the upgrade"
            )
            ?? ContractCheck.expect(clash, CatalogSeedFixture.clash, "the entry named like the custom exercise")
            ?? ContractCheck.expect(custom, CatalogSeedFixture.custom, "the custom exercise after the upgrade")
    }

    static func observeAll(_ repository: any ExerciseRepository) async throws -> String? {
        var values = repository.observeAll().makeAsyncIterator()
        let initial = await values.next()
        try await repository.save(landmine)
        let saved = await values.next()
        let catalog = Seeders.catalog(count: 2, version: 1)
        try await repository.seedIfNeeded(catalog.exercises, version: catalog.version)
        let seeded = await values.next().map(Set.init)
        return ContractCheck.expect(initial, [], "the first value")
            ?? ContractCheck.expect(saved, [landmine], "the value after a save")
            ?? ContractCheck.expect(seeded, Set(catalog.exercises + [landmine]), "the value after seeding")
    }
}
