import Foundation
import LedgerDomain

/// Criterion 11 and observation. `all()` is compared as a set where the protocol promises no order.
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
