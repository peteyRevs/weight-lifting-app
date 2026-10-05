import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F08 S1, G2 round 1: `Fixtures.defaultProgram(startDate:)` against what its doc comment promises and against
/// the generator it is built by.
@Suite("Adversarial F08 S1 · the default-program fixture", .timeLimit(.minutes(1)))
struct FixturesTemplatesAdversarialTests {
    static func monday() throws -> CivilDate {
        try #require(CivilDate(year: 2026, month: 9, day: 14))
    }

    /// A block with the three things the fixture's doc comment lets differ from `seedProgram` taken out: ids
    /// (days by position), the start date and start loads.
    static func comparable(_ program: Program) -> [String] {
        let position = Dictionary(zip(program.days.map(\.id), program.days.indices)) { first, _ in first }
        let goal = program.goal?.rawValue ?? "nil"
        let dayCount = program.daysPerWeek.map(String.init) ?? "nil"
        var lines = ["\(program.name)|\(goal)|\(dayCount)|\(program.isActive)"]
        for week in program.weeks {
            let entries: [String] = week.schedule.sorted { $0.key < $1.key }.map { entry in
                "\(entry.key.rawValue):\(position[entry.value] ?? -1)"
            }
            lines.append("week \(week.index) deload \(week.isDeload) \(entries.joined(separator: ","))")
        }
        for day in program.days {
            lines.append("day \(day.name)|\(day.tag)")
            lines += day.slots.map { slot in
                let scheme = "\(slot.sets)×\(slot.reps) hi \(slot.repsHi) RPE \(slot.rpe.value) \(slot.rest.seconds) s"
                let step = slot.step.map { "step \($0.pounds) lb" } ?? "no step"
                let missed = slot.misses.sorted()
                let flags = "superset \(slot.isSupersetWithPrevious) drop \(slot.dropSets) misses \(missed)"
                return "\(slot.exerciseID.rawValue) \(scheme) \(slot.progression.rawValue) \(step) \(flags)"
            }
        }
        return lines
    }

    @Test("The default is the generator's both × four block in pounds for the week of `now`, ids from 1001")
    func defaultProgram_isTheGeneratorsOutput() throws {
        var next = 1000
        let generated = try ProgramTemplates.program(
            ProgramTemplates.Request(goal: .both, days: .four, units: .lb, startDate: Self.monday()),
            catalog: ExerciseCatalog.seed(),
            id: Fixtures.defaultProgramID
        ) {
            next += 1
            return Fixtures.uuid(next)
        }
        #expect(try Fixtures.defaultProgram() == generated)
        #expect(try Fixtures.defaultProgram(startDate: nil) == generated)
        #expect(try Fixtures.defaultProgram(startDate: Self.monday()) == generated)
        #expect(next == 1028)
    }

    @Test("What the doc comment says of it: both, four days, active, its own id, Bench at 45 lb, week 1 holds `now`")
    func defaultProgram_keepsItsPromises() throws {
        let program = try Fixtures.defaultProgram()
        #expect(program.id == Fixtures.defaultProgramID && program.id != Fixtures.programID)
        #expect(program.goal == .both && program.daysPerWeek == 4 && program.isActive)
        #expect(program.startDate == CivilDate(year: 2026, month: 9, day: 14))
        #expect(program.startDate.weekday == Fixtures.settingsLb.weekStart)
        let bench = try #require(program.days.first?.slots.first)
        #expect(bench.exerciseID == Fixtures.CatalogID.benchPress && bench.startLoad == .pounds(45))
        #expect(try Fixtures.seedProgram().days[0].slots[0].startLoad == .pounds(180))
        let weeks = WeekCalendar(
            startDate: program.startDate, weekStart: Fixtures.settingsLb.weekStart, calendar: Fixtures.calendar
        )
        #expect(weeks.weekIndex(for: Fixtures.now) == 0)
        #expect(weeks.scheduledDay(on: Fixtures.now, in: program) == program.days[1].id)
    }

    @Test("Its ids are uuid(1001) onward in the generator's order: eight weeks, then each day and its slots")
    func defaultProgram_idsAreAsDocumented() throws {
        let program = try Fixtures.defaultProgram()
        #expect(program.weeks.map(\.id.rawValue) == (1001 ... 1008).map(Fixtures.uuid))
        // Days of 5, 4, 4 and 3 slots: 1009 + 5, 1015 + 4, 1020 + 4, 1025 + 3.
        #expect(program.days.map(\.id.rawValue) == [1009, 1015, 1020, 1025].map(Fixtures.uuid))
        let slots = program.days.map { $0.slots.map(\.id.rawValue) }
        #expect(slots == [
            (1010 ... 1014).map(Fixtures.uuid), (1016 ... 1019).map(Fixtures.uuid),
            (1021 ... 1024).map(Fixtures.uuid), (1026 ... 1028).map(Fixtures.uuid)
        ])
    }

    @Test("It differs from `seedProgram` in three ways only: start loads, start date and ids")
    func defaultProgram_differsFromSeedProgramInThreeWaysOnly() throws {
        let fixture = try Fixtures.defaultProgram()
        let seed = try Fixtures.seedProgram()
        #expect(Self.comparable(fixture) == Self.comparable(seed))
    }

    @Test("The two program fixtures share no id, so one store holds both")
    func defaultProgram_sharesNoIDWithSeedProgram() async throws {
        let fixture = try Fixtures.defaultProgram()
        let seed = try Fixtures.seedProgram()
        func ids(_ program: Program) -> Set<UUID> {
            let slots = program.days.flatMap(\.slots).map(\.id.rawValue)
            return Set([program.id.rawValue] + program.weeks.map(\.id.rawValue) + program.days
                .map(\.id.rawValue) + slots)
        }
        #expect(ids(fixture).count == 29 && ids(fixture).isDisjoint(with: ids(seed)))
        let stores = try InMemoryStores(seed: .preview())
        #expect(try await stores.programs.active() == seed)
        try await stores.programs.save(fixture)
        #expect(try await stores.programs.active() == fixture)
        try await stores.programs.setActive(seed.id)
        #expect(try await stores.programs.active() == seed)
    }

    @Test(
        "A start date is used as given, whatever its weekday, and changes nothing else",
        arguments: [(2026, 10, 1), (2026, 9, 13), (2028, 2, 29), (2027, 1, 1), (1, 1, 1), (9999, 12, 31)]
    )
    func defaultProgram_startDateIsUsedAsGiven(year: Int, month: Int, day: Int) throws {
        let start = try #require(CivilDate(year: year, month: month, day: day))
        var program = try Fixtures.defaultProgram(startDate: start)
        #expect(program.startDate == start)
        program.startDate = try Self.monday()
        #expect(try program == Fixtures.defaultProgram())
    }

    @Test("It is a block the rules can run: Upper A of week 1 opens with Bench 5 × 5 at 45 lb, week 8 at 4 × 5")
    func defaultProgram_buildsASession() throws {
        let program = try Fixtures.defaultProgram()
        let catalog = try ExerciseCatalog.seed()
        func session(week: Int) throws -> WorkoutState {
            try SessionBuilder.build(
                program: program,
                weekIndex: week,
                day: program.days[0],
                exercises: Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) }),
                history: [:],
                settings: Fixtures.settingsLb,
                id: Fixtures.sessionID,
                device: Fixtures.deviceID,
                now: Fixtures.now
            )
        }
        let first = try #require(session(week: 0).exercises.first)
        #expect(first.name == "Barbell Bench Press" && first.targetSets == 5 && first.targetReps == 5)
        #expect(first.targetLoad == .pounds(45) && first.step == .pounds(5))
        // Week 8: 45 + 5 × 7 = 80 lb, 85 % is 68, to the nearest 5 is 70; one set fewer.
        let deload = try #require(session(week: 7).exercises.first)
        #expect(deload.targetLoad == .pounds(70) && deload.targetSets == 4 && deload.rpe.value == 6)
        #expect(program.weeks[7].schedule.count == 3 && program.weeks[7].schedule[.saturday] == nil)
    }
}
