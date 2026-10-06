import Foundation
import LedgerDomain
import LedgerPersistence

/// `ProgramRepository`'s contract as named clauses (F05): criterion 2's round trip, saves that replace a
/// program's weeks, days, slots and misses, re-validation through `Slot.init` and `Program.init` (F02 review
/// N2), text holding U+0000 (refused, review N-a), the one active program, deletion, observation, and ids
/// (review B1), and then `update`'s clauses (F11 S3, `updateClauses`). Every clause gets a fresh, empty
/// repository that accepts slots naming `exercises` (a GRDB database must hold them first: `slot.exercise_id`
/// is a foreign key).
public enum ProgramRepositoryContract {
    public typealias Clause = ContractClause<any ProgramRepository>

    public static let clauses: [Clause] = [
        Clause("a saved active program reads back equal, misses included (8 weeks × 4 days)", roundTrip),
        Clause("a second save replaces days, slots and misses: removed, added and changed", saveReplaces),
        Clause("save re-validates: a slot or program edited out of range throws and changes nothing", revalidates),
        Clause("a program or day name, or a day tag, holding U+0000 throws nulInText; nothing is saved", refusesNul),
        Clause("exactly one program is active: setActive, or saving an active one, deactivates the other", oneActive),
        Clause("delete hides the program, and saving it again brings it back", deleteHides),
        Clause("observeActive emits the active program now, then after each change", observeActive),
        Clause("setActive of a program that is not saved, or is deleted, throws missingRow", setActiveMissing),
        Clause("two weeks, days or slots sharing an id throw duplicateIdentifier; nothing is saved", duplicateChildren),
        Clause(
            "a week, day or slot id another program holds, even deleted or dropped, is refused; it is unchanged",
            otherProgramsIDs
        )
    ] + updateClauses

    /// The exercises the contract's programs name.
    public static let exercises = Seeders.catalog(count: 6, version: 1).exercises

    /// Criterion 2's program: 8 weeks × 4 days of 5 slots, with misses.
    public static func program(number: Int = 0, isActive: Bool = true) throws -> Program {
        try Seeders.program(number: number, exercises: exercises.map(\.id), isActive: isActive)
    }

    /// `program` edited everywhere a save must diff: its last day removed (and unscheduled), a slot added to
    /// day 0, day 1's first slot rebuilt with other sets and misses, a miss added and one cleared, a day
    /// renamed, a week turned into a deload, and the name and goal changed.
    public static func edited(_ program: Program) throws -> Program {
        var edited = program
        let removed = edited.days.removeLast()
        for index in edited.weeks.indices {
            edited.weeks[index].schedule = edited.weeks[index].schedule.filter { $0.value != removed.id }
        }
        edited.weeks[2].isDeload = true
        try edited.days[0].slots.append(
            Seeders.slot(90, day: 0, position: 9, last: false, exercises.map(\.id))
        )
        let old = edited.days[1].slots[0]
        edited.days[1].slots[0] = try Slot(
            id: old.id,
            exerciseID: exercises[5].id,
            sets: old.sets % 12 + 1,
            reps: 12,
            repsHi: 15,
            rpe: 9.5,
            restSeconds: 300,
            progression: .fixed,
            startLoad: .kilograms(102.5),
            step: .pounds(1.25),
            misses: [3, 4]
        )
        edited.days[0].slots[1].misses.insert(5)
        edited.days[0].slots[3].misses = []
        edited.days[2].name = "Renamed — Day 3"
        edited.name = "Block 0, revised"
        edited.goal = .hypertrophy
        edited.daysPerWeek = 3
        return edited
    }

    // MARK: Clauses

    static func roundTrip(_ repository: any ProgramRepository) async throws -> String? {
        let program = try program()
        try await repository.save(program)
        return try await ContractCheck.expect(repository.active(), program, "active() after save")
    }

    static func saveReplaces(_ repository: any ProgramRepository) async throws -> String? {
        let program = try program()
        try await repository.save(program)
        let edited = try edited(program)
        try await repository.save(edited)
        let afterEdit = try await repository.active()
        try await repository.save(program)
        let afterRevert = try await repository.active()
        return ContractCheck.expect(afterEdit, edited, "active() after saving the edit")
            ?? ContractCheck.expect(afterRevert, program, "active() after saving the original again")
    }

    static func revalidates(_ repository: any ProgramRepository) async throws -> String? {
        let program = try program()
        try await repository.save(program)
        var slotOutOfRange = try edited(program)
        slotOutOfRange.days[1].slots[2].sets = 99
        var repsInverted = program
        repsInverted.days[0].slots[0].repsHi = repsInverted.days[0].slots[0].reps
        var tooFewWeeks = program
        tooFewWeeks.weeks = [tooFewWeeks.weeks[0]]
        let issue = await ContractCheck.expectError(SlotValidationError.setsOutOfRange(99)) {
            try await repository.save(slotOutOfRange)
        }
        let repsHi = program.days[0].slots[0].reps
        let inverted = await ContractCheck.expectError(
            SlotValidationError.repsHiNotAboveReps(reps: repsHi, repsHi: repsHi)
        ) { try await repository.save(repsInverted) }
        let weeks = await ContractCheck.expectError(ProgramValidationError.tooFewWeeks(count: 1)) {
            try await repository.save(tooFewWeeks)
        }
        let stored = try await repository.active()
        return issue ?? inverted ?? weeks ?? ContractCheck.expect(stored, program, "active() after the refused saves")
    }

    static func refusesNul(_ repository: any ProgramRepository) async throws -> String? {
        let program = try program()
        try await repository.save(program)
        var named = program
        named.name += "\u{0}"
        var dayNamed = program
        dayNamed.days[0].name = "Day\u{0}1"
        var tagged = program
        tagged.days[1].tag = "\u{0}"
        var other = try Self.program(number: 2, isActive: true)
        other.name = "\u{0}"
        let cases: [(Program, String)] = [
            (named, "program.name"), (dayNamed, "day_template.name"), (tagged, "day_template.tag"),
            (other, "program.name")
        ]
        for (refused, column) in cases {
            let issue = await ContractCheck.expectError(LedgerPersistenceError.nulInText(column)) {
                try await repository.save(refused)
            }
            if let issue {
                return "\(column): \(issue)"
            }
        }
        return try await ContractCheck.expect(repository.active(), program, "active() after the refused saves")
    }
}
