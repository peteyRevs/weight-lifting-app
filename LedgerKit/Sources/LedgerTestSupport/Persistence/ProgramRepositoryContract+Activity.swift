import Foundation
import LedgerDomain

/// The one active program, deletion and observation.
extension ProgramRepositoryContract {
    static func oneActive(_ repository: any ProgramRepository) async throws -> String? {
        let first = try program(number: 1, isActive: true)
        let second = try program(number: 2, isActive: false)
        try await repository.save(first)
        try await repository.save(second)
        let afterSaves = try await repository.active()
        try await repository.setActive(second.id)
        let afterSetActive = try await repository.active()
        var firstAgain = first
        firstAgain.name = "Block 1, again"
        try await repository.save(firstAgain)
        let afterSavingActive = try await repository.active()
        var secondActive = second
        secondActive.isActive = true
        return ContractCheck.expect(afterSaves, first, "active() after saving an inactive second program")
            ?? ContractCheck.expect(afterSetActive, secondActive, "active() after setActive(second)")
            ?? ContractCheck.expect(afterSavingActive, firstAgain, "active() after saving the first as active")
    }

    static func deleteHides(_ repository: any ProgramRepository) async throws -> String? {
        let program = try program()
        try await repository.save(program)
        try await repository.delete(program.id)
        let afterDelete = try await repository.active()
        try await repository.delete(program.id) // a second delete does nothing
        try await repository.save(program)
        let afterSave = try await repository.active()
        return ContractCheck.expect(afterDelete, nil, "active() after delete")
            ?? ContractCheck.expect(afterSave, program, "active() after saving it again")
    }

    static func observeActive(_ repository: any ProgramRepository) async throws -> String? {
        let program = try program()
        let edited = try edited(program)
        var values = repository.observeActive().makeAsyncIterator()
        let initial = await values.next()
        try await repository.save(program)
        let saved = await values.next()
        try await repository.save(edited)
        let changed = await values.next()
        try await repository.delete(program.id)
        let deleted = await values.next()
        return ContractCheck.expect(initial, .some(nil), "the first value")
            ?? ContractCheck.expect(saved, .some(program), "the value after a save")
            ?? ContractCheck.expect(changed, .some(edited), "the value after an edit")
            ?? ContractCheck.expect(deleted, .some(nil), "the value after delete")
    }
}
