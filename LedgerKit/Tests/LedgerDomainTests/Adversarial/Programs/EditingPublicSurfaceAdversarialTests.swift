import Foundation
import LedgerDomain
import Testing

/// Later slices' stores live in `FeatureProgram`, another module, "and add nothing". This file imports
/// `LedgerDomain` without `@testable`, so it compiles only while every editing function, type and constant
/// the plan lists is public, and its checks run only through that public surface. The generic helpers hold
/// the plan's conformances (slice criterion 13: `Sendable` as their neighbours are).
@Suite("Editing public surface (adversarial)", .tags(.domain))
struct EditingPublicSurfaceAdversarialTests {
    static func isSendable(_: (some Sendable).Type) -> Bool {
        true
    }

    static func isHashable(_: (some Hashable).Type) -> Bool {
        true
    }

    static func count<Cases: CaseIterable>(_: Cases.Type) -> Int {
        Cases.allCases.count
    }
}

extension EditingPublicSurfaceAdversarialTests {
    @Test("The plan's types are public, Hashable and Sendable, and the errors are Equatable errors.")
    func types_haveThePlansConformances() {
        #expect(Self.isSendable(SlotField.self) && Self.isHashable(SlotField.self))
        #expect(Self.isSendable(SlotField.Kind.self) && Self.isHashable(SlotField.Kind.self))
        #expect(Self.isSendable(StepDirection.self) && Self.isHashable(StepDirection.self))
        #expect(Self.isSendable(MoveDirection.self) && Self.isHashable(MoveDirection.self))
        #expect(Self.isSendable(ExerciseSearch.MuscleFilter.self) && Self.isHashable(ExerciseSearch.MuscleFilter.self))
        #expect(Self.isSendable(ProgramEditError.self))
        #expect(Self.count(SlotField.Kind.self) == 6)
        #expect(Self.count(ExerciseSearch.MuscleFilter.self) == 5)
        let failure: any Error = ProgramEditError.weekHasLoggedSessions(weekNumber: 8)
        #expect(failure as? ProgramEditError == .weekHasLoggedSessions(weekNumber: 8))
        #expect(ProgramEditError.minimumTwoWeeks != .weekHasLoggedSessions(weekNumber: 2))
    }

    @Test("Every block edit can be called from another module, and from a task off the main actor.")
    func programEditing_isPublicAndCallableOffTheMainActor() async throws {
        let program = try EditAdv.fourDayProgram()
        let day = EditAdv.fourDayIDs[0]
        let counts = await Task.detached { () -> [Int] in
            let named = ProgramEditing.renameProgram(program, to: ProgramEditing.cleanedName(" Block ") ?? "")
            let longer = ProgramEditing.addWeek(named, id: EditAdv.weekID(208))
            let shorter = (try? ProgramEditing.removeLastWeek(longer, loggedWeeks: [])) ?? longer
            let deloaded = ProgramEditing.toggleDeload(shorter, week: 0)
            let cycled = ProgramEditing.cycleSchedule(deloaded, week: 0, weekday: .sunday)
            let copied = ProgramEditing.copyPreviousWeek(cycled, week: 1)
            let applied = ProgramEditing.applyToLaterWeeks(copied, week: 1)
            let added = ProgramEditing.addDay(applied, id: EditAdv.dayID(340), name: "New day")
            let renamed = ProgramEditing.renameDay(added, day: day, to: "Push")
            let updated = ProgramEditing.updateDay(renamed, day: day) { $0 }
            let deleted = ProgramEditing.deleteDay(updated, day: day)
            return [deleted.weeks.count, deleted.days.count, deleted.weeks[7].schedule.count]
        }.value
        #expect(counts == [8, 4, 3])
    }

    @Test("Every day edit, the ranges and the clamping initializers can be called from another module.")
    func dayEditing_isPublicAndCallable() throws {
        let exercise = Fixtures.bench
        let rest = RestDuration(clampingSeconds: 100)
        let slot = try DayEditing.newSlot(id: EditAdv.slotID(1), exercise: exercise, units: .kg, defaultRest: rest)
        let other = try DayEditing.newSlot(id: EditAdv.slotID(2), exercise: exercise, units: .kg, defaultRest: rest)
        var day = DayEditing.addSlots(DayTemplate(id: EditAdv.dayID(4000), name: "Day", tag: "D1"), [slot, other])
        for kind in SlotField.Kind.allCases {
            let field = DayEditing.stepped(kind, StepDirection.upward, of: slot, exercise: exercise, units: .kg)
            day = DayEditing.set(field, slot: slot.id, in: day)
        }
        day = DayEditing.set(.rpe(RPE(clamping: 11).value), slot: other.id, in: day)
        day = DayEditing.setProgression(.double, slot: slot.id, in: day)
        day = DayEditing.setDropSet(true, slot: slot.id, in: day)
        day = DayEditing.setSuperset(true, slot: other.id, in: day)
        day = DayEditing.move(day, slot: other.id, MoveDirection.upward)
        #expect(DayEditing.groups(of: day) == [[other.id, slot.id]])
        let edited = try #require(day.slots.last)
        let numbers = [edited.sets, edited.reps, edited.repsHi, edited.rest.seconds, edited.dropSets]
        #expect(numbers == [4, 9, 11, 120, 1])
        #expect(edited.startLoad == .kilograms(82.5))
        #expect(edited.rpe == RPE(8.5))
        #expect(DayEditing.removeSlot(day, slot: slot.id).slots.map(\.rpe.value) == [10])
        #expect(Slot.setsRange.upperBound + Slot.repsRange.upperBound + Slot.repsHiRange.upperBound == 82)
    }

    @Test("The week strip's prescriptions and the library's filter can be called from another module.")
    func prescriptionsAndFilter_arePublicAndCallable() throws {
        let slot = try Fixtures.slot(Fixtures.backSquat, id: 311, sets: 5, reps: 5, rest: 180)
        let weeks = try EditAdv.fourDayProgram().weeks
        let rows = ProgressionRules.prescriptions(for: slot, weeks: weeks, exercise: Fixtures.backSquat, units: .lb)
        #expect(rows.last?.load == .pounds(240))
        let chip = ExerciseSearch.MuscleFilter.chest
        #expect(chip.groups == [.chest])
        let found = ExerciseSearch.filter(
            [Fixtures.bench, Fixtures.backSquat],
            query: "squat",
            muscle: chip,
            equipment: .barbell
        )
        #expect(found.map(\.name) == ["Back Squat"])
    }
}
