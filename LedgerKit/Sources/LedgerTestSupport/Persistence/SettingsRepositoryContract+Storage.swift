import Foundation
import LedgerDomain

/// Settings as a store keeps them (F07 S1 fix round 1, finding F7-2): through `SettingsCodec`, so an inventory's
/// plates come back as `PlateInventory`'s decoder normalises them, and a weight with no exact text is refused
/// with `EncodingError`. Run by the GRDB repository and LedgerFakes' settings store.
public extension SettingsRepositoryContract {
    static let storageClauses: [Clause] = [
        Clause("settings load back as their encoding stores them: plates heaviest first, positive, once", normalises),
        Clause("settings holding a NaN weight throw EncodingError; the saved settings stay", refusesNaN)
    ]
}

extension SettingsRepositoryContract {
    static func normalises(_ repository: any SettingsRepository) async throws -> String? {
        var settings = Settings.default
        settings.plateInventory[.lb]?.plates = [.pounds(5), .pounds(45), .pounds(5), .zero]
        try await repository.save(settings)
        let plates = try await repository.load().plateInventory[.lb]?.plates
        return ContractCheck.expect(plates, [.pounds(45), .pounds(5)], "the lb plates read back")
    }

    static func refusesNaN(_ repository: any SettingsRepository) async throws -> String? {
        try await repository.save(custom)
        var settings = custom
        settings.plateInventory[.kg] = PlateInventory(bar: Weight(grams: .nan), plates: [])
        do {
            try await repository.save(settings)
            return "saved settings holding a NaN bar"
        } catch is EncodingError {
            return try await ContractCheck.expect(repository.load(), custom, "load() after the refused save")
        }
    }
}
