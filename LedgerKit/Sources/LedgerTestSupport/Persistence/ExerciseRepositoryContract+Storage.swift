import Foundation
import LedgerDomain

/// What an exercise store refuses at its storage boundary (ADR-007; F07 S1 fix round 1, finding F7-1): a start
/// load no column keeps exactly, saved or seeded. Run by the GRDB repository and LedgerFakes' exercise store.
public extension ExerciseRepositoryContract {
    static let storageClauses: [Clause] = [
        Clause(
            "a start load no column keeps exactly throws inexactWeight, saved or seeded; nothing is stored",
            exactLoads
        )
    ]
}

extension ExerciseRepositoryContract {
    static func exactLoads(_ repository: any ExerciseRepository) async throws -> String? {
        let eighth = Weight.pounds(Decimal(string: "0.125") ?? 0)
        try await repository.save(landmine)
        var pounds = landmine
        pounds.defaultStartLoad = [.lb: eighth, .kg: .kilograms(20)]
        var kilograms = landmine
        kilograms.defaultStartLoad = [.lb: .pounds(45), .kg: Weight(grams: Decimal(string: "0.00000001") ?? 0)]
        // ⅛ lb is 566,990,462.5 units of 10⁻⁷ g, and 10⁻⁸ g a tenth of one: neither is a whole count.
        var catalog = Seeders.catalog(count: 3, version: 1).exercises
        catalog[2].defaultStartLoad = [.lb: eighth]
        let tenth = Decimal(string: "0.00000001") ?? 0
        let saved = await ContractCheck.expectError(RepositoryError.inexactWeight(eighth.grams)) {
            try await repository.save(pounds)
        }
        let savedKilograms = await ContractCheck.expectError(RepositoryError.inexactWeight(tenth)) {
            try await repository.save(kilograms)
        }
        let seeded = await ContractCheck.expectError(RepositoryError.inexactWeight(eighth.grams)) {
            try await repository.seedIfNeeded(catalog, version: 1)
        }
        return try await ContractCheck.first(
            saved.map { "a saved lb load: \($0)" },
            savedKilograms.map { "a saved kg load: \($0)" },
            seeded.map { "a seeded lb load: \($0)" },
            ContractCheck.expect(repository.all(), [landmine], "all() after the refused writes")
        )
    }
}
