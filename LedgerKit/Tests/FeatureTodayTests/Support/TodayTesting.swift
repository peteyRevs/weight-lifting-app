@testable import FeatureToday
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// Tags live in the test target, as in every other one (F02 notes: tags in LedgerTestSupport would pull
/// swift-testing into the features, which link it).
extension Tag {
    /// Every FeatureToday suite (layer tag).
    @Tag static var feature: Self
    /// Seeded property-style tests; the case count comes from `LEDGER_PROPERTY_SEED_COUNT`.
    @Tag static var property: Self
    /// Suites that compare against committed reference images.
    @Tag static var snapshot: Self
}

/// Deterministic SplitMix64 generator for property tests (testing-strategy §3 rule 5).
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

/// One property-test case. A failing case names its seed, which is then added as a fixed regression test.
nonisolated struct PropertySeed: Sendable, CustomStringConvertible {
    let value: UInt64

    var description: String {
        "seed \(value)"
    }

    var generator: SeededGenerator {
        SeededGenerator(seed: value)
    }

    /// `LEDGER_PROPERTY_SEED_COUNT` seeds (PR lane 200, nightly 2,000); 200 when unset or invalid.
    static let all: [PropertySeed] = {
        let configured = ProcessInfo.processInfo.environment["LEDGER_PROPERTY_SEED_COUNT"].flatMap(Int.init)
        let count = max(1, configured ?? 200)
        return (0 ..< count).map { PropertySeed(value: UInt64($0) &* 7919 &+ 17) }
    }()
}

/// The brief's worked examples as inputs: spec §6.4's program (`Fixtures.seedProgram()`) re-dated to begin on
/// Monday 2026-09-14, so that `Fixtures.now`, Wednesday 2026-09-16 05:20 UTC, is Lower A's day in week 1.
nonisolated enum TodayFixtures {
    /// The four days of the seed program, by the index of `Program.days`.
    enum DayIndex {
        static let upperA = 0
        static let lowerA = 1
        static let upperB = 2
        static let lowerB = 3
    }

    static func civil(_ year: Int, _ month: Int, _ day: Int) throws -> CivilDate {
        try #require(CivilDate(year: year, month: month, day: day))
    }

    /// The seed program beginning on `start` (Monday 2026-09-14 when nil).
    static func program(startingOn start: CivilDate? = nil) throws -> Program {
        var program = try Fixtures.seedProgram()
        program.startDate = try start ?? civil(2026, 9, 14)
        return program
    }

    /// The bundled catalog by id, decoded once.
    private static let catalog = Result {
        try Dictionary(ExerciseCatalog.seed().map { ($0.id, $0) }) { first, _ in first }
    }

    /// The bundled catalog by id: what the store hands the presentation.
    static func exercises() throws -> [ExerciseID: Exercise] {
        try catalog.get()
    }

    /// A Gregorian calendar in the zone `identifier`.
    static func calendar(in identifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: identifier))
        return calendar
    }

    /// An input for the re-dated seed program at `now`, in UTC and en_US, with the catalog's exercises, pounds
    /// and a Monday week start. Tests change the fields their case is about.
    static func input(
        program: Program?,
        now: Date = Fixtures.now,
        settings: Settings = Fixtures.settingsLb
    ) throws -> TodayInput {
        try TodayInput(
            program: program,
            exercises: exercises(),
            settings: settings,
            now: now,
            calendar: Fixtures.calendar,
            locale: Fixtures.locale
        )
    }

    /// The input of the brief's criterion 1: the program at `now`.
    static func input(now: Date = Fixtures.now) throws -> TodayInput {
        try input(program: program(), now: now)
    }

    /// The live workout `SessionBuilder` builds for day `dayIndex` of `program` in week `weekIndex`, started
    /// at `start`.
    static func liveWorkout(
        _ number: Int,
        of program: Program,
        weekIndex: Int,
        dayIndex: Int,
        startedAt start: Date
    ) throws -> WorkoutState {
        try SessionBuilder.build(
            program: program,
            weekIndex: weekIndex,
            day: program.days[dayIndex],
            exercises: exercises(),
            history: [:],
            settings: Fixtures.settingsLb,
            id: WorkoutID(Fixtures.uuid(number)),
            device: Fixtures.deviceID,
            now: start
        )
    }

    /// `workout` with every set done and finished `seconds` after it started.
    static func finished(_ workout: WorkoutState, after seconds: Int) -> WorkoutState {
        var done = workout
        for exercise in done.exercises.indices {
            for set in done.exercises[exercise].sets.indices {
                done.exercises[exercise].sets[set].doneAt = workout.startedAt
            }
        }
        done.cursor = nil
        done.phase = .finished
        done.endedAt = workout.startedAt.addingTimeInterval(Double(seconds))
        return done
    }

    /// A finished workout that moved exactly `pounds`: one set of that weight, once. `source` ties it to a
    /// program day; nil is an ad-hoc workout.
    static func workout(
        _ number: Int,
        named name: String = "Lower A — Squat focus",
        pounds: Decimal,
        startedAt start: Date,
        seconds: Int = 58 * 60,
        source: WorkoutSource? = nil
    ) throws -> WorkoutState {
        let id = WorkoutID(Fixtures.uuid(number))
        let exercise = try WorkoutExercise(
            id: .derived(from: id, index: 0),
            slotID: nil,
            exerciseID: Fixtures.CatalogID.backSquat,
            originalExerciseID: Fixtures.CatalogID.backSquat,
            name: "Back Squat",
            equipment: .barbell,
            step: .pounds(5),
            rest: .defaultRest,
            rpe: #require(RPE(8)),
            isSupersetWithPrevious: false,
            targetSets: 1,
            targetReps: 1,
            targetLoad: .pounds(pounds),
            sets: [
                LoggedSet(
                    id: SetID(Fixtures.uuid(number)),
                    weight: .pounds(pounds),
                    reps: .one,
                    kind: .working,
                    doneAt: start
                )
            ]
        )
        return WorkoutState(
            id: id,
            source: source,
            name: name,
            tag: "LA",
            isDeload: false,
            exercises: [exercise],
            cursor: nil,
            startedAt: start,
            endedAt: start.addingTimeInterval(Double(seconds)),
            phase: .finished,
            originDevice: Fixtures.deviceID
        )
    }

    /// What a workout of day `dayIndex` of `program` in week `weekIndex` carries.
    static func source(of program: Program, weekIndex: Int, dayIndex: Int) -> WorkoutSource {
        WorkoutSource(programID: program.id, weekIndex: weekIndex, dayTemplateID: program.days[dayIndex].id)
    }
}

// MARK: - Small views of a model, so that a failure prints a line and not a model

nonisolated extension TodayModel.Card {
    /// The card's case by name.
    var kind: String {
        switch self {
        case .upNext: "upNext"
        case .logged: "logged"
        case .restDay: "restDay"
        case .noProgram: "noProgram"
        case .blockComplete: "blockComplete"
        }
    }

    var upNext: TodayModel.UpNext? {
        if case let .upNext(card) = self {
            return card
        }
        return nil
    }

    var logged: TodayModel.Logged? {
        if case let .logged(card) = self {
            return card
        }
        return nil
    }

    var restDay: TodayModel.RestDay? {
        if case let .restDay(card) = self {
            return card
        }
        return nil
    }

    var message: TodayModel.Message? {
        switch self {
        case let .noProgram(card), let .blockComplete(card): card
        case .upNext, .logged, .restDay: nil
        }
    }
}

nonisolated extension [WeekStrip.Day] {
    /// One letter per day: D done, T today, P planned, a dash for rest.
    var marks: String {
        map { day in
            switch day.mark {
            case .done: "D"
            case .today: "T"
            case .planned: "P"
            case .rest: "-"
            }
        }
        .joined()
    }
}
