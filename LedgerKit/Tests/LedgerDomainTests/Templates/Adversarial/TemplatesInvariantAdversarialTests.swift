import Foundation
@testable import LedgerDomain
import Testing

/// F08 S1, G2 round 1: what a store, Today and the builder rely on in any generated block, checked on all 32
/// inputs without reference to which template it is.
@Suite("Adversarial F08 S1 · structural invariants of a generated block", .tags(.domain))
struct TemplatesInvariantAdversarialTests {
    typealias Brief = BriefTemplates

    @Test("Every week, day and slot id is its own, and none is the program's", arguments: Brief.Case.all)
    func ids_areUnique(_ input: Brief.Case) throws {
        let program = try Brief.program(input)
        let slots = program.days.flatMap(\.slots)
        let ids = program.weeks.map(\.id.rawValue) + program.days.map(\.id.rawValue) + slots.map(\.id.rawValue)
        #expect(Set(ids).count == ids.count, "\(input)")
        #expect(ids.count == 8 + input.days.rawValue + slots.count, "\(input)")
        #expect(!ids.contains(program.id.rawValue), "\(input)")
    }

    @Test("Every schedule entry names a day of the block, and every day is trained", arguments: Brief.Case.all)
    func schedule_namesOnlyDaysThatExist(_ input: Brief.Case) throws {
        let program = try Brief.program(input)
        let dayIDs = Set(program.days.map(\.id))
        for week in program.weeks {
            #expect(Set(week.schedule.values).isSubset(of: dayIDs), "\(input), week \(week.index + 1)")
            #expect(Set(week.schedule.values).count == week.schedule.count, "\(input): a day twice in a week")
        }
        #expect(Set(program.weeks.flatMap(\.schedule.values)) == dayIDs, "\(input)")
        #expect(program.weeks.prefix(7).allSatisfy { $0.schedule.count == input.days.rawValue }, "\(input)")
    }

    @Test("Every slot's exercise is a catalog exercise, never a custom one", arguments: Brief.Case.all)
    func slots_nameCatalogExercises(_ input: Brief.Case) throws {
        let exercises = try Brief.byID(Brief.catalog())
        for slot in try Brief.program(input).days.flatMap(\.slots) {
            let exercise = try #require(exercises[slot.exerciseID], "\(input): \(slot.exerciseID.rawValue)")
            #expect(!exercise.isCustom, "\(input): \(exercise.name)")
        }
    }

    @Test(
        "No day is empty, starts with a superset-with-previous slot, or repeats an exercise",
        arguments: Brief.Case.all
    )
    func days_areWellFormed(_ input: Brief.Case) throws {
        for day in try Brief.program(input).days {
            let first = try #require(day.slots.first, "\(input): \(day.name) has no slots")
            #expect(!first.isSupersetWithPrevious, "\(input): \(day.name)")
            #expect(Set(day.slots.map(\.exerciseID)).count == day.slots.count, "\(input): \(day.name)")
            #expect(day.shortTitle == day.name.components(separatedBy: " — ")[0], "\(input): \(day.name)")
        }
    }

    @Test(
        "The block passes its own validation again, slot by slot and whole, and survives JSON",
        arguments: Brief.Case.all
    )
    func program_revalidates(_ input: Brief.Case) throws {
        let program = try Brief.program(input)
        let days = try program.days.map { day in
            try DayTemplate(id: day.id, name: day.name, tag: day.tag, slots: day.slots.map(Self.rebuilt))
        }
        let rebuilt = try Program(
            id: program.id,
            name: program.name,
            startDate: program.startDate,
            weeks: program.weeks,
            days: days,
            goal: program.goal,
            daysPerWeek: program.daysPerWeek,
            isActive: program.isActive
        )
        #expect(rebuilt == program, "\(input)")
        #expect(try Adversarial.roundTrip(program) == program, "\(input)")
    }

    static func rebuilt(_ slot: Slot) throws -> Slot {
        try Slot(
            id: slot.id,
            exerciseID: slot.exerciseID,
            sets: slot.sets,
            reps: slot.reps,
            repsHi: slot.repsHi,
            rpe: slot.rpe.value,
            restSeconds: slot.rest.seconds,
            progression: slot.progression,
            startLoad: slot.startLoad,
            step: slot.step,
            isSupersetWithPrevious: slot.isSupersetWithPrevious,
            dropSets: slot.dropSets,
            misses: slot.misses
        )
    }

    @Test("Exactly one week is a deload, and it is the last of eight contiguous weeks", arguments: Brief.Case.all)
    func deload_isTheLastWeekOnly(_ input: Brief.Case) throws {
        let program = try Brief.program(input)
        #expect(program.weeks.map(\.index) == Array(0 ..< 8), "\(input)")
        #expect(program.weeks.map(\.isDeload) == [false, false, false, false, false, false, false, true], "\(input)")
    }

    @Test("Criterion 7: every slot is inside spec §7.1's limits", arguments: Brief.Case.all)
    func slots_areInsideSpec71(_ input: Brief.Case) throws {
        for slot in try Brief.program(input).days.flatMap(\.slots) {
            #expect((1 ... 12).contains(slot.sets), "\(input)")
            #expect((1 ... 30).contains(slot.reps), "\(input)")
            #expect((2 ... 40).contains(slot.repsHi) && slot.repsHi > slot.reps, "\(input)")
            let doubled = slot.rpe.value * 2
            #expect((5 ... 10).contains(slot.rpe.value) && doubled == decimalRounded(doubled), "\(input)")
            #expect((30 ... 300).contains(slot.rest.seconds) && slot.rest.seconds % 15 == 0, "\(input)")
            #expect((0 ... 1).contains(slot.dropSets), "\(input)")
            #expect(slot.misses.isEmpty, "\(input): a new block has no misses")
        }
    }
}

// MARK: - Start loads (amendments 2 and 3, decisions #21, #22 and #24)

extension TemplatesInvariantAdversarialTests {
    @Test(
        "A slot's start load is its catalog exercise's for the unit, copied in; its step is nil",
        arguments: Brief.Case.all
    )
    func startLoads_areTheCatalogs(_ input: Brief.Case) throws {
        let exercises = try Brief.byID(Brief.catalog())
        for slot in try Brief.program(input).days.flatMap(\.slots) {
            let exercise = try #require(exercises[slot.exerciseID])
            #expect(slot.startLoad == exercise.startLoad(in: input.units), "\(input): \(exercise.name)")
            #expect(slot.startLoad == exercise.defaultStartLoad[input.units], "\(input): \(exercise.name)")
            #expect(slot.step == nil, "\(input): \(exercise.name)")
        }
    }

    @Test(
        "Criterion 8, decision #22: every start load is a positive multiple of the unit's step",
        arguments: Brief.Case.all
    )
    func startLoads_arePositiveMultiplesOfTheStep(_ input: Brief.Case) throws {
        let exercises = try Brief.byID(Brief.catalog())
        for slot in try Brief.program(input).days.flatMap(\.slots) {
            let exercise = try #require(exercises[slot.exerciseID])
            let row = try #require(Brief.catalogRows[exercise.name], "\(input): \(exercise.name)")
            let load = try #require(slot.startLoad, "\(input): \(exercise.name) has no start load")
            let steps = load.value(in: input.units) / Brief.step(row.equipment, in: input.units)
            #expect(
                steps > 0 && steps == decimalRounded(steps),
                "\(input): \(exercise.name) \(load.value(in: input.units))"
            )
            #expect(exercise.equipment == row.equipment, "\(input): \(exercise.name)")
        }
    }

    @Test(
        "Decision #21 by hand: each template exercise starts at the policy's load in each unit",
        arguments: Brief.Case.all
    )
    func startLoads_areDecision21s(_ input: Brief.Case) throws {
        let exercises = try Brief.byID(Brief.catalog())
        for slot in try Brief.program(input).days.flatMap(\.slots) {
            let name = try #require(exercises[slot.exerciseID]).name
            let row = try #require(Brief.catalogRows[name], "\(input): \(name)")
            #expect(slot.startLoad == Brief.weight(row.load(in: input.units), in: input.units), "\(input): \(name)")
        }
    }

    @Test("Amendment 2: Bench starts at 45 lb and 20 kg, never the prototype's 180; the pull-up is the weighted one")
    func startLoads_benchAndPullUp() throws {
        let exercises = try Brief.byID(Brief.catalog())
        for units in Units.allCases {
            let program = try Brief.program(Brief.Case(goal: .both, days: .four, units: units))
            let bench = try #require(program.days[0].slots.first)
            let pullUp = try #require(program.days[2].slots.first)
            #expect(bench.startLoad == (units == .lb ? .pounds(45) : .kilograms(20)))
            #expect(pullUp.startLoad == (units == .lb ? .pounds(10) : .kilograms(5)))
            #expect(exercises[pullUp.exerciseID]?.name == "Weighted Pull-Up")
        }
    }

    @Test("Units change loads and nothing else: the lb and kg blocks differ only in start loads")
    func units_changeOnlyStartLoads() throws {
        for goal in TrainingGoal.allCases {
            for days in DaysPerWeek.allCases {
                let inPounds = try Brief.program(Brief.Case(goal: goal, days: days, units: .lb))
                let inKilograms = try Brief.program(Brief.Case(goal: goal, days: days, units: .kg))
                #expect(inPounds != inKilograms, "\(goal) × \(days)")
                #expect(Self.withoutLoads(inPounds) == Self.withoutLoads(inKilograms), "\(goal) × \(days)")
            }
        }
    }

    /// `program` with every slot's start load cleared.
    static func withoutLoads(_ program: Program) -> Program {
        var copy = program
        for day in copy.days.indices {
            for slot in copy.days[day].slots.indices {
                copy.days[day].slots[slot].startLoad = nil
            }
        }
        return copy
    }
}
