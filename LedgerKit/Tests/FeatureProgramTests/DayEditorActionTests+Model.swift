@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The actions as the model hands them out: a stepper's carries the Domain's stepped value, and each says
/// whether the panel closes.
nonisolated extension DayEditorActionTests {
    @Test("A stepper's action carries the value DayEditing.stepped gives for the slot on screen")
    func stepperAction_carriesTheSteppedValue() throws {
        var input = try DayEditorFixtures.seedInput()
        let slot = input.program.days[0].slots[1]
        input.openSlot = slot.id
        let exercise = try #require(input.exercises[slot.exerciseID])
        let details = try #require(DayEditorPresentation.make(input).content().row("2").panel?.details)
        for field in details.fields {
            for (action, direction) in [(field.decrement, StepDirection.downward), (field.increment, .upward)] {
                let stepped = DayEditing.stepped(field.kind, direction, of: slot, exercise: exercise, units: .lb)
                #expect(action == .edit(.slot(.set(stepped, slot: slot.id), day: input.day), closesPanel: false))
            }
        }
        #expect(details.fields.count == 6)
    }

    @Test("Which actions close the panel: the superset's, Remove and Delete; a field, a move and the rest do not")
    func closesPanel_isSetOnTheActionsThatCloseIt() throws {
        var input = try DayEditorFixtures.input(slots: DayEditorFixtures.fiveWithASuperset())
        input.openSlot = DayEditorFixtures.slotID(4)
        let content = try DayEditorPresentation.make(input).content()
        let panel = try #require(content.row("3B").panel)
        let details = try #require(panel.details)
        /// "closes" or "stays" for an edit, by its flag.
        func ending(of action: DayEditorAction?) -> String {
            guard case let .edit(_, closesPanel) = action else {
                return "not an edit"
            }
            return closesPanel ? "closes" : "stays"
        }
        #expect(panel.supersetActions.map { ending(of: $0.action) } == ["closes", "closes"])
        #expect(ending(of: panel.remove.action) == "closes")
        #expect(ending(of: content.deleteDay.confirmation.confirm.action) == "closes")
        #expect(ending(of: panel.moveUp?.action) == "stays")
        #expect(ending(of: panel.moveDown?.action) == "stays")
        #expect(ending(of: details.dropSet.action) == "stays")
        let steppers = details.fields.flatMap { [ending(of: $0.decrement), ending(of: $0.increment)] }
        #expect(steppers == Array(repeating: "stays", count: 10))
        #expect(details.progression.chips.compactMap(\.action).map { ending(of: $0) } == ["stays", "stays"])
    }
}
