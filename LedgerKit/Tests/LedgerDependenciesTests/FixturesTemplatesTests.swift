import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// `Fixtures.defaultProgram`: the program onboarding saves (F08), as the generator writes it, and how it
/// stands beside `Fixtures.seedProgram`, so the two fixtures other features test against cannot drift apart
/// unnoticed.
@Suite("Fixtures · default program", .timeLimit(.minutes(1)))
struct FixturesTemplatesTests {
    private func civil(_ year: Int, _ month: Int, _ day: Int) throws -> CivilDate {
        try #require(CivilDate(year: year, month: month, day: day))
    }

    @Test("The default program is the generator's: both, four days, in pounds, from the Monday of now's week")
    func defaultProgram_isTheGenerators() throws {
        let program = try Fixtures.defaultProgram()
        var number = 1000
        let generated = try ProgramTemplates.program(
            ProgramTemplates.Request(goal: .both, days: .four, units: .lb, startDate: civil(2026, 9, 14)),
            catalog: ExerciseCatalog.seed(),
            id: Fixtures.defaultProgramID,
            newID: {
                number += 1
                return Fixtures.uuid(number)
            }
        )
        #expect(program == generated)
        #expect(program.isActive && program.goal == .both && program.daysPerWeek == 4)
        #expect(program.days.first?.slots.first?.startLoad == .pounds(45))
        // `now` is in its first week.
        let weeks = WeekCalendar(startDate: program.startDate, weekStart: .monday, calendar: Fixtures.calendar)
        #expect(weeks.weekIndex(for: Fixtures.now) == 0)
    }

    @Test("A start date given is the program's, and changes nothing else")
    func defaultProgram_startDate_isTheOneGiven() throws {
        let august = try civil(2026, 8, 17)
        var moved = try Fixtures.defaultProgram()
        moved.startDate = august
        #expect(try Fixtures.defaultProgram(startDate: august) == moved)
    }

    @Test("The default program differs from the seed program only in its loads, its ids and its start")
    func defaultProgram_differsFromSeedProgram_onlyInLoadsIdsAndStart() throws {
        let seed = try Fixtures.seedProgram()
        let program = try Fixtures.defaultProgram()
        #expect(program.name == seed.name)
        #expect(program.goal == seed.goal && program.daysPerWeek == seed.daysPerWeek)
        #expect(program.isActive == seed.isActive)
        #expect(program.days.map(\.name) == seed.days.map(\.name))
        #expect(program.days.map(\.tag) == seed.days.map(\.tag))
        // The same slots, once each takes the seed's id and load.
        #expect(program.days.map(\.slots.count) == seed.days.map(\.slots.count))
        for (slot, seedSlot) in zip(program.days.flatMap(\.slots), seed.days.flatMap(\.slots)) {
            let aligned = try Slot(
                id: seedSlot.id,
                exerciseID: slot.exerciseID,
                sets: slot.sets,
                reps: slot.reps,
                repsHi: slot.repsHi,
                rpe: slot.rpe.value,
                restSeconds: slot.rest.seconds,
                progression: slot.progression,
                startLoad: seedSlot.startLoad,
                step: slot.step,
                isSupersetWithPrevious: slot.isSupersetWithPrevious,
                dropSets: slot.dropSets,
                misses: slot.misses
            )
            #expect(aligned == seedSlot)
        }
        /// The same weeks, by day tag.
        func schedules(_ program: Program) -> [[Weekday: String]] {
            let tags = Dictionary(uniqueKeysWithValues: program.days.map { ($0.id, $0.tag) })
            return program.weeks.map { week in week.schedule.mapValues { tags[$0] ?? "?" } }
        }
        #expect(schedules(program) == schedules(seed))
        #expect(program.weeks.map(\.isDeload) == seed.weeks.map(\.isDeload))
        // What differs: the id, every child id, the start (four weeks later) and the loads.
        #expect(program.id != seed.id)
        let childIDs = { (program: Program) in
            Set(program.weeks.map(\.id.rawValue) + program.days.map(\.id.rawValue)
                + program.days.flatMap(\.slots).map(\.id.rawValue))
        }
        #expect(childIDs(program).isDisjoint(with: childIDs(seed)))
        #expect(try program.startDate == civil(2026, 9, 14) && seed.startDate == civil(2026, 8, 17))
        #expect(seed.days.first?.slots.first?.startLoad == .pounds(180))
    }

    @Test("Saved to stores holding the catalog, the default program reads back equal")
    func defaultProgram_savesAndReadsBack() async throws {
        let stores = try InMemoryStores(seed: InMemoryStores.Seed(catalog: ExerciseCatalog.seed()))
        let program = try Fixtures.defaultProgram()
        try await stores.programs.save(program)
        #expect(try await stores.programs.active() == program)
    }

    @Test("A seed holding the default program names no exercise the catalog lacks")
    func defaultProgram_inASeed_missesNoExercise() throws {
        let seed = try InMemoryStores.Seed(catalog: ExerciseCatalog.seed(), programs: [Fixtures.defaultProgram()])
        #expect(seed.missingExercises.isEmpty)
    }
}
