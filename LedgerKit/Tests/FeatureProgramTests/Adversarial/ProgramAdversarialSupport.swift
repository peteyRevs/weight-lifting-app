@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport

/// F11 S5 adversarial round 1: what the tester's suites share. Programs are built here from seeds, an input is
/// filled as the store will fill it, and an action is applied as its documentation tells the store to apply
/// it: one `ProgramEditing` call, written here and not taken from the feature.
nonisolated enum AdvProgram {
    static let english = Locale(identifier: "en_US")

    /// Gregorian, UTC, with the first weekday and the locale asked for.
    static func calendar(firstWeekday: Int = 2, locale: Locale? = english, zone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        calendar.locale = locale
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    static func input(
        _ program: Program,
        exercises: [ExerciseID: Exercise] = [:],
        weekStart: Weekday = .monday,
        week: Int = 0,
        logged: Set<Int> = [],
        notice: ProgramBuilderNotice? = nil,
        calendar: Calendar = calendar(),
        locale: Locale = english
    ) -> ProgramBuilderInput {
        var settings = Settings.default
        settings.weekStart = weekStart
        return ProgramBuilderInput(
            program: program,
            exercises: exercises,
            settings: settings,
            selectedWeek: week,
            loggedWeeks: logged,
            notice: notice,
            calendar: calendar,
            locale: locale
        )
    }

    /// The spec's seed program with the bundled catalog.
    static func seed(week: Int = 0) throws -> ProgramBuilderInput {
        let catalog = try Dictionary(ExerciseCatalog.seed().map { ($0.id, $0) }) { first, _ in first }
        return try input(Fixtures.seedProgram(), exercises: catalog, week: week)
    }

    static func exercise(_ number: Int, short: String? = nil) -> Exercise {
        Exercise(
            id: ExerciseID(Fixtures.uuid(40000 + number)),
            name: "Exercise \(number)",
            shortName: short ?? "Ex\(number)",
            equipment: .barbell,
            primaryMuscle: .chest,
            pattern: .horizontalPush,
            defaultStartLoad: [:]
        )
    }

    static func slot(
        _ number: Int,
        exercise: Int,
        sets: Int = 3,
        rest: Int = 90,
        joined: Bool = false,
        drop: Int = 0
    ) throws -> Slot {
        try Slot(
            id: SlotID(Fixtures.uuid(50000 + number)),
            exerciseID: ExerciseID(Fixtures.uuid(40000 + exercise)),
            sets: sets,
            reps: 8,
            repsHi: 10,
            rpe: 8,
            restSeconds: rest,
            progression: .linear,
            isSupersetWithPrevious: joined,
            dropSets: drop
        )
    }

    static func day(_ number: Int, name: String? = nil, tag: String? = nil, slots: [Slot] = []) -> DayTemplate {
        DayTemplate(
            id: DayTemplateID(Fixtures.uuid(30000 + number)),
            name: name ?? "Day \(number)",
            tag: tag ?? "T\(number)",
            slots: slots
        )
    }

    /// A block of `weeks` weeks over `days`; `schedule` gives the place among `days` trained on a weekday of a
    /// week, or nil for rest.
    static func program(
        name: String = "Block",
        weeks: Int,
        days: [DayTemplate],
        deloads: Set<Int> = [],
        schedule: (Int, Weekday) -> Int? = { _, _ in nil }
    ) throws -> Program {
        let built = (0 ..< weeks).map { index in
            var entries: [Weekday: DayTemplateID] = [:]
            for weekday in Weekday.allCases {
                if let place = schedule(index, weekday), days.indices.contains(place) {
                    entries[weekday] = days[place].id
                }
            }
            return Week(
                id: WeekID(Fixtures.uuid(20000 + index)),
                index: index,
                isDeload: deloads.contains(index),
                schedule: entries
            )
        }
        let start = try Fixtures.seedProgram().startDate
        return try Program(id: Fixtures.programID, name: name, startDate: start, weeks: built, days: days)
    }

    /// A program drawn from `seed`: 2 to 9 weeks, 0 to 6 days of 0 to 6 slots (drop sets and supersets among
    /// them, one slot in five of an exercise that is not stored), any schedule, any deload flags.
    static func random(seed: UInt64) throws -> (program: Program, exercises: [ExerciseID: Exercise]) {
        var rng = SplitMix64(seed: seed)
        let dayCount = Int.random(in: 0 ... 6, using: &rng)
        var days: [DayTemplate] = []
        var number = 0
        for place in 0 ..< dayCount {
            var slots: [Slot] = []
            for index in 0 ..< Int.random(in: 0 ... 6, using: &rng) {
                number += 1
                try slots.append(slot(
                    number,
                    exercise: Int.random(in: 0 ... 14, using: &rng),
                    sets: Int.random(in: 1 ... 12, using: &rng),
                    rest: 30 + 15 * Int.random(in: 0 ... 18, using: &rng),
                    joined: index > 0 && Int.random(in: 0 ... 2, using: &rng) == 0,
                    drop: Int.random(in: 0 ... 3, using: &rng) == 0 ? 1 : 0
                ))
            }
            let name = place.isMultiple(of: 2) ? "Day \(place) — focus \(place)" : "Day \(place)"
            days.append(day(place, name: name, slots: slots))
        }
        let weekCount = Int.random(in: 2 ... 9, using: &rng)
        var picks: [[Int?]] = []
        var deloads: Set<Int> = []
        for week in 0 ..< weekCount {
            picks.append(Weekday.allCases.map { _ in
                dayCount > 0 && Bool.random(using: &rng) ? Int.random(in: 0 ..< dayCount, using: &rng) : nil
            })
            if Int.random(in: 0 ... 3, using: &rng) == 0 {
                deloads.insert(week)
            }
        }
        let program = try program(weeks: weekCount, days: days, deloads: deloads) { week, weekday in
            picks[week][weekday.rawValue - 1]
        }
        let stored = (0 ... 11).map { exercise($0) }
        return (program, Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) }))
    }
}

/// The store's part, as the actions' documentation gives it: what an action does to the input.
nonisolated enum AdvStore {
    struct Step {
        var input: ProgramBuilderInput
        /// How many `ProgramEditing` calls the action stood for.
        var edits = 0
        var route: ProgramRoute?
        var refused: ProgramEditError?
    }

    /// One edit as one `ProgramEditing` call, spelled by the tester.
    static func edited(_ program: Program, _ edit: ProgramBuilderEdit) throws(ProgramEditError) -> Program {
        switch edit {
        case let .renameProgram(name): ProgramEditing.renameProgram(program, to: name)
        case let .addWeek(id): ProgramEditing.addWeek(program, id: id)
        case let .removeLastWeek(logged): try ProgramEditing.removeLastWeek(program, loggedWeeks: logged)
        case let .setDeload(isDeload, week): ProgramEditing.setDeload(program, isDeload, week: week)
        case let .setSchedule(week, weekday, day):
            ProgramEditing.setSchedule(program, week: week, weekday: weekday, day: day)
        case let .copyPreviousWeek(week): ProgramEditing.copyPreviousWeek(program, week: week)
        case let .applyToLaterWeeks(week): ProgramEditing.applyToLaterWeeks(program, week: week)
        case let .addDay(id, name): ProgramEditing.addDay(program, id: id, name: name)
        }
    }

    /// `input` after `action`; `fresh` numbers the ids the store would draw.
    static func apply(_ action: ProgramBuilderAction, to input: ProgramBuilderInput, fresh: Int) -> Step {
        var step = Step(input: input)
        switch action {
        case let .selectWeek(place):
            step.input.selectedWeek = place
            step.input.notice = nil
        case let .edit(edit, notice):
            do {
                step.input.program = try edited(input.program, edit)
            } catch {
                step.refused = error
            }
            step.edits = 1
            step.input.notice = notice
        case let .addWeek(selecting):
            step.input.program = ProgramEditing.addWeek(input.program, id: WeekID(Fixtures.uuid(60000 + fresh)))
            step.edits = 1
            step.input.selectedWeek = selecting
            step.input.notice = nil
        case let .addDay(name, weekIndex):
            let id = DayTemplateID(Fixtures.uuid(70000 + fresh))
            step.input.program = ProgramEditing.addDay(input.program, id: id, name: name)
            step.edits = 1
            step.input.notice = nil
            step.route = .day(id, weekIndex: weekIndex)
        case let .notice(notice):
            step.input.notice = notice
        case let .route(route):
            step.route = route
        }
        return step
    }
}
