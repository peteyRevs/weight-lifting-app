@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// Builders shared by the F09 S3 adversarial suites (gate G2, round 1). Nothing here calls the feature: inputs
/// are built from `LedgerFakes`' seed program (spec §6.4) and `LedgerDomain`, and every expected value in the
/// suites comes from the brief, from hand computation or from a Domain function the suite calls itself.
nonisolated enum TodayAdversarial {
    static let english = Locale(identifier: "en_US")
    static let utc = TimeZone(secondsFromGMT: 0) ?? .gmt

    /// A Gregorian calendar in `zone` whose own first weekday is Thursday: the week start is the settings',
    /// never the calendar's, so a reading of `calendar.firstWeekday` shows.
    static func calendar(_ zone: TimeZone = utc) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = english
        calendar.firstWeekday = 5
        return calendar
    }

    static func zone(_ identifier: String) throws -> TimeZone {
        try #require(TimeZone(identifier: identifier), "no time zone \(identifier) on this host")
    }

    static func civil(_ year: Int, _ month: Int, _ day: Int) throws -> CivilDate {
        try #require(CivilDate(year: year, month: month, day: day))
    }

    /// The wall-clock moment `hour:minute:second` of `day` in `zone`. The caller picks a time that exists.
    static func moment(
        _ day: CivilDate,
        _ hour: Int = 12,
        _ minute: Int = 0,
        _ second: Int = 0,
        in zone: TimeZone = utc
    ) throws -> Date {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = zone
        let parts = DateComponents(
            year: day.year,
            month: day.month,
            day: day.day,
            hour: hour,
            minute: minute,
            second: second
        )
        return try #require(gregorian.date(from: parts))
    }

    /// The brief's examples: the seed program begun on Monday 2026-09-14.
    static func seed(start: CivilDate? = nil) throws -> Program {
        var program = try Fixtures.seedProgram()
        program.startDate = try start ?? civil(2026, 9, 14)
        return program
    }

    /// The bundled catalog by id.
    static func exercises() throws -> [ExerciseID: Exercise] {
        try Dictionary(ExerciseCatalog.seed().map { ($0.id, $0) }) { first, _ in first }
    }

    static func settings(_ units: Units = .lb, weekStart: Weekday = .monday) -> Settings {
        var settings = Settings.default
        settings.units = units
        settings.weekStart = weekStart
        return settings
    }

    static func input(
        _ program: Program?,
        now: Date,
        zone: TimeZone = utc,
        settings: Settings = .default,
        week: [WorkoutState] = [],
        recent: [WorkoutState] = [],
        previous: Volume? = nil,
        session: WorkoutState? = nil
    ) throws -> TodayInput {
        try TodayInput(
            program: program,
            exercises: exercises(),
            settings: settings,
            weekWorkouts: week,
            recentWorkouts: recent,
            previousWeekVolume: previous,
            session: session,
            now: now,
            calendar: calendar(zone),
            locale: english
        )
    }

    static func day(_ tag: String, in program: Program) throws -> DayTemplate {
        try #require(program.days.first { $0.tag == tag }, "no day tagged \(tag)")
    }
}

// MARK: - Workouts

nonisolated extension TodayAdversarial {
    /// The live workout `SessionBuilder` builds for day `tag` of `program` in week `week`, started at `start`.
    static func live(
        _ program: Program,
        week: Int,
        tag: String,
        number: Int,
        start: Date,
        units: Units = .lb
    ) throws -> WorkoutState {
        try SessionBuilder.build(
            program: program,
            weekIndex: week,
            day: day(tag, in: program),
            exercises: exercises(),
            history: [:],
            settings: settings(units),
            id: WorkoutID(Fixtures.uuid(number)),
            device: Fixtures.deviceID,
            now: start
        )
    }

    /// `workout` finished `seconds` after its start with its first `done` sets ticked (all of them by default).
    static func finished(_ workout: WorkoutState, after seconds: Int = 3600, done: Int = .max) -> WorkoutState {
        var copy = workout
        var remaining = done
        for exercise in copy.exercises.indices {
            for set in copy.exercises[exercise].sets.indices where remaining > 0 {
                copy.exercises[exercise].sets[set].doneAt = workout.startedAt.addingTimeInterval(1)
                remaining -= 1
            }
        }
        copy.cursor = nil
        copy.rest = nil
        copy.phase = .finished
        copy.endedAt = workout.startedAt.addingTimeInterval(TimeInterval(seconds))
        return copy
    }

    /// One done set of a hand-built workout.
    struct Lift: Sendable {
        let weight: Weight
        let reps: Int
        var isDone = true
        var kind = SetKind.working

        static func pounds(_ value: Decimal, _ reps: Int) -> Lift {
            Lift(weight: .pounds(value), reps: reps)
        }
    }

    /// A finished workout that holds exactly `lifts` in one exercise: for volumes the brief names to the pound.
    static func lifted(
        number: Int,
        start: Date,
        seconds: Int = 3600,
        lifts: [Lift],
        name: String = "Lower A — Squat focus",
        tag: String = "LA",
        source: WorkoutSource? = nil
    ) throws -> WorkoutState {
        let sets = lifts.enumerated().map { index, lift in
            LoggedSet(
                id: SetID(Fixtures.uuid(number * 1000 + index)),
                weight: lift.weight,
                reps: Reps(clamping: lift.reps),
                kind: lift.kind,
                doneAt: lift.isDone ? start.addingTimeInterval(1) : nil
            )
        }
        let exercise = try WorkoutExercise(
            id: WorkoutExerciseID(Fixtures.uuid(number * 1000 + 999)),
            slotID: nil,
            exerciseID: Fixtures.CatalogID.backSquat,
            originalExerciseID: Fixtures.CatalogID.backSquat,
            name: "Back Squat",
            equipment: .barbell,
            step: .pounds(5),
            rest: .defaultRest,
            rpe: #require(RPE(8)),
            isSupersetWithPrevious: false,
            targetSets: sets.count,
            targetReps: lifts.first?.reps ?? 1,
            targetLoad: lifts.first?.weight ?? .zero,
            sets: sets
        )
        return WorkoutState(
            id: WorkoutID(Fixtures.uuid(number)),
            source: source,
            name: name,
            tag: tag,
            isDeload: false,
            exercises: lifts.isEmpty ? [] : [exercise],
            cursor: nil,
            startedAt: start,
            endedAt: start.addingTimeInterval(TimeInterval(seconds)),
            phase: .finished,
            originDevice: Fixtures.deviceID
        )
    }
}

// MARK: - English dates, written here and not by `Date.FormatStyle`

nonisolated extension TodayAdversarial {
    static let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    static let months = [
        "January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
        "November", "December"
    ]

    /// "Wednesday".
    static func weekdayName(_ weekday: Weekday) -> String {
        weekdays[weekday.rawValue - 1]
    }

    /// "Wednesday, September 16".
    static func fullDate(_ day: CivilDate) -> String {
        "\(weekdayName(day.weekday)), \(months[day.month - 1]) \(day.day)"
    }

    /// "Wed".
    static func shortWeekday(_ day: CivilDate) -> String {
        String(weekdayName(day.weekday).prefix(3))
    }

    /// "W".
    static func letter(_ day: CivilDate) -> String {
        String(weekdayName(day.weekday).prefix(1))
    }
}

/// SplitMix64, seeded (testing-strategy §3 rule 5). Named apart from the target's own generator.
nonisolated struct AdversarialRandom: RandomNumberGenerator {
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
