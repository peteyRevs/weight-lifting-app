import Foundation
@testable import LedgerDomain
import Testing

/// What slice criterion 12 is for: S3 stores a builder edit and a workout's save in either order, so an edit
/// must neither write a slot's misses and exercise nor read them. Here a "save" writes both on one slot, and
/// every seeded edit must give the same day, and the same program, whether it runs before the save or after.
@Suite("An edit and a workout's save commute (adversarial)", .tags(.domain, .property))
struct EditingCommutesAdversarialTests {
    /// What a workout's save writes on one slot: its misses (rule 13) and, after a swap, its exercise.
    struct Save {
        let slot: SlotID
        let misses: Set<Int>
        let exercise: ExerciseID

        static func random(ids: [SlotID], using generator: inout SeededGenerator) -> Save {
            Save(
                slot: ids.randomElement(using: &generator) ?? EditAdv.slotID(999),
                misses: Set((0 ..< 8).filter { _ in Bool.random(using: &generator) }),
                exercise: ExerciseID(Fixtures.uuid(Int.random(in: 950 ... 959, using: &generator)))
            )
        }

        func applied(to day: DayTemplate) -> DayTemplate {
            var saved = day
            if let place = saved.slots.firstIndex(where: { $0.id == slot }) {
                saved.slots[place].misses = misses
                saved.slots[place].exerciseID = exercise
            }
            return saved
        }
    }
}

extension EditingCommutesAdversarialTests {
    @Test(
        "Forty seeded day edits each commute with a save of one slot's misses and exercise.",
        arguments: PropertySeed.all
    )
    func dayEdit_andASave_commute(seed: PropertySeed) throws {
        var generator = seed.generator
        var model = DayEditingModelAdversarialTests.start(using: &generator)
        var day = try model.day()
        // The start-load stepper is given one exercise throughout: which exercise it reads is the caller's.
        let exercise = EditAdv.lifts[1].exercise
        for step in 0 ..< 40 {
            let edit = DayEdit.random(ids: model.ids, step: step, using: &generator)
            let save = Save.random(ids: model.ids, using: &generator)
            let editThenSave = try save.applied(to: edit.applied(to: day, units: model.units, exercise: exercise))
            let saveThenEdit = try edit.applied(to: save.applied(to: day), units: model.units, exercise: exercise)
            let commute = editThenSave == saveThenEdit
            if !commute {
                let found = "[\(EditAdv.brief(saveThenEdit.slots))] against [\(EditAdv.brief(editThenSave.slots))]"
                Issue.record("\(seed), step \(step), \(edit), save of \(EditAdv.number(save.slot.rawValue)): \(found)")
                return
            }
            edit.apply(to: &model)
            day = try edit.applied(to: day, units: model.units)
        }
    }

    @Test(
        "Sixty seeded block edits each commute with a save of one slot's misses and exercise.",
        arguments: PropertySeed.all
    )
    func blockEdit_andASave_commute(seed: PropertySeed) throws {
        var generator = seed.generator
        var program = try EditingNeverWritesAdversarialTests.start(using: &generator)
        for step in 0 ..< 60 {
            let edit = ProgramEditingModelAdversarialTests.randomEdit(
                BlockModel(program),
                step: step,
                using: &generator
            )
            let save = Save.random(ids: program.days.flatMap(\.slots).map(\.id), using: &generator)
            func saved(_ program: Program) -> Program {
                var copy = program
                copy.days = copy.days.map(save.applied(to:))
                return copy
            }
            let editThenSave = saved((try? edit.applied(to: program)) ?? program)
            let saveThenEdit = (try? edit.applied(to: saved(program))) ?? saved(program)
            let commute = editThenSave == saveThenEdit
            if !commute {
                Issue.record("\(seed), step \(step), \(edit), save of \(EditAdv.number(save.slot.rawValue))")
                return
            }
            program = (try? edit.applied(to: program)) ?? program
        }
    }
}
