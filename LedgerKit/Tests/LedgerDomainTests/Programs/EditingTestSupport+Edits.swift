import Foundation
@testable import LedgerDomain
import Testing

// Random edits for the seeded suites: every function of `DayEditing` and of `ProgramEditing`, each given
// ids the value holds and ids it does not, weeks inside and outside the block, and values far outside every
// range. `fresh` is a number no id in the value uses yet; an edit takes its new ids from it.

extension EditingTestSupport {
    typealias DayEdit = @Sendable (DayTemplate, Int, inout SeededGenerator) throws -> DayTemplate
    typealias ProgramEdit = @Sendable (Program, Int, inout SeededGenerator) throws -> Program

    static let names = ["Arms", "  Push \n", "", "\u{0}\t", "Lower\u{7}B", "E\u{301}paules", " \u{85} "]

    /// Values for every field, inside and far outside its range, on and off its step.
    static let fields: [SlotField] = [
        .sets(0), .sets(4), .sets(13), .sets(.min), .sets(.max),
        .reps(0), .reps(1), .reps(12), .reps(30), .reps(31), .reps(.max),
        .repsHi(1), .repsHi(2), .repsHi(9), .repsHi(40), .repsHi(41), .repsHi(.min),
        .rpe(4), .rpe(dec("7.3")), .rpe(dec("8.25")), .rpe(10), .rpe(11), .rpe(.nan), .rpe(.greatestFiniteMagnitude),
        .restSeconds(0), .restSeconds(37), .restSeconds(38), .restSeconds(120), .restSeconds(.max), .restSeconds(.min),
        .startLoad(.zero), .startLoad(.pounds(-5)), .startLoad(.pounds(dec("181.3"))), .startLoad(.kilograms(60)),
        .startLoad(Weight(grams: .nan))
    ]

    /// A slot id of the day, or one time in eight (and always for an empty day) an id it does not hold.
    static func someSlot(of day: DayTemplate, using generator: inout SeededGenerator) -> SlotID {
        let held = Int.random(in: 0 ..< 8, using: &generator) == 0 ? nil : day.slots.randomElement(using: &generator)
        return held?.id ?? SlotID(unknown)
    }

    /// A day id of the program, or one time in eight (and always with no day) an id it does not hold.
    static func someDay(of program: Program, using generator: inout SeededGenerator) -> DayTemplateID {
        let held = Int.random(in: 0 ..< 8, using: &generator) == 0 ? nil : program.days.randomElement(using: &generator)
        return held?.id ?? DayTemplateID(unknown)
    }

    /// A week index from one before the block to one past it.
    static func someWeek(of program: Program, using generator: inout SeededGenerator) -> Int {
        Int.random(in: -1 ... program.weeks.count, using: &generator)
    }

    static func direction(using generator: inout SeededGenerator) -> StepDirection {
        Bool.random(using: &generator) ? .upward : .downward
    }

    static let dayEdits: [(name: String, apply: DayEdit)] = [
        ("addSlots", { day, fresh, generator in
            let exercise = exercises.randomElement(using: &generator) ?? Fixtures.bench
            let rest = RestDuration(clampingSeconds: Int.random(in: 0 ... 400, using: &generator))
            var slot = try DayEditing.newSlot(
                id: SlotID(Fixtures.uuid(fresh)),
                exercise: exercise,
                units: .lb,
                defaultRest: rest
            )
            slot.isSupersetWithPrevious = Bool.random(using: &generator)
            return DayEditing.addSlots(day, [slot, slot] + day.slots.prefix(1))
        }),
        ("removeSlot", { day, _, generator in
            DayEditing.removeSlot(day, slot: someSlot(of: day, using: &generator))
        }),
        ("set", { day, _, generator in
            let field = fields.randomElement(using: &generator) ?? .sets(1)
            return DayEditing.set(field, slot: someSlot(of: day, using: &generator), in: day)
        }),
        ("set(stepped)", { day, _, generator in
            guard let slot = day.slots.randomElement(using: &generator) else {
                return day
            }
            let kind = SlotField.Kind.allCases.randomElement(using: &generator) ?? .sets
            let units = Units.allCases.randomElement(using: &generator) ?? .lb
            let exercise = exercises.first { $0.id == slot.exerciseID } ?? Fixtures.bench
            let field = DayEditing.stepped(
                kind,
                direction(using: &generator),
                of: slot,
                exercise: exercise,
                units: units
            )
            return DayEditing.set(field, slot: slot.id, in: day)
        }),
        ("setProgression", { day, _, generator in
            let progression = Progression.allCases.randomElement(using: &generator) ?? .double
            return DayEditing.setProgression(progression, slot: someSlot(of: day, using: &generator), in: day)
        }),
        ("setDropSet", { day, _, generator in
            DayEditing.setDropSet(Bool.random(using: &generator), slot: someSlot(of: day, using: &generator), in: day)
        }),
        ("setSuperset", { day, _, generator in
            DayEditing.setSuperset(Bool.random(using: &generator), slot: someSlot(of: day, using: &generator), in: day)
        }),
        ("move", { day, _, generator in
            DayEditing.move(
                day,
                slot: someSlot(of: day, using: &generator),
                Bool.random(using: &generator) ? .upward : .downward
            )
        })
    ]

    static let programEdits: [(name: String, apply: ProgramEdit)] = [
        ("renameProgram", { program, _, generator in
            ProgramEditing.renameProgram(program, to: names.randomElement(using: &generator) ?? "")
        }),
        ("addWeek", { program, fresh, generator in
            let reused = Int.random(in: 0 ..< 6, using: &generator) == 0 ? program.weeks.first?.id : nil
            return ProgramEditing.addWeek(program, id: reused ?? WeekID(Fixtures.uuid(fresh)))
        }),
        ("removeLastWeek", { program, _, generator in
            let logged = Set((0 ..< 2).map { _ in Int.random(in: -1 ... 13, using: &generator) })
            return (try? ProgramEditing.removeLastWeek(program, loggedWeeks: logged)) ?? program
        }),
        ("toggleDeload", { program, _, generator in
            ProgramEditing.toggleDeload(program, week: someWeek(of: program, using: &generator))
        }),
        ("cycleSchedule", { program, _, generator in
            let weekday = Weekday.allCases.randomElement(using: &generator) ?? .monday
            return ProgramEditing.cycleSchedule(
                program,
                week: someWeek(of: program, using: &generator),
                weekday: weekday
            )
        }),
        ("copyPreviousWeek", { program, _, generator in
            ProgramEditing.copyPreviousWeek(program, week: someWeek(of: program, using: &generator))
        }),
        ("applyToLaterWeeks", { program, _, generator in
            ProgramEditing.applyToLaterWeeks(program, week: someWeek(of: program, using: &generator))
        }),
        ("addDay", { program, fresh, generator in
            let reused = Int.random(in: 0 ..< 6, using: &generator) == 0 ? program.days.first?.id : nil
            let name = names.randomElement(using: &generator) ?? ""
            return ProgramEditing.addDay(program, id: reused ?? DayTemplateID(Fixtures.uuid(fresh)), name: name)
        }),
        ("renameDay", { program, _, generator in
            let name = names.randomElement(using: &generator) ?? ""
            return ProgramEditing.renameDay(program, day: someDay(of: program, using: &generator), to: name)
        }),
        ("deleteDay", { program, _, generator in
            ProgramEditing.deleteDay(program, day: someDay(of: program, using: &generator))
        }),
        ("updateDay", { program, fresh, generator in
            let edit = dayEdits.randomElement(using: &generator) ?? dayEdits[0]
            var failure: (any Error)?
            let edited = ProgramEditing.updateDay(program, day: someDay(of: program, using: &generator)) { day in
                do {
                    return try edit.apply(day, fresh, &generator)
                } catch {
                    failure = error
                    return day
                }
            }
            if let failure {
                throw failure
            }
            return edited
        })
    ]
}
