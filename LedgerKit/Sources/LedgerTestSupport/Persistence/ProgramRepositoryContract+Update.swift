import Foundation
import LedgerDomain
import Synchronization

/// `ProgramRepository.update` (F11 S3 criteria 1 to 6 and 8): the change is applied to the program as stored at
/// that moment and saved as `save` saves it, or nothing is written. What an update and a workout's save do to
/// each other is in `WorkoutRepositoryContract.linkedClauses`, which has both stores.
///
/// A clause that fails says what differs in a line (`brief(_:)`, `Program.difference(from:)`), never a whole
/// program: a failure's text goes into the result bundle for every case.
extension ProgramRepositoryContract {
    static let updateClauses: [Clause] = [
        Clause("update applies its change to the program as stored now, and returns it as stored", updateApplies),
        Clause(
            "update of a program that is not stored, or is deleted, throws missingRow and never calls its change",
            updateMissing
        ),
        Clause("a change that throws is rethrown as it is; nothing is written", updateRethrows),
        Clause(
            "a result save would refuse is refused by update with save's error, and one under another id with "
                + "duplicateIdentifier; nothing is written",
            updateRefuses
        ),
        Clause(
            "an update leaves which program is active alone; a change of isActive is saved as save saves it",
            updateKeepsActivity
        ),
        Clause(
            "observeActive emits the program after an update that changes it, and nothing after one that changes "
                + "nothing, throws or is refused",
            updateObserved
        ),
        Clause(
            "update on a task that is already cancelled throws CancellationError, never calls its change and "
                + "writes nothing",
            updateCancelledBefore
        ),
        Clause(
            "a task cancelled inside the change stores all of the change or none of it, and throws only for none",
            updateCancelledInside
        )
    ]

    /// What a change throws in these clauses.
    struct ChangeFailure: Error, Equatable {
        let code: Int
    }

    /// How often a change was called.
    final class Tally: Sendable {
        private let calls = Mutex(0)

        var count: Int {
            calls.withLock { $0 }
        }

        func add() {
            calls.withLock { $0 += 1 }
        }
    }

    /// A program in a line: its name, whether it is active, its weeks (`d` for a deload), and how many days,
    /// slots and misses it has.
    static func brief(_ program: Program) -> String {
        let slots = program.days.flatMap(\.slots)
        let weeks = program.weeks.map { $0.isDeload ? "d" : "w" }.joined()
        let misses = slots.reduce(0) { $0 + $1.misses.count }
        return "\"\(program.name.prefix(40))\", \(program.isActive ? "active" : "inactive"), weeks \(weeks), "
            + "\(program.days.count) days, \(slots.count) slots, \(misses) misses"
    }

    /// `nil` when `actual` is `expected`, else what differs, in a line.
    static func same(_ actual: Program?, _ expected: Program?, _ what: String) -> String? {
        guard actual != expected else {
            return nil
        }
        guard let actual, let expected else {
            return "\(what): got \(actual.map(brief) ?? "no program"), expected \(expected.map(brief) ?? "none")"
        }
        let slots = actual.difference(from: expected) ?? ""
        return "\(what): got \(brief(actual)), expected \(brief(expected)); \(slots)"
    }

    /// What `body` threw, with its type, or `nil` when it returned.
    static func refusal(of body: () async throws -> Void) async -> String? {
        do {
            try await body()
            return nil
        } catch {
            return String(String(reflecting: error).prefix(200))
        }
    }

    /// `program` with " (renamed)" added to its name: a change that touches one row.
    static func renamed(_ program: Program) -> Program {
        var changed = program
        changed.name += " (renamed)"
        return changed
    }

    /// `program` under the id `id`, everything else as it is.
    static func moved(_ program: Program, to id: ProgramID) throws -> Program {
        try Program(
            id: id,
            name: program.name,
            startDate: program.startDate,
            weeks: program.weeks,
            days: program.days,
            goal: program.goal,
            daysPerWeek: program.daysPerWeek,
            isActive: program.isActive
        )
    }

    // MARK: Clauses

    static func updateApplies(_ repository: any ProgramRepository) async throws -> String? {
        let program = try program()
        try await repository.save(program)
        let expected = try edited(program)
        let returned = try await repository.update(program.id) { try edited($0) }
        let afterEdit = try await repository.active()
        // The next change meets the edit, not the program first saved. Its weeks come back in index order.
        let again = try await repository.update(program.id) { stored in
            var changed = renamed(stored)
            changed.weeks.reverse()
            return changed
        }
        let afterRename = try await repository.active()
        // A program saved whole in between is what the next change meets.
        try await repository.save(program)
        let afterSave = try await repository.update(program.id, renamed)
        return try await ContractCheck.first(
            same(returned, expected, "what the first update returned"),
            same(afterEdit, expected, "active() after the first update"),
            same(again, renamed(expected), "what the second update returned"),
            same(afterRename, renamed(expected), "active() after the second update"),
            same(afterSave, renamed(program), "what an update after a whole save returned"),
            same(repository.active(), renamed(program), "active() after it")
        )
    }

    static func updateMissing(_ repository: any ProgramRepository) async throws -> String? {
        let calls = Tally()
        let change: @Sendable (Program) -> Program = { stored in
            calls.add()
            return renamed(stored)
        }
        let kept = try program(number: 1, isActive: true)
        let deleted = try program(number: 2, isActive: false)
        let unknown = try program(number: 9).id
        try await repository.save(kept)
        try await repository.save(deleted)
        try await repository.delete(deleted.id)
        let unsaved = await ContractCheck.expectError(RepositoryError.missingRow(key("program", unknown))) {
            _ = try await repository.update(unknown, change)
        }
        let afterDelete = await ContractCheck.expectError(RepositoryError.missingRow(key("program", deleted.id))) {
            _ = try await repository.update(deleted.id, change)
        }
        let active = try await repository.active()
        // Saved again, the deleted program is what was saved: the refused update left nothing behind.
        var revived = deleted
        revived.isActive = true
        try await repository.save(revived)
        return try await ContractCheck.first(
            unsaved.map { "a program that is not stored: \($0)" },
            afterDelete.map { "a deleted program: \($0)" },
            ContractCheck.expect(calls.count, 0, "the calls of the change"),
            same(active, kept, "active() after the refused updates"),
            same(repository.active(), revived, "the deleted program, saved again")
        )
    }

    static func updateRethrows(_ repository: any ProgramRepository) async throws -> String? {
        let program = try program()
        try await repository.save(program)
        let thrown = await ContractCheck.expectError(ChangeFailure(code: 7)) {
            _ = try await repository.update(program.id) { _ in throw ChangeFailure(code: 7) }
        }
        return try await ContractCheck.first(
            thrown,
            same(repository.active(), program, "active() after the change threw")
        )
    }

    /// Results `save` refuses, each as a change returns it: for a re-validation, for text, and for ids.
    static func refusedResults(holding other: Program) -> [(String, @Sendable (Program) -> Program)] {
        [
            ("a slot out of range", { stored in
                var result = stored
                result.days[1].slots[2].sets = 99
                return result
            }),
            ("one week", { stored in
                var result = stored
                result.weeks = [stored.weeks[0]]
                return result
            }),
            ("a name holding U+0000", { stored in
                var result = stored
                result.name += "\u{0}"
                return result
            }),
            ("a slot twice", { stored in
                var result = stored
                result.days[1].slots[0] = stored.days[0].slots[0]
                return result
            }),
            ("a slot another program holds", { stored in
                var result = stored
                result.days[0].slots[0] = other.days[0].slots[0]
                return result
            }),
            ("a day another program holds", { replacingDay(0, of: $0, withID: other.days[0].id) })
        ]
    }

    static func updateRefuses(_ repository: any ProgramRepository) async throws -> String? {
        let program = try program()
        let other = try Self.program(number: 1, isActive: false)
        try await repository.save(program)
        try await repository.save(other)
        for (what, result) in refusedResults(holding: other) {
            // `save` refuses the result, and writes nothing; `update` must throw the very same.
            let bySave = await refusal { try await repository.save(result(program)) }
            let byUpdate = await refusal { _ = try await repository.update(program.id, result) }
            guard let bySave, bySave == byUpdate else {
                return "\(what): save threw \(bySave ?? "nothing"), update threw \(byUpdate ?? "nothing")"
            }
        }
        // Another id, whether a stored program holds it or none does: this program's rows would go under it.
        for stranger in try [other.id, Self.program(number: 9).id] {
            let issue = await ContractCheck.expectError(RepositoryError.duplicateIdentifier(key("program", stranger))) {
                _ = try await repository.update(program.id) { try moved($0, to: stranger) }
            }
            if let issue {
                return "a result under another id: \(issue)"
            }
        }
        let afterRefusals = try await repository.active()
        try await repository.setActive(other.id)
        var otherActive = other
        otherActive.isActive = true
        return try await ContractCheck.first(
            same(afterRefusals, program, "active() after the refused updates"),
            same(repository.active(), otherActive, "the other program after them")
        )
    }
}
