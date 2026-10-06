import Foundation
@testable import LedgerDomain
import Testing

/// Slice criterion 12, "what editing never writes": over seeded sequences that mix every `ProgramEditing`
/// function with every `DayEditing` function applied through `updateDay`, no slot that already exists ever
/// has other misses or another exercise, and the program stays one `Program.init` accepts with slots
/// `Slot.init` accepts (criterion 1). S3 relies on it: a workout's save writes those two fields.
@Suite("Editing never writes misses or exercises (adversarial)", .tags(.domain, .property))
struct EditingNeverWritesAdversarialTests {
    /// What a workout's save owns of a slot.
    struct Owned: Equatable {
        let exercise: ExerciseID
        let misses: Set<Int>
    }

    static func owned(_ program: Program) -> [SlotID: Owned] {
        let slots = program.days.flatMap(\.slots)
        return Dictionary(slots.map { ($0.id, Owned(exercise: $0.exerciseID, misses: $0.misses)) }) { first, _ in
            first
        }
    }

    /// The seed schedule with one to five seeded slots in every day, each with seeded misses.
    static func start(using generator: inout SeededGenerator) throws -> Program {
        var program = try EditAdv.fourDayProgram()
        for place in program.days.indices {
            var model = DayModel(units: .lb)
            let rows = (0 ..< Int.random(in: 1 ... 5, using: &generator)).map { offset in
                SlotRow.random(id: 5000 + 100 * place + offset, using: &generator)
            }
            model.add(rows, joined: rows.map { _ in Bool.random(using: &generator) })
            program.days[place].slots = try model.day().slots
        }
        return program
    }

    /// A block edit, or a day edit of one of the program's days through `updateDay`.
    static func edited(
        _ program: Program,
        step: Int,
        units: Units,
        using generator: inout SeededGenerator
    ) -> (program: Program, edit: String) {
        guard Int.random(in: 0 ..< 3, using: &generator) > 0,
              let day = program.days.randomElement(using: &generator)
        else {
            let edit = ProgramEditingModelAdversarialTests.randomEdit(
                BlockModel(program),
                step: step,
                using: &generator
            )
            return ((try? edit.applied(to: program)) ?? program, "\(edit)")
        }
        let edit = DayEdit.random(ids: day.slots.map(\.id), step: step, using: &generator)
        let result = ProgramEditing.updateDay(program, day: day.id) { current in
            (try? edit.applied(to: current, units: units)) ?? current
        }
        return (result, "day \(EditAdv.number(day.id.rawValue)): \(edit)")
    }
}

extension EditingNeverWritesAdversarialTests {
    @Test(
        "A hundred seeded edits of a program never write the misses or the exercise of a slot that exists.",
        arguments: PropertySeed.all
    )
    func editSequence_neverWritesMissesOrExercise(seed: PropertySeed) throws {
        var generator = seed.generator
        let units = Units.allCases.randomElement(using: &generator) ?? .lb
        var program = try Self.start(using: &generator)
        var born = Self.owned(program)
        for step in 0 ..< 100 {
            let next = Self.edited(program, step: step, units: units, using: &generator)
            program = next.program
            let now = Self.owned(program)
            let written = now.first { entry in born[entry.key].map { $0 != entry.value } ?? false }
            if let written {
                Issue
                    .record(
                        "\(seed), step \(step), \(next.edit): slot \(EditAdv.number(written.key.rawValue)) was written"
                    )
                return
            }
            if let rejection = EditAdv.rejection(of: program) {
                Issue.record("\(seed), step \(step), \(next.edit): \(rejection)")
                return
            }
            born.merge(now) { first, _ in first }
        }
    }

    @Test(
        "No single DayEditing function changes the misses or the exercise of any slot of a day, for every slot."
    )
    func everyFunction_onEverySlot_keepsMissesAndExercise() throws {
        let day = try EditAdv.day(flags: [false, true, false, true, true, false])
        let lift = EditAdv.lifts[0].exercise
        var tally = Tally()
        for slot in day.slots {
            var results = [DayEditing.removeSlot(day, slot: slot.id)]
            results += [true, false].map { DayEditing.setDropSet($0, slot: slot.id, in: day) }
            results += [true, false].map { DayEditing.setSuperset($0, slot: slot.id, in: day) }
            results += [MoveDirection.upward, .downward].map { DayEditing.move(day, slot: slot.id, $0) }
            results += Progression.allCases.map { DayEditing.setProgression($0, slot: slot.id, in: day) }
            for kind in SlotField.Kind.allCases {
                for direction in [StepDirection.upward, .downward] {
                    let field = DayEditing.stepped(kind, direction, of: slot, exercise: lift, units: .kg)
                    results.append(DayEditing.set(field, slot: slot.id, in: day))
                }
            }
            for (place, result) in results.enumerated() {
                let written = DayEditingModelAdversarialTests.written(result.slots, before: day.slots)
                tally.check(written == nil, "function \(place): \(written ?? "")")
            }
        }
        #expect(tally.passed, tally.summary)
        #expect(tally.cases == 6 * 22)
    }
}
