import Foundation
import GRDB
import LedgerDomain
import LedgerFakes
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F08 S1, G2 round 1: every block `ProgramTemplates` writes, saved to the GRDB repository and to LedgerFakes'
/// linked in-memory stores side by side. Both must hand back exactly what was generated.
@Suite("Adversarial F08 S1 · generated blocks in the stores", .tags(.persistence), .timeLimit(.minutes(2)))
struct TemplateProgramStoreAdversarialTests {
    /// One of the 32 inputs.
    struct Input: Sendable, CustomStringConvertible {
        var goal: TrainingGoal
        var days: DaysPerWeek
        var units: Units

        var description: String {
            "\(goal.rawValue) × \(days.rawValue) days in \(units.rawValue)"
        }

        static let all: [Input] = TrainingGoal.allCases.flatMap { goal in
            DaysPerWeek.allCases.flatMap { days in Units.allCases.map { Input(goal: goal, days: days, units: $0) } }
        }
    }

    /// Both kinds of store, seeded with the bundled catalog as a launch seeds it.
    struct Stores {
        let stored: Repositories
        let fake: InMemoryStores

        init(seeded: Bool = true) async throws {
            stored = try Repositories()
            let catalog = try seeded ? ExerciseCatalog.seed() : []
            if seeded {
                try await stored.exercises.seedIfNeeded(catalog, version: ExerciseCatalog.version)
            }
            fake = InMemoryStores(seed: InMemoryStores.Seed(catalog: catalog))
        }
    }

    /// The block for `input` with program id `uuid(number)` and child ids `uuid(number × 1000 + 1)` onward.
    static func program(_ input: Input, catalog: [Exercise], number: Int = 7) throws -> Program {
        var next = number * 1000
        let start = try #require(CivilDate(year: 2026, month: 9, day: 14))
        return try ProgramTemplates.program(
            ProgramTemplates.Request(goal: input.goal, days: input.days, units: input.units, startDate: start),
            catalog: catalog,
            id: ProgramID(Fixtures.uuid(number))
        ) {
            next += 1
            return Fixtures.uuid(next)
        }
    }

    static let liveCounts = """
    SELECT (SELECT COUNT(*) FROM program WHERE deleted_at IS NULL) || ' '
        || (SELECT COUNT(*) FROM program_week WHERE deleted_at IS NULL) || ' '
        || (SELECT COUNT(*) FROM day_template WHERE deleted_at IS NULL) || ' '
        || (SELECT COUNT(*) FROM slot WHERE deleted_at IS NULL) || ' '
        || (SELECT COUNT(*) FROM slot_miss WHERE deleted_at IS NULL)
    """

    @Test("Every generated block loads back from GRDB and from the fake exactly as generated", arguments: Input.all)
    func everyTemplate_roundTripsThroughBothStores(_ input: Input) async throws {
        let stores = try await Stores()
        let program = try Self.program(input, catalog: ExerciseCatalog.seed())
        try await stores.stored.programs.save(program)
        try await stores.fake.programs.save(program)
        let fromDatabase = try await stores.stored.programs.active()
        let fromFake = try await stores.fake.programs.active()
        #expect(fromDatabase == program, "\(input)")
        #expect(fromFake == program, "\(input)")
        #expect(fromDatabase == fromFake, "\(input)")
        #expect(try await stores.stored.programs.program(id: program.id) == program, "\(input)")
        let slots = program.days.flatMap(\.slots).count
        #expect(try await stores.stored.texts(Self.liveCounts) == ["1 8 \(input.days.rawValue) \(slots) 0"])
    }

    @Test(
        "A block written from the stored catalog, in the store's order, is the one written from the bundle",
        arguments: Input.all
    )
    func storedCatalog_givesTheSameBlock(_ input: Input) async throws {
        let stores = try await Stores()
        let bundled = try ExerciseCatalog.seed()
        let fromDatabase = try await stores.stored.exercises.all()
        let fromFake = try await stores.fake.exercises.all()
        #expect(fromDatabase.map(\.id) != bundled.map(\.id), "the store returns name order, not file order")
        let expected = try Self.program(input, catalog: bundled)
        #expect(try Self.program(input, catalog: fromDatabase) == expected, "\(input)")
        #expect(try Self.program(input, catalog: fromFake) == expected, "\(input)")
    }

    @Test("A lifter's own exercises named like template ones change nothing, and the block still saves")
    func customNamesakesInTheStore_areIgnored() async throws {
        let stores = try await Stores()
        let names = ["Barbell Bench Press", "Deadlift", "Weighted Pull-Up", "Back Squat", "Barbell Curl"]
        for (offset, name) in names.enumerated() {
            let custom = Exercise(
                id: ExerciseID(Fixtures.uuid(offset + 1)), // sorts before every catalog id of the same name
                name: name,
                shortName: "MINE",
                equipment: .machine,
                primaryMuscle: .core,
                pattern: .core,
                defaultStartLoad: [.lb: .pounds(995), .kg: .kilograms(450)],
                isCustom: true
            )
            try await stores.stored.exercises.save(custom)
            try await stores.fake.exercises.save(custom)
        }
        for input in Input.all {
            let expected = try Self.program(input, catalog: ExerciseCatalog.seed())
            let fromDatabase = try await Self.program(input, catalog: stores.stored.exercises.all())
            let fromFake = try await Self.program(input, catalog: stores.fake.exercises.all())
            #expect(fromDatabase == expected && fromFake == expected, "\(input)")
        }
        let program = try await Self.program(Input.all[0], catalog: stores.stored.exercises.all())
        try await stores.stored.programs.save(program)
        #expect(try await stores.stored.programs.active() == program)
    }
}

// MARK: - Rows, side by side, and before the catalog

extension TemplateProgramStoreAdversarialTests {
    @Test("All sixteen pound blocks live side by side: the last saved is the active one, the rest load inactive")
    func sixteenBlocks_sideBySide() async throws {
        let stores = try await Stores()
        let catalog = try ExerciseCatalog.seed()
        let inputs = Input.all.filter { $0.units == .lb }
        var saved: [Program] = []
        for (offset, input) in inputs.enumerated() {
            let program = try Self.program(input, catalog: catalog, number: 100 + offset)
            try await stores.stored.programs.save(program)
            try await stores.fake.programs.save(program)
            saved.append(program)
        }
        let last = try #require(saved.last)
        #expect(try await stores.stored.programs.active() == last)
        #expect(try await stores.fake.programs.active() == last)
        for var program in saved.dropLast() {
            program.isActive = false
            #expect(try await stores.stored.programs.program(id: program.id) == program, "\(program.name)")
        }
        // 4 goals × (3 + 4 + 5 + 6) days, and 4 × (15 + 16 + 24 + 24) slots.
        #expect(try await stores.stored.texts(Self.liveCounts) == ["16 128 72 316 0"])
    }

    @Test("The row is what the brief says: civil start, goal, day count, active; exact load, no step")
    func columns_holdTheGeneratedValues() async throws {
        let stores = try await Stores()
        let program = try Self.program(Input(goal: .both, days: .four, units: .lb), catalog: ExerciseCatalog.seed())
        try await stores.stored.programs.save(program)
        let columns = "name || '|' || start_date || '|' || goal || '|' || days_per_week || '|' || is_active"
        let root = "SELECT \(columns) FROM program"
        #expect(try await stores.stored.texts(root) == ["Upper / Lower|2026-09-14|both|4|1"])
        // Bench: 45 lb is 20,411.65665 g, an exact count of 10⁻⁷ g (ADR-007).
        let bench = "SELECT quote(start_load_e7g) || ' ' || quote(step_e7g) FROM slot WHERE id = ?"
        let slot = program.days[0].slots[0]
        #expect(try await stores.stored.texts(bench, [ColumnCodec.text(slot.id)]) == ["204116566500 NULL"])
        let deload = "SELECT quote(sat) || ' ' || is_deload FROM program_week ORDER BY week_index"
        let saturday = "'\(ColumnCodec.text(program.days[3].id))' 0"
        #expect(try await stores.stored.texts(deload) == Array(repeating: saturday, count: 7) + ["NULL 1"])
    }

    @Test(
        "Decision #28: before the catalog is seeded both stores refuse the block, naming its first exercise",
        arguments: DaysPerWeek.allCases
    )
    func unseededStore_refusesTheBlock(_ days: DaysPerWeek) async throws {
        let stores = try await Stores(seeded: false)
        let input = Input(goal: .both, days: days, units: .lb)
        let program = try Self.program(input, catalog: ExerciseCatalog.seed())
        let first = try #require(program.days.first?.slots.first?.exerciseID)
        let expected = RepositoryError.unknownExercise("exercise \(first.rawValue.uuidString)")
        await #expect(throws: expected) { try await stores.stored.programs.save(program) }
        await #expect(throws: expected) { try await stores.fake.programs.save(program) }
        #expect(try await stores.stored.programs.active() == nil)
        #expect(try await stores.fake.programs.active() == nil)
        #expect(try await stores.stored.texts(Self.liveCounts) == ["0 0 0 0 0"])
        // And the generator itself, handed the empty stored catalog, says which exercise it could not find.
        let stored = try await stores.stored.exercises.all()
        #expect(throws: ProgramTemplateError.self) { try Self.program(input, catalog: stored) }
    }

    @Test("Fixtures.defaultProgram and Fixtures.seedProgram save into one database, either order, and load back")
    func fixtures_saveSideBySide() async throws {
        let fixture = try Fixtures.defaultProgram()
        let seed = try Fixtures.seedProgram()
        for order in [[fixture, seed], [seed, fixture]] {
            let stores = try await Stores()
            for program in order {
                try await stores.stored.programs.save(program)
                try await stores.fake.programs.save(program)
            }
            let last = try #require(order.last)
            #expect(try await stores.stored.programs.active() == last)
            #expect(try await stores.fake.programs.active() == last)
            #expect(try await stores.stored.texts(Self.liveCounts) == ["2 16 8 32 0"])
        }
    }
}

// MARK: - A block in use

extension TemplateProgramStoreAdversarialTests {
    /// `workout` with every set done as prescribed and finished an hour after it started.
    static func finished(_ workout: WorkoutState) -> WorkoutState {
        var done = workout
        var tick = 0
        for exercise in done.exercises.indices {
            for set in done.exercises[exercise].sets.indices {
                tick += 1
                done.exercises[exercise].sets[set].doneAt = workout.startedAt.addingTimeInterval(Double(tick) * 120)
            }
        }
        done.cursor = nil
        done.rest = nil
        done.phase = .finished
        done.endedAt = workout.startedAt.addingTimeInterval(3600)
        return done
    }

    /// Every scheduled day of every week of `program`, built by `SessionBuilder` and trained as prescribed.
    static func wholeBlock(_ program: Program, units: Units) throws -> [WorkoutState] {
        let catalog = try ExerciseCatalog.seed()
        let exercises = Dictionary(catalog.map { ($0.id, $0) }) { first, _ in first }
        var settings = Settings.default
        settings.units = units
        var workouts: [WorkoutState] = []
        for week in program.weeks {
            for (weekday, dayID) in week.schedule.sorted(by: { $0.key < $1.key }) {
                let day = try #require(program.days.first { $0.id == dayID })
                let offset = Double(week.index * 7 + weekday.rawValue - 1) * 86400 + 7 * 3600
                try workouts.append(finished(SessionBuilder.build(
                    program: program,
                    weekIndex: week.index,
                    day: day,
                    exercises: exercises,
                    history: [:],
                    settings: settings,
                    id: WorkoutID(Fixtures.uuid(0x0800_0000 + week.index * 16 + weekday.rawValue)),
                    device: Fixtures.deviceID,
                    now: Fixtures.date(2026, 9, 14).addingTimeInterval(offset)
                )))
            }
        }
        return workouts
    }

    @Test(
        "A whole block trained as prescribed is stored by both stores, every weight exact, and reads back alike",
        arguments: [
            Input(goal: .both, days: .four, units: .lb), Input(goal: .hypertrophy, days: .six, units: .kg),
            Input(goal: .strength, days: .three, units: .kg), Input(goal: .consistency, days: .five, units: .lb)
        ]
    )
    func wholeBlock_materialisesInBothStores(_ input: Input) async throws {
        let stores = try await Stores()
        let program = try Self.program(input, catalog: ExerciseCatalog.seed())
        try await stores.stored.programs.save(program)
        try await stores.fake.programs.save(program)
        let workouts = try Self.wholeBlock(program, units: input.units)
        #expect(workouts.count == 8 * input.days.rawValue - (input.days == .four ? 1 : 0), "\(input)")
        for workout in workouts {
            try await stores.stored.workouts.materialize(workout, slotUpdates: [])
            try await stores.fake.workouts.materialize(workout, slotUpdates: [])
        }
        let fromDatabase = try await stores.stored.workouts.recent(limit: 100)
        let fromFake = try await stores.fake.workouts.recent(limit: 100)
        #expect(fromDatabase.count == workouts.count, "\(input)")
        #expect(fromDatabase == fromFake, "\(input)")
        #expect(Set(fromDatabase.map(\.id)) == Set(workouts.map(\.id)), "\(input)")
        // Training the block changes nothing in it: no slot was missed.
        #expect(try await stores.stored.programs.active() == program, "\(input)")
        #expect(try await stores.fake.programs.active() == program, "\(input)")
    }
}
