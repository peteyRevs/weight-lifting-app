import Foundation
import LedgerDomain

/// What a program store refuses at its storage boundary (F07 S1 fix round 1): a weight no column keeps exactly
/// (ADR-007, finding F7-1), and a slot naming an exercise that is not stored (the slot's foreign key; finding
/// F7-3, product decision #28). Run by the GRDB repository and by LedgerFakes' program store linked to an
/// exercise store (`InMemoryStores`), each holding `exercises` and nothing else.
public extension ProgramRepositoryContract {
    static let storageClauses: [Clause] = [
        Clause("a slot start load or step no column keeps exactly throws inexactWeight; nothing is saved", exactLoads),
        Clause("a slot naming an exercise that is not stored throws unknownExercise; nothing is saved", knownExercises)
    ]
}

extension ProgramRepositoryContract {
    static let eighthPound = Weight.pounds(Decimal(string: "0.125") ?? 0)

    static func exactLoads(_ repository: any ProgramRepository) async throws -> String? {
        let program = try program()
        try await repository.save(program)
        var load = program
        load.days[1].slots[2].startLoad = eighthPound
        var step = program
        step.days[2].slots[0].step = eighthPound
        for (what, refused) in [("start load", load), ("step", step)] {
            let issue = await ContractCheck.expectError(RepositoryError.inexactWeight(eighthPound.grams)) {
                try await repository.save(refused)
            }
            if let issue {
                return "a ⅛ lb \(what): \(issue)"
            }
        }
        return try await ContractCheck.expect(repository.active(), program, "active() after the refused saves")
    }

    static func knownExercises(_ repository: any ProgramRepository) async throws -> String? {
        let program = try program()
        try await repository.save(program)
        let unknown = Seeders.catalogID(9999)
        var refused = program
        refused.days[2].slots[1].exerciseID = unknown
        refused.days[3].slots[0].exerciseID = Seeders.catalogID(9998)
        refused.name = "Block 0, never saved"
        let issue = await ContractCheck.expectError(RepositoryError.unknownExercise(key("exercise", unknown))) {
            try await repository.save(refused)
        }
        return try await ContractCheck.first(
            issue.map { "the first slot naming an unknown exercise: \($0)" },
            ContractCheck.expect(repository.active(), program, "active() after the refused save")
        )
    }
}
