import Foundation
import LedgerDomain
import LedgerPersistence

/// Ids and missing programs. Every week, day and slot id is a row id shared by all programs, so an id used twice
/// in one program, or one that another program holds, is refused rather than taking that row over (review B1).
extension ProgramRepositoryContract {
    static func setActiveMissing(_ repository: any ProgramRepository) async throws -> String? {
        let unknown = try program(number: 9).id
        let unsaved = await ContractCheck.expectError(LedgerPersistenceError.missingRow(Self.key("program", unknown))) {
            try await repository.setActive(unknown)
        }
        let deleted = try program(isActive: false)
        try await repository.save(deleted)
        try await repository.delete(deleted.id)
        let afterDelete = await ContractCheck.expectError(
            LedgerPersistenceError.missingRow(Self.key("program", deleted.id))
        ) { try await repository.setActive(deleted.id) }
        let active = try await repository.active()
        return unsaved ?? afterDelete ?? ContractCheck.expect(active, nil, "active() after the refused setActive calls")
    }

    static func duplicateChildren(_ repository: any ProgramRepository) async throws -> String? {
        let program = try program()
        var slotTwice = program
        slotTwice.days[1].slots[0] = program.days[0].slots[0]
        let dayTwice = Self.replacingDay(0, of: program, withID: program.days[1].id)
        var weekTwice = program
        let week = program.weeks[2]
        weekTwice.weeks[2] = Week(id: program.weeks[0].id, index: 2, isDeload: week.isDeload, schedule: week.schedule)
        let cases: [(Program, String)] = [
            (slotTwice, Self.key("slot", program.days[0].slots[0].id)),
            (dayTwice, Self.key("day_template", program.days[1].id)),
            (weekTwice, Self.key("program_week", program.weeks[0].id))
        ]
        for (broken, key) in cases {
            let issue = await ContractCheck.expectError(LedgerPersistenceError.duplicateIdentifier(key)) {
                try await repository.save(broken)
            }
            if let issue {
                return issue
            }
        }
        return try await ContractCheck.expect(repository.active(), nil, "active() after the refused saves")
    }

    static func otherProgramsIDs(_ repository: any ProgramRepository) async throws -> String? {
        let first = try program(number: 1, isActive: true)
        try await repository.save(first)
        let second = try program(number: 2, isActive: false)
        var takesSlot = second
        takesSlot.days[0].slots[0] = first.days[0].slots[0]
        var takesWeek = second
        let week = second.weeks[0]
        takesWeek.weeks[0] = Week(id: first.weeks[0].id, index: 0, isDeload: week.isDeload, schedule: week.schedule)
        let cases: [(Program, String)] = [
            (takesSlot, Self.key("slot", first.days[0].slots[0].id)),
            (Self.replacingDay(0, of: second, withID: first.days[0].id), Self.key("day_template", first.days[0].id)),
            (takesWeek, Self.key("program_week", first.weeks[0].id))
        ]
        for (copy, key) in cases {
            let issue = await ContractCheck.expectError(LedgerPersistenceError.duplicateIdentifier(key)) {
                try await repository.save(copy)
            }
            if let issue {
                return issue
            }
        }
        let afterRefusals = try await repository.active()
        // A deleted program's ids are still its own: saving it again must bring back every row.
        try await repository.delete(first.id)
        let deleted = await ContractCheck.expectError(LedgerPersistenceError.duplicateIdentifier(cases[0].1)) {
            try await repository.save(takesSlot)
        }
        try await repository.save(first)
        let restored = try await repository.active()
        return ContractCheck.expect(afterRefusals, first, "the first program after the refused saves")
            ?? deleted
            ?? ContractCheck.expect(restored, first, "the first program saved again after its delete")
    }

    /// `program` with day `index` given the id `id`, and its weeks scheduling that id in the day's place.
    static func replacingDay(_ index: Int, of program: Program, withID id: DayTemplateID) -> Program {
        var changed = program
        let day = program.days[index]
        changed.days[index] = DayTemplate(id: id, name: day.name, tag: day.tag, slots: day.slots)
        for week in changed.weeks.indices {
            changed.weeks[week].schedule = changed.weeks[week].schedule.mapValues { $0 == day.id ? id : $0 }
        }
        return changed
    }

    /// `LedgerPersistenceError`'s `"table id"`.
    static func key(_ table: String, _ id: some TypedIdentifier) -> String {
        "\(table) \(id.rawValue.uuidString)"
    }
}
