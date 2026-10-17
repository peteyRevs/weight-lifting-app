@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S8 adversarial round 1, criterion 11: the picks become slots through the Domain. The store's part is
/// spelled here from `ExercisePickerAction.add`'s documentation: a slot from `DayEditing.newSlot` for each id,
/// in order, then one `SlotEdit.add`.
@Suite("Adversarial F11 S8 · the picks become slots", .tags(.feature, .property))
nonisolated struct ExercisePickerAddAdversarialTests {
    static func slots(
        for ids: [ExerciseID],
        among exercises: [Exercise],
        settings: Settings,
        firstID: Int = 70000
    ) throws -> [Slot] {
        try ids.enumerated().map { place, id in
            try DayEditing.newSlot(
                id: SlotID(Fixtures.uuid(firstID + place)),
                exercise: #require(exercises.first { $0.id == id }),
                units: settings.units,
                defaultRest: settings.defaultRest
            )
        }
    }

    @Test("Every catalog exercise, added in either unit, is a slot of rule 7's defaults with its own start load")
    func add_everyCatalogExercise_hasRuleSevenDefaults() throws {
        let catalog = try ExerciseCatalog.seed()
        for settings in [Fixtures.settingsLb, Fixtures.settingsKg] {
            let slots = try Self.slots(for: catalog.map(\.id), among: catalog, settings: settings)
            let day = DayTemplate(id: DayTemplateID(Fixtures.uuid(71000)), name: "Everything", tag: "EV", slots: [])
            let added = SlotEdit.add(slots).applied(to: day).slots
            #expect(added.count == catalog.count)
            for (slot, exercise) in zip(added, catalog) {
                let isRuleSeven = slot.sets == 3 && slot.reps == 8 && slot.repsHi == 10 && slot.rpe.value == 8
                    && slot.progression == .linear && slot.rest == settings.defaultRest
                    && slot.startLoad == exercise.startLoad(in: settings.units)
                let isPlain = !slot.isSupersetWithPrevious && slot.dropSets == 0 && slot.misses.isEmpty
                    && slot.step == nil && slot.exerciseID == exercise.id
                #expect(isRuleSeven && isPlain, "\(exercise.name) in \(settings.units)")
            }
        }
    }

    @Test(
        "Picks tapped on seeded screens go to the day's end in pick order, once each, and nothing else moves",
        arguments: PropertySeed.all.prefix(60)
    )
    func add_seededPicks_appendInPickOrder(seed: PropertySeed) throws {
        var generator = seed.generator
        let catalog = try ExerciseCatalog.seed()
        let program = try Fixtures.seedProgram()
        let place = Int.random(in: program.days.indices, using: &generator)
        let day = program.days[place]
        var input = ExercisePickerInput(
            exercises: catalog.shuffled(using: &generator), dayExercises: Set(day.slots.map(\.exerciseID)),
            query: "", muscle: nil, equipment: nil, picks: [], locale: Locale(identifier: "en_US")
        )
        var order: [ExerciseID] = []
        for _ in 0 ..< Int.random(in: 1 ... 9, using: &generator) {
            let rows = ExercisePickerPresentation.make(input).rows
            let row = try #require(rows.randomElement(using: &generator))
            order.removeAll { $0 == row.id }
            order += row.isPicked ? [] : [row.id]
            input = AdvPicker.apply(row.action, to: input).input
        }
        guard let action = ExercisePickerPresentation.make(input).foot.action else {
            #expect(order.isEmpty, "\(seed): no foot action with \(order.count) picks")
            return
        }
        let ids = try #require(AdvPicker.apply(action, to: input).added)
        #expect(ids == order, "\(seed)")
        let slots = try Self.slots(for: ids, among: catalog, settings: Fixtures.settingsLb)
        let edit = DayEditorEdit.slot(.add(slots), day: day.id)
        let edited = edit.applied(to: program)
        let after = edited.days[place].slots
        #expect(after.map(\.exerciseID) == day.slots.map(\.exerciseID) + order, "\(seed)")
        let keepsTheRest = Array(after.prefix(day.slots.count)) == day.slots
            && edited.days.indices.allSatisfy { $0 == place || edited.days[$0] == program.days[$0] }
            && edited.weeks == program.weeks
        #expect(keepsTheRest, "\(seed)")
        let isSafeTwice = edit.applied(to: edited) == edited
        #expect(isSafeTwice, "\(seed)")
    }

    @Test("An empty list, slots the day holds and a list naming one id twice add nothing or one")
    func add_emptyHeldAndRepeated() throws {
        let program = try Fixtures.seedProgram()
        let catalog = try ExerciseCatalog.seed()
        for day in program.days {
            let isUnchanged = SlotEdit.add([]).applied(to: day) == day && SlotEdit.add(day.slots)
                .applied(to: day) == day
            #expect(isUnchanged, "\(day.name)")
        }
        let day = program.days[0]
        let slot = try #require(Self.slots(for: [catalog[0].id], among: catalog, settings: Fixtures.settingsLb).first)
        let repeated = SlotEdit.add([slot, slot, slot]).applied(to: day).slots
        #expect(repeated.count == day.slots.count + 1 && repeated.last?.id == slot.id)
        #expect(SlotEdit.add([]).isRelative == false)
    }

    @Test("The same exercise picked for a day that holds it, and added twice over, stands in the day each time")
    func add_sameExerciseAgain_isAnotherSlot() throws {
        let program = try Fixtures.seedProgram()
        let catalog = try ExerciseCatalog.seed()
        let day = program.days[0]
        let held = try #require(day.slots.first).exerciseID
        let first = try Self.slots(for: [held], among: catalog, settings: Fixtures.settingsLb, firstID: 72000)
        let second = try Self.slots(for: [held], among: catalog, settings: Fixtures.settingsLb, firstID: 72100)
        let after = SlotEdit.add(second).applied(to: SlotEdit.add(first).applied(to: day))
        #expect(after.slots.count == day.slots.count + 2)
        #expect(after.slots.count { $0.exerciseID == held } == day.slots.count { $0.exerciseID == held } + 2)
        #expect(Set(after.slots.map(\.id)).count == after.slots.count)
    }
}
