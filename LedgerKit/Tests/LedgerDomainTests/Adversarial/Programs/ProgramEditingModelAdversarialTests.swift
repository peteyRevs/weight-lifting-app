import Foundation
@testable import LedgerDomain
import Testing

/// Slice criteria 1 and 3 to 5 over seeded sequences of edits: after every edit the program is the one
/// `BlockModel` expects, `Program.init` accepts it, and nothing an edit does not name has changed.
@Suite("ProgramEditing against a model (adversarial)", .tags(.domain, .property))
struct ProgramEditingModelAdversarialTests {
    static let names = [
        "Push", "  Pull  ", "", "   ", "\u{0}", "Legs\u{7} day", "\tArms\n", "D\u{ED}a", "\u{1F3CB}\u{FE0F} Heavy",
        "\u{200F}\u{64A}\u{648}\u{645}", "A\u{0}B", "\u{85}\u{A0}"
    ]

    /// A block to start from: the seed schedule, a block with no days, one with a single day, or the seed
    /// schedule with slots in every day.
    static func start(using generator: inout SeededGenerator) throws -> Program {
        switch Int.random(in: 0 ..< 4, using: &generator) {
        case 0:
            return try EditAdv.fourDayProgram()
        case 1:
            return try EditAdv.program(weeks: EditAdv.restWeeks(2), days: [])
        case 2:
            return try EditAdv.program(weeks: EditAdv.restWeeks(3), days: [EditAdv.day(flags: [false, true])])
        default:
            var program = try EditAdv.fourDayProgram()
            for place in program.days.indices {
                let flags = (0 ... place).map { $0 == 2 }
                program.days[place].slots = try EditAdv.day(flags: flags, base: 5000 + 100 * place).slots
            }
            return program
        }
    }

    /// A seeded edit for a block of `model`'s shape; `step` gives a new week or day an id no other has. A
    /// week is sometimes before the block or past its end, and a day sometimes one the block lacks.
    static func randomEdit(_ model: BlockModel, step: Int, using generator: inout SeededGenerator) -> BlockEdit {
        let week = Int.random(in: -2 ... model.weeks.count + 1, using: &generator)
        switch Int.random(in: 0 ..< 10, using: &generator) {
        case 0, 1: return weekEdit(model, step: step, using: &generator)
        case 2: return .copyPrevious(week: week)
        case 3: return .applyLater(week: week)
        case 4, 5, 6: return .cycle(week: week, Weekday.allCases.randomElement(using: &generator) ?? .monday)
        default: return dayEdit(model, step: step, using: &generator)
        }
    }

    static func weekEdit(_ model: BlockModel, step: Int, using generator: inout SeededGenerator) -> BlockEdit {
        switch Int.random(in: 0 ..< 6, using: &generator) {
        case 0, 1: return .addWeek(EditAdv.weekID(60000 + step))
        case 2: return .addWeek(model.weeks.randomElement(using: &generator)?.id ?? EditAdv.weekID(200))
        case 3: return .toggleDeload(week: Int.random(in: -2 ... model.weeks.count + 1, using: &generator))
        default:
            let candidates = Array(-1 ... model.weeks.count + 1)
            return .removeLastWeek(logged: Set(candidates.filter { _ in
                Int.random(in: 0 ..< 5, using: &generator) == 0
            }))
        }
    }

    static func dayEdit(_ model: BlockModel, step: Int, using generator: inout SeededGenerator) -> BlockEdit {
        let name = names.randomElement(using: &generator) ?? ""
        let known = model.days.randomElement(using: &generator)?.id ?? EditAdv.dayID(999)
        let day = Int.random(in: 0 ..< 8, using: &generator) == 0 ? EditAdv.dayID(999) : known
        switch Int.random(in: 0 ..< 8, using: &generator) {
        case 0: return .rename(name)
        case 1, 2, 3: return .days(.add(EditAdv.dayID(70000 + step), name: name))
        case 4: return .days(.add(known, name: name))
        case 5: return .days(.rename(day, name: name))
        default: return .days(.delete(day))
        }
    }

    /// What is wrong with `program` after an edit, or `nil`.
    static func problem(_ program: Program, model: BlockModel, before: Program) -> String? {
        if let difference = model.difference(from: program) {
            return difference
        }
        if let rejection = EditAdv.rejection(of: program) {
            return rejection
        }
        let slots = Dictionary(before.days.map { ($0.id, $0.slots) }) { first, _ in first }
        if !program.days.allSatisfy({ $0.slots == slots[$0.id] ?? [] }) {
            return "a block edit changed a day's slots"
        }
        let header = [program.id == before.id, program.startDate == before.startDate, program.goal == before.goal]
        if header.contains(false) || program.daysPerWeek != before.daysPerWeek || program.isActive != before.isActive {
            return "the id, the start date, the goal, the days a week or the active flag changed"
        }
        return nil
    }
}

extension ProgramEditingModelAdversarialTests {
    @Test("Sixty seeded edits of a block give the model's block at every step.", arguments: PropertySeed.all)
    func editSequence_matchesTheModelAtEveryStep(seed: PropertySeed) throws {
        var generator = seed.generator
        var program = try Self.start(using: &generator)
        var model = BlockModel(program)
        for step in 0 ..< 60 {
            let edit = Self.randomEdit(model, step: step, using: &generator)
            let before = program
            let expectedError = model.apply(edit)
            var thrown: ProgramEditError?
            do {
                program = try edit.applied(to: program)
            } catch {
                thrown = error
            }
            var problem = Self.problem(program, model: model, before: before)
            if thrown != expectedError {
                problem = "threw \(String(describing: thrown)), expected \(String(describing: expectedError))"
            }
            if let problem {
                Issue.record("\(seed), step \(step), \(edit): \(problem)")
                return
            }
        }
        let decoded = try Adversarial.roundTrip(program) == program
        #expect(decoded, "\(seed): the edited program does not survive encoding and decoding")
    }

    @Test(
        "removeLastWeek, for 2 to 6 weeks and every set of logged weeks: the minimum comes first, then the last week."
    )
    func removeLastWeek_everyLoggedSet_throwsInOrder() throws {
        var tally = Tally()
        for count in 2 ... 6 {
            let program = try EditAdv.fourDayProgram(weekCount: count)
            let candidates = Array(-1 ... count + 1)
            for bits in 0 ..< 1 << candidates.count {
                let logged = Set(candidates.indices.filter { bits >> $0 & 1 == 1 }.map { candidates[$0] })
                var expected: ProgramEditError?
                if count == 2 {
                    expected = .minimumTwoWeeks
                } else if logged.contains(count - 1) {
                    expected = .weekHasLoggedSessions(weekNumber: count)
                }
                var thrown: ProgramEditError?
                var left = count
                do {
                    left = try ProgramEditing.removeLastWeek(program, loggedWeeks: logged).weeks.count
                } catch {
                    thrown = error
                }
                let holds = thrown == expected && left == (expected == nil ? count - 1 : count)
                tally.check(
                    holds,
                    "\(count) weeks, logged \(logged.sorted()): threw \(String(describing: thrown)), \(left) left"
                )
            }
        }
        #expect(tally.passed, tally.summary)
        #expect(tally.cases == 992)
    }

    @Test("A week before the block or past its end changes nothing, for every function that takes a week.")
    func weekOutsideTheBlock_changesNothing() throws {
        let program = try EditAdv.fourDayProgram()
        var tally = Tally()
        for week in Array(-40 ... -1) + Array(8 ... 48) {
            let results = [
                ProgramEditing.toggleDeload(program, week: week),
                ProgramEditing.cycleSchedule(program, week: week, weekday: .monday),
                ProgramEditing.cycleSchedule(program, week: week, weekday: .sunday),
                ProgramEditing.copyPreviousWeek(program, week: week),
                ProgramEditing.applyToLaterWeeks(program, week: week)
            ]
            for (place, result) in results.enumerated() {
                tally.check(result == program, "function \(place) changed the block for week \(week)")
            }
        }
        #expect(tally.passed, tally.summary)
    }
}
