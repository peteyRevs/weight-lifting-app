import Foundation
@testable import LedgerDomain
import Testing

/// `ProgramTemplates.program`: what every generated block has in common (F08 criteria 7 and 9). The §6.4 seed
/// is in `ProgramTemplatesSeedTests`, the splits and the role table in `ProgramTemplatesSplitsTests`.
@Suite("ProgramTemplates", .tags(.domain))
struct ProgramTemplatesTests {
    @Test("The cases are the 16 (goal, days) pairs, and each of them in pounds and in kilograms")
    func cases_coverEveryGoalDaysAndUnit() {
        #expect(TemplateCase.pairs.count == 16)
        #expect(Set(TemplateCase.pairs.map(\.description)).count == 16)
        #expect(TemplateCase.all.count == 32)
        #expect(Set(TemplateCase.all.map(\.description)).count == 32)
    }

    @Test(
        "A block is active, 8 weeks from its start date, and records the goal and the days",
        arguments: TemplateCase.all
    )
    func program_recordsGoalDaysAndIsActive(_ block: TemplateCase) throws {
        let program = try block.program()
        #expect(program.id == Fixtures.programID)
        #expect(program.isActive)
        #expect(program.goal == block.goal)
        #expect(program.daysPerWeek == block.days.rawValue)
        #expect(program.startDate == TemplateCase.start)
        #expect(ProgramTemplates.weekCount == 8)
        #expect(program.weeks.map(\.index) == Array(0 ..< 8))
        #expect(program.days.count == block.days.rawValue)
        #expect(program.days.allSatisfy { !$0.slots.isEmpty })
    }

    @Test("Week 8 is a deload, and the only one", arguments: TemplateCase.pairs)
    func program_onlyWeek8IsADeload(_ block: TemplateCase) throws {
        let program = try block.program()
        #expect(program.weeks.map(\.isDeload) == Array(repeating: false, count: 7) + [true])
    }

    @Test(
        "Weeks 1–7 schedule exactly the picked number of days: each day once, on its weekday",
        arguments: TemplateCase.pairs
    )
    func program_weeks1to7_scheduleExactlyDaysPerWeek(_ block: TemplateCase) throws {
        let program = try block.program()
        let weekdays = TemplateOracle.split(for: block.days).weekdays
        let expected = Dictionary(uniqueKeysWithValues: zip(weekdays, program.days.map(\.id)))
        #expect(expected.count == block.days.rawValue)
        for week in program.weeks.prefix(7) {
            #expect(week.schedule.count == block.days.rawValue, "week \(week.index + 1)")
            #expect(week.schedule == expected, "week \(week.index + 1)")
        }
    }

    @Test("The deload week keeps every training day, except the 4-day split's Saturday", arguments: TemplateCase.pairs)
    func program_deloadWeek_keepsItsDays_exceptTheFourDaySaturday(_ block: TemplateCase) throws {
        let program = try block.program()
        let lastFullWeek = try #require(program.week(at: 6)).schedule
        let deload = try #require(program.week(at: 7)).schedule
        if block.days == .four {
            #expect(deload == lastFullWeek.filter { $0.key != .saturday })
            #expect(deload.count == 3)
        } else {
            #expect(deload == lastFullWeek)
        }
    }

    @Test("Criterion 7: every slot value is inside spec §7.1's ranges", arguments: TemplateCase.all)
    func program_everyGoalAndSplit_staysInsideSpec71(_ block: TemplateCase) throws {
        let slots = try block.program().days.flatMap(\.slots)
        #expect(slots.count >= 3 * block.days.rawValue)
        let rpeSteps = Set((10 ... 20).map { Decimal($0) / 2 }) // 5, 5.5 … 10
        for slot in slots {
            #expect((1 ... 12).contains(slot.sets))
            #expect((1 ... 30).contains(slot.reps))
            #expect((2 ... 40).contains(slot.repsHi) && slot.repsHi > slot.reps)
            #expect(rpeSteps.contains(slot.rpe.value))
            #expect((30 ... 300).contains(slot.rest.seconds) && slot.rest.seconds.isMultiple(of: 15))
            #expect((0 ... 1).contains(slot.dropSets))
            #expect(slot.misses.isEmpty)
        }
    }

    @Test("Criterion 9: the same request and the same id sequence give an equal program", arguments: TemplateCase.all)
    func program_sameInputsAndIDs_isEqual(_ block: TemplateCase) throws {
        let first = try block.program()
        #expect(try block.program() == first)
        // The ids come from the sequence and nowhere else: another sequence gives another program.
        #expect(try block.program(firstID: 500) != first)
    }

    @Test("Ids are asked for in order: the eight weeks, then each day followed by its slots")
    func program_drawsIDs_weeksThenEachDayAndItsSlots() throws {
        var calls = 0
        let program = try ProgramTemplates.program(
            TemplateCase(goal: .both, days: .four).request,
            catalog: BundledCatalog.exercises(),
            id: Fixtures.programID,
            newID: {
                calls += 1
                return Fixtures.uuid(calls)
            }
        )
        #expect(calls == 28)
        #expect(program.weeks.map(\.id) == (1 ... 8).map { WeekID(Fixtures.uuid($0)) })
        #expect(program.days.map(\.id) == [9, 15, 20, 25].map { DayTemplateID(Fixtures.uuid($0)) })
        let slotNumbers = [Array(10 ... 14), Array(16 ... 19), Array(21 ... 24), Array(26 ... 28)]
        #expect(program.days.map { $0.slots.map(\.id) } == slotNumbers.map { $0.map { SlotID(Fixtures.uuid($0)) } })
    }

    @Test("Every week, day and slot has an id of its own, and none is the program's", arguments: TemplateCase.pairs)
    func program_idsAreAllDistinct(_ block: TemplateCase) throws {
        let program = try block.program()
        let slots = program.days.flatMap(\.slots)
        let ids = program.weeks.map(\.id.rawValue) + program.days.map(\.id.rawValue) + slots.map(\.id.rawValue)
        #expect(ids.count == 8 + block.days.rawValue + slots.count)
        #expect(Set(ids).count == ids.count)
        #expect(!ids.contains(program.id.rawValue))
    }

    @Test("Every day of every block builds a session, in week 1 and in the deload week", arguments: TemplateCase.all)
    func program_everyDay_buildsASession(_ block: TemplateCase) throws {
        let program = try block.program()
        var settings = Settings.default
        settings.units = block.units
        for weekIndex in [0, 7] {
            let isDeload = weekIndex == 7
            for day in program.days {
                let session = try SessionBuilder.build(
                    program: program,
                    weekIndex: weekIndex,
                    day: day,
                    exercises: BundledCatalog.byID(),
                    history: [:],
                    settings: settings,
                    id: Fixtures.workoutID,
                    device: Fixtures.deviceID,
                    now: Fixtures.now
                )
                #expect(session.isDeload == isDeload)
                #expect(session.exercises.map(\.slotID) == day.slots.map(\.id))
                for (exercise, slot) in zip(session.exercises, day.slots) {
                    let working = exercise.sets.count { $0.kind == .working }
                    #expect(working == (isDeload ? max(1, slot.sets - 1) : slot.sets), "\(day.tag) \(exercise.name)")
                    #expect(exercise.sets.count == working + slot.dropSets, "\(day.tag) \(exercise.name)")
                    // Week 1 lifts the slot's own start load; every later load is a whole number of steps.
                    #expect(isDeload || exercise.targetLoad == slot.startLoad, "\(day.tag) \(exercise.name)")
                    #expect(exercise.sets.allSatisfy { $0.weight.rounded(toStep: exercise.step) == $0.weight })
                }
            }
        }
    }
}
