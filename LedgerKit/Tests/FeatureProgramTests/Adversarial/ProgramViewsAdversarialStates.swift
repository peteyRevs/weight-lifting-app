#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import Foundation
    import LedgerDomain
    import LedgerTestSupport
    import Testing

    /// States of the builder that no preview draws, for the F11 S9 adversarial suites (gate G2, round 1). Each
    /// is the model the presentation makes of a program the Domain's own edits can reach.
    nonisolated enum BuilderState: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// Two weeks and no training day: the strip offers nothing.
        case noDays
        /// A day of twelve exercises under a long name, and a day with none, both scheduled.
        case twelveExercises
        /// Ten days, "D1" to "D10", the last seven on the seven weekdays: no rest day, a tag of three letters.
        case tenDays
        /// Sixteen weeks, every one a deload week, the last selected, under a long program name.
        case sixteenDeloads
        /// The notice that names a week with logged sessions.
        case loggedNotice

        static let longName =
            "Hypertrophy and strength, upper and lower with accessories: the long autumn block before the meet"
        static let longDay = "Upper body, pressing and pulling, with every accessory the gym has room for"

        var testDescription: String {
            rawValue
        }

        func input() throws -> ProgramBuilderInput {
            switch self {
            case .noDays:
                return try ProgramFixtures.input(ProgramFixtures.program(weekCount: 2, days: []))
            case .twelveExercises:
                var long = try ProgramFixtures.day(1, slotCount: 12)
                long.name = Self.longDay
                let days = try [long, ProgramFixtures.day(2)]
                var input = try ProgramFixtures.input(ProgramFixtures.program(weekCount: 3, days: days))
                try Self.apply([
                    .setSchedule(week: 0, weekday: .monday, day: days[0].id),
                    .setSchedule(week: 0, weekday: .wednesday, day: days[1].id)
                ], to: &input)
                return input
            case .tenDays:
                let days = try (1 ... 10).map { try ProgramFixtures.day($0, slotCount: 1) }
                var input = try ProgramFixtures.input(ProgramFixtures.program(weekCount: 4, days: days))
                try Self.apply(zip(Weekday.allCases, days.suffix(7)).map {
                    .setSchedule(week: 0, weekday: $0, day: $1.id)
                }, to: &input)
                return input
            case .sixteenDeloads:
                var input = try ProgramFixtures.seedInput()
                try Self.apply((0 ..< 8).map { .addWeek(WeekID(Fixtures.uuid(900 + $0))) }, to: &input)
                try Self.apply((0 ..< 16).map { .setDeload(true, week: $0) }, to: &input)
                try Self.apply([.renameProgram(Self.longName)], to: &input)
                input.selectedWeek = 15
                return input
            case .loggedNotice:
                var input = try ProgramFixtures.seedInput(selectedWeek: 3)
                input.notice = .weekHasLoggedSessions(weekNumber: 8)
                return input
            }
        }

        func model() throws -> ProgramBuilderModel {
            try ProgramPresentation.make(input())
        }

        private static func apply(_ edits: [ProgramBuilderEdit], to input: inout ProgramBuilderInput) throws {
            for edit in edits {
                input.program = try edit.applied(to: input.program)
            }
        }
    }

    /// States of the exercise library that no preview draws.
    nonisolated enum LibraryState: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// The whole bundled catalog, no filter, no pick.
        case everything
        /// The whole catalog, every exercise picked and every one already in the day.
        case everythingPicked
        /// A library with no exercise at all.
        case emptyCatalog
        /// Two exercises the lifter made, with long names, one picked and in the day.
        case longNames
        /// A query longer than the search field.
        case longQuery

        static let exerciseName =
            "Half-kneeling single-arm landmine press with a pause at the top and a slow five-second negative"
        static let queryText = "half-kneeling single-arm landmine press with a pause at the top, slow negative"

        var testDescription: String {
            rawValue
        }

        func input() throws -> ExercisePickerInput {
            switch self {
            case .everything:
                return try ExercisePickerFixtures.input()
            case .everythingPicked:
                let all = try ExercisePickerFixtures.catalog().map(\.id)
                return try ExercisePickerFixtures.input(picks: all, dayExercises: Set(all))
            case .emptyCatalog:
                var input = try ExercisePickerFixtures.input()
                input.exercises = []
                return input
            case .longNames:
                var first = ExercisePickerFixtures.customRow
                first.name = Self.exerciseName
                let second = Exercise(
                    id: ExerciseID(Fixtures.uuid(7002)),
                    name: Self.exerciseName + ", left side",
                    shortName: "LANDMINE",
                    equipment: first.equipment,
                    primaryMuscle: first.primaryMuscle,
                    pattern: first.pattern,
                    defaultStartLoad: first.defaultStartLoad,
                    isCustom: true
                )
                var input = try ExercisePickerFixtures.input(
                    query: "landmine",
                    picks: [first.id],
                    dayExercises: [first.id]
                )
                input.exercises += [first, second]
                return input
            case .longQuery:
                return try ExercisePickerFixtures.input(query: Self.queryText)
            }
        }

        func model() throws -> ExercisePickerModel {
            try ExercisePickerPresentation.make(input())
        }
    }
#endif
