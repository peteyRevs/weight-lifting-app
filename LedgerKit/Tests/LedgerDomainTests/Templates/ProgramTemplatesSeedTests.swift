import Foundation
@testable import LedgerDomain
import Testing

/// The canonical seed (F08 criterion 6, as amended): `both` on the 4-day split is spec §6.4 in every column
/// except load and step, with §6.4's schedule.
@Suite("ProgramTemplates · spec §6.4 seed", .tags(.domain))
struct ProgramTemplatesSeedTests {
    private func seed(_ units: Units = .lb) throws -> Program {
        try TemplateCase(goal: .both, days: .four, units: units).program()
    }

    @Test("The seed is Upper / Lower: four days of 5, 4, 4 and 3 slots, the table's 16 rows and no more")
    func program_bothFourDay_hasTheTablesDaysAndRowCount() throws {
        let program = try seed()
        #expect(program.name == "Upper / Lower")
        #expect(program.days.map(\.name) == [
            "Upper A — Push focus", "Lower A — Squat focus", "Upper B — Pull focus", "Lower B — Hinge focus"
        ])
        #expect(program.days.map(\.tag) == ["UA", "LA", "UB", "LB"])
        #expect(program.days.map(\.slots.count) == [5, 4, 4, 3])
        #expect(TemplateOracle.seedRows.count == 16)
        #expect(Set(TemplateOracle.seedRows.map(\.description)).count == 16)
    }

    @Test(
        "Criterion 6: a slot equals its spec §6.4 row in every column but load and step",
        arguments: TemplateOracle.seedRows
    )
    func program_bothFourDay_matchesSpec64_exceptLoad(row: TemplateOracle.SeedRow) throws {
        let catalog = try BundledCatalog.byID()
        for units in Units.allCases {
            let day = try #require(try seed(units).days.first { $0.tag == row.tag })
            let slot = try #require(day.slots.indices.contains(row.number - 1) ? day.slots[row.number - 1] : nil)
            let exercise = try #require(catalog[slot.exerciseID])
            #expect(exercise.name == row.exercise)
            #expect(TemplateOracle.Scheme(slot) == row.scheme)
            #expect(slot.repsHi == slot.reps + 2)
            #expect(slot.isSupersetWithPrevious == row.isSuperset)
            #expect(slot.dropSets == row.dropSets)
            #expect(slot.misses.isEmpty)
            // The load is the catalog's, copied into the slot (decisions #21 and #24); the step stays unset.
            #expect(slot.startLoad == exercise.startLoad(in: units), "\(units)")
            #expect(slot.step == nil)
        }
    }

    @Test("The seed's loads are the catalog's beginner defaults, not the prototype's (decision #21)")
    func program_bothFourDay_benchStartsAtTheEmptyBar() throws {
        let bench = try #require(try seed(.lb).days.first?.slots.first)
        #expect(bench.startLoad == .pounds(45))
        #expect(try seed(.kg).days.first?.slots.first?.startLoad == .kilograms(20))
    }

    @Test(
        "Criterion 6: weeks 1–7 run UA, LA, UB, LB on Mon, Wed, Fri, Sat; week 8 drops Saturday, for every goal",
        arguments: TrainingGoal.allCases
    )
    func program_fourDay_scheduleMatchesSeed_includingWeek8(goal: TrainingGoal) throws {
        let program = try TemplateCase(goal: goal, days: .four).program()
        let tags = Dictionary(uniqueKeysWithValues: program.days.map { ($0.id, $0.tag) })
        let schedules = program.weeks.map { week in week.schedule.mapValues { tags[$0] ?? "?" } }
        let full: [Weekday: String] = [.monday: "UA", .wednesday: "LA", .friday: "UB", .saturday: "LB"]
        let deload: [Weekday: String] = [.monday: "UA", .wednesday: "LA", .friday: "UB"]
        #expect(schedules == Array(repeating: full, count: 7) + [deload])
    }

    @Test("Other goals keep the seed's exercises, supersets and drop set", arguments: TrainingGoal.allCases)
    func program_fourDay_everyGoal_keepsExercisesSupersetsAndDropSet(goal: TrainingGoal) throws {
        let seed = try seed()
        let program = try TemplateCase(goal: goal, days: .four).program()
        #expect(program.name == seed.name)
        #expect(program.days.map(\.name) == seed.days.map(\.name))
        #expect(program.days.map(\.tag) == seed.days.map(\.tag))
        let slots = program.days.flatMap(\.slots)
        let seedSlots = seed.days.flatMap(\.slots)
        #expect(slots.map(\.exerciseID) == seedSlots.map(\.exerciseID))
        #expect(slots.map(\.isSupersetWithPrevious) == TemplateOracle.seedRows.map(\.isSuperset))
        #expect(slots.map(\.dropSets) == TemplateOracle.seedRows.map(\.dropSets))
        #expect(slots.map(\.startLoad) == seedSlots.map(\.startLoad))
    }

    @Test("Strength on the 4-day split takes the role table, not the seed's rows")
    func program_strengthFourDay_takesTheRoleTable() throws {
        let program = try TemplateCase(goal: .strength, days: .four).program()
        let schemes = program.days.map { $0.slots.map(TemplateOracle.Scheme.init) }
        let primary = TemplateOracle.Scheme(5, 5, hi: 7, rpe: 8, rest: 180, .linear)
        let secondary = TemplateOracle.Scheme(4, 6, hi: 8, rpe: 8, rest: 150, .linear)
        let accessory = TemplateOracle.Scheme(3, 8, hi: 10, rpe: 8, rest: 90, .linear)
        #expect(schemes == [
            [primary, secondary, secondary, accessory, accessory],
            [primary, secondary, accessory, accessory],
            [primary, secondary, secondary, accessory],
            [primary, secondary, accessory]
        ])
        // The seed's fixed calf raise is the role table's linear accessory here, and still a superset.
        let calfRaise = try #require(program.days.first { $0.tag == "LA" }?.slots.last)
        #expect(calfRaise.progression == .linear && calfRaise.isSupersetWithPrevious)
    }
}
