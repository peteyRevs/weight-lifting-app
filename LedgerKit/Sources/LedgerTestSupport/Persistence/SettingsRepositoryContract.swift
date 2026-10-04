import Foundation
import LedgerDomain

/// `SettingsRepository`'s contract as named clauses (F07): the defaults before the first save, a save that
/// replaces the one value whole, and observation that emits each change once. Every implementation runs the
/// same clauses: `GRDBSettingsRepository` and `InMemorySettingsRepository`, each in `LedgerPersistenceTests`.
/// What only a database can do (a row it cannot read, a later payload version) stays with the GRDB suite.
public enum SettingsRepositoryContract {
    public typealias Clause = ContractClause<any SettingsRepository>

    public static let clauses: [Clause] = [
        Clause("before the first save, load returns Settings.default", loadsDefaults),
        Clause(
            "saved settings load back equal, every field and exact plate weights; a second save replaces them",
            saves
        ),
        Clause("observe emits the settings now, then each change, and no save that changes nothing", observe)
    ]

    /// Every field away from `Settings.default`, with inventories that need exact weights.
    public static let custom = Settings(
        units: .kg,
        defaultRest: RestDuration(seconds: 120) ?? .defaultRest,
        plateMathEnabled: false,
        autoRest: false,
        watchBuzz: false,
        weekStart: .sunday,
        plateInventory: [
            .kg: PlateInventory(bar: .kilograms(15), plates: [.kilograms(25), .kilograms(0.5)]),
            .lb: PlateInventory(bar: .pounds(35), plates: [.pounds(45), .pounds(1.25)])
        ]
    )

    static func loadsDefaults(_ repository: any SettingsRepository) async throws -> String? {
        try await ContractCheck.expect(repository.load(), .default, "load() before any save")
    }

    static func saves(_ repository: any SettingsRepository) async throws -> String? {
        try await repository.save(custom)
        let first = try await repository.load()
        var changed = custom
        changed.units = .lb
        changed.plateInventory = [.lb: .standard(.lb)]
        try await repository.save(changed)
        let second = try await repository.load()
        return ContractCheck.expect(first, custom, "load() after a save")
            ?? ContractCheck.expect(second, changed, "load() after a second save")
    }

    static func observe(_ repository: any SettingsRepository) async throws -> String? {
        var values = repository.observe().makeAsyncIterator()
        let initial = await values.next()
        try await repository.save(custom)
        let saved = await values.next()
        try await repository.save(custom) // changes nothing: no value
        var changed = custom
        changed.weekStart = .monday
        try await repository.save(changed)
        let next = await values.next()
        return ContractCheck.expect(initial, .default, "the first value")
            ?? ContractCheck.expect(saved, custom, "the value after a save")
            ?? ContractCheck.expect(next, changed, "the value after an unchanged save, then a change")
    }
}
