@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S6 criteria 1 and 10: an edit is exactly one Domain call, written here by hand beside it; every edit
/// but a move gives, applied twice, what one application gives; and the two relative ones are marked.
@Suite("DayEditorEdit", .tags(.feature))
nonisolated struct DayEditorActionTests {
    /// Each slot edit beside the `DayEditing` call it stands for, on Upper A of the seed program.
    static func slotPairs(on day: DayTemplate) -> [(edit: SlotEdit, expected: DayTemplate)] {
        let first = day.slots[0].id
        let second = day.slots[1].id
        let last = day.slots[4].id
        return [
            (.set(.sets(7), slot: first), DayEditing.set(.sets(7), slot: first, in: day)),
            (.set(.reps(12), slot: second), DayEditing.set(.reps(12), slot: second, in: day)),
            (.set(.repsHi(3), slot: second), DayEditing.set(.repsHi(3), slot: second, in: day)),
            (.set(.rpe(9.5), slot: first), DayEditing.set(.rpe(9.5), slot: first, in: day)),
            (.set(.restSeconds(45), slot: first), DayEditing.set(.restSeconds(45), slot: first, in: day)),
            (
                .set(.startLoad(.pounds(185)), slot: first),
                DayEditing.set(.startLoad(.pounds(185)), slot: first, in: day)
            ),
            (.setProgression(.double, slot: first), DayEditing.setProgression(.double, slot: first, in: day)),
            (.setDropSet(true, slot: first), DayEditing.setDropSet(true, slot: first, in: day)),
            (.setSuperset(true, slot: second), DayEditing.setSuperset(true, slot: second, in: day)),
            (.setSuperset(false, slot: last), DayEditing.setSuperset(false, slot: last, in: day)),
            (.move(.downward, slot: first), DayEditing.move(day, slot: first, .downward)),
            (.move(.upward, slot: last), DayEditing.move(day, slot: last, .upward)),
            (.remove(slot: second), DayEditing.removeSlot(day, slot: second))
        ]
    }

    @Test("Each slot edit gives the day its one DayEditing call gives, and each changes Upper A")
    func slotEdit_applied_isTheOneDayEditingCall() throws {
        let day = try Fixtures.upperA()
        let pairs = Self.slotPairs(on: day)
        #expect(pairs.count == 13)
        for (edit, expected) in pairs {
            let isSame = edit.applied(to: day) == expected
            #expect(isSame, "\(edit)")
            let hasChanged = expected != day
            #expect(hasChanged, "\(edit) is seen to do something")
        }
    }

    @Test("A slot edit in a program is updateDay around it; a rename and a delete are ProgramEditing's own")
    func edit_applied_isTheOneProgramEditingCall() throws {
        let program = try Fixtures.seedProgram()
        let day = program.days[0]
        for (slotEdit, edited) in Self.slotPairs(on: day) {
            let expected = ProgramEditing.updateDay(program, day: day.id) { _ in edited }
            let isSame = DayEditorEdit.slot(slotEdit, day: day.id).applied(to: program) == expected
            #expect(isSame, "\(slotEdit)")
            #expect(expected.days[0].slots.count == edited.slots.count)
        }
        let renamed = DayEditorEdit.renameDay(" Push ", day: day.id).applied(to: program)
        let isRenamed = renamed == ProgramEditing.renameDay(program, day: day.id, to: " Push ")
        #expect(isRenamed)
        #expect(renamed.days[0].name == "Push")
        let deleted = DayEditorEdit.deleteDay(day.id).applied(to: program)
        let isDeleted = deleted == ProgramEditing.deleteDay(program, day: day.id)
        #expect(isDeleted)
        #expect(deleted.days.count == 3)
    }

    @Test("An edit that names a day or a slot the program does not hold changes nothing")
    func edit_unknownDayOrSlot_changesNothing() throws {
        let program = try Fixtures.seedProgram()
        let day = program.days[0].id
        let otherDay = DayTemplateID(Fixtures.uuid(999))
        // A slot of Lower A is not a slot of Upper A.
        let foreign = program.days[1].slots[0].id
        let edits: [DayEditorEdit] = [
            .renameDay("Push", day: otherDay), .renameDay("\n ", day: day), .deleteDay(otherDay),
            .slot(.set(.sets(7), slot: program.days[0].slots[0].id), day: otherDay),
            .slot(.set(.sets(7), slot: foreign), day: day), .slot(.setProgression(.fixed, slot: foreign), day: day),
            .slot(.setDropSet(true, slot: foreign), day: day), .slot(.setSuperset(true, slot: foreign), day: day),
            .slot(.move(.downward, slot: foreign), day: day), .slot(.remove(slot: foreign), day: day)
        ]
        for edit in edits {
            let isSame = edit.applied(to: program) == program
            #expect(isSame, "\(edit)")
        }
    }

    @Test("Only a move and a removal are marked relative, and the mark of a slot edit is its day edit's")
    func isRelative_marksMoveAndRemove() throws {
        let day = try Fixtures.upperA()
        let relative = Self.slotPairs(on: day).map(\.edit).filter(\.isRelative)
        #expect(relative == [
            .move(.downward, slot: day.slots[0].id), .move(.upward, slot: day.slots[4].id),
            .remove(slot: day.slots[1].id)
        ])
        for edit in Self.slotPairs(on: day).map(\.edit) {
            #expect(DayEditorEdit.slot(edit, day: day.id).isRelative == edit.isRelative, "\(edit)")
        }
        #expect(DayEditorEdit.renameDay("Push", day: day.id).isRelative == false)
        #expect(DayEditorEdit.deleteDay(day.id).isRelative == false)
    }

    @Test("Every edit not marked relative gives, applied twice, what one application gives; a move does not")
    func edits_appliedTwice_onlyAMoveDiffers() throws {
        let program = try Fixtures.seedProgram()
        let day = program.days[0]
        let edits = Self.slotPairs(on: day).map { DayEditorEdit.slot($0.edit, day: day.id) }
            + [.renameDay("Push", day: day.id), .deleteDay(day.id)]
        for edit in edits where !edit.isRelative {
            let once = edit.applied(to: program)
            let isSame = edit.applied(to: once) == once
            #expect(isSame, "\(edit)")
        }
        // A move carries the slot one place from wherever it stands: twice is two places.
        let move = DayEditorEdit.slot(.move(.downward, slot: day.slots[0].id), day: day.id)
        let once = move.applied(to: program)
        let twice = move.applied(to: once)
        #expect(once.days[0].slots.map(\.id).firstIndex(of: day.slots[0].id) == 1)
        #expect(twice.days[0].slots.map(\.id).firstIndex(of: day.slots[0].id) == 2)
        // A removal names its slot, so a second one finds nothing; it is marked relative all the same,
        // because the member it leaves to lead the superset is decided by the day it meets.
        let removal = DayEditorEdit.slot(.remove(slot: day.slots[3].id), day: day.id)
        let removed = removal.applied(to: program)
        let isSame = removal.applied(to: removed) == removed
        #expect(isSame)
        #expect(removed.days[0].slots.map(\.isSupersetWithPrevious) == [false, false, false, false])
    }

    @Test("A queue of unmarked edits replayed over its own result gives another program: no queue is sent twice")
    func queue_replayed_givesAnotherProgram() throws {
        // Three exercises on their own. "Superset with next" on the second names the third; then the second
        // is removed, and the third leads what is left.
        let slots = try [DayEditorFixtures.slot(1), DayEditorFixtures.slot(2), DayEditorFixtures.slot(3)]
        let input = try DayEditorFixtures.input(slots: slots)
        let join = DayEditorEdit.slot(.setSuperset(true, slot: slots[2].id), day: input.day)
        let queue = [join, .slot(.remove(slot: slots[1].id), day: input.day)]
        #expect(join.isRelative == false)
        let once = queue.reduce(input.program) { $1.applied(to: $0) }
        #expect(once.days[0].slots.map(\.isSupersetWithPrevious) == [false, false])
        // Replayed, the join finds another slot before the third and joins it to that one.
        let twice = queue.reduce(once) { $1.applied(to: $0) }
        #expect(twice.days[0].slots.map(\.id) == [slots[0].id, slots[2].id])
        #expect(twice.days[0].slots.map(\.isSupersetWithPrevious) == [false, true])
    }

    @Test("The name field's action is the rename edit with the text as typed, and it leaves the panel open")
    func rename_isTheRenameEditWithTheTypedText() {
        let day = DayTemplateID(Fixtures.uuid(300))
        #expect(DayEditorAction.rename("Push ", day: day) == .edit(.renameDay("Push ", day: day), closesPanel: false))
    }
}
