import Foundation

/// Why `ProgramTemplates.program` could not write a block.
public enum ProgramTemplateError: Error, Equatable, Sendable {
    /// A template exercise, named as the catalog names it, is not among the exercises given: the catalog is not
    /// seeded yet (product decision #28). Onboarding offers a retry.
    case unknownExercise(String)
}

/// Onboarding's program generator (F08; spec §6.4, §6.7): the first 8-week block a lifter gets, for a goal and
/// a number of training days a week.
///
/// A block is written from a split (`ProgramTemplates+Splits`): its training days, each a list of catalog
/// exercises with a role. The goal turns a role into sets, reps, RPE, rest and progression
/// (`ProgramTemplates+Prescriptions`). One block is not derived that way: `both` on the 4-day split is spec
/// §6.4, the prototype's own program, row for row.
///
/// Program names, day names, tags and preview lines are English data, as the catalog's names are: they are
/// stored in the program, where the lifter edits them, and are not String Catalog entries.
public enum ProgramTemplates {
    /// Every block is 8 weeks long, and its last week is a deload.
    public static let weekCount = 8

    /// What to write: the lifter's two picks, and the units and the start date of the block.
    public struct Request: Hashable, Sendable {
        public var goal: TrainingGoal
        public var days: DaysPerWeek
        /// The unit the start loads are taken in: the catalog holds one load per unit (decision #21).
        public var units: Units
        /// Decision #18: the first day of the week the lifter starts in (`startDate(containing:weekStart:calendar:)`).
        public var startDate: CivilDate

        public init(goal: TrainingGoal, days: DaysPerWeek, units: Units, startDate: CivilDate) {
            self.goal = goal
            self.days = days
            self.units = units
            self.startDate = startDate
        }
    }

    /// One training day as onboarding's last step lists it.
    public struct DayPreview: Hashable, Sendable {
        /// "Upper A — Push focus".
        public let name: String
        /// "UA".
        public let tag: String
        /// "Bench, incline, row, pulldown, laterals": the day's lifts, as a lifter would say them.
        public let line: String
    }

    /// Onboarding's last step: the program a number of days a week gets.
    public struct Preview: Hashable, Sendable {
        /// "Upper / Lower".
        public let programName: String
        /// One per training day, in the program's order.
        public let days: [DayPreview]
    }

    /// Step 3's list. It needs no catalog, no ids and no goal: a goal changes prescriptions, never a name or a
    /// line.
    public static func preview(days: DaysPerWeek) -> Preview {
        let split = split(for: days)
        return Preview(
            programName: split.name,
            days: split.days.map { DayPreview(name: $0.name, tag: $0.tag, line: $0.preview) }
        )
    }

    /// Decision #18: the first day (on `weekStart`) of the week that holds `now`, in `calendar`'s time zone, or
    /// `nil` when that day is outside 0001…9999.
    public static func startDate(containing now: Date, weekStart: Weekday, calendar: Calendar) -> CivilDate? {
        // `firstDayOfWeek` reads the week start and the time zone only, never the calendar's own start date.
        WeekCalendar(startDate: .unixEpoch, weekStart: weekStart, calendar: calendar).firstDayOfWeek(containing: now)
    }

    /// The block for `request`: active, `weekCount` weeks with the last a deload, the split's days on their
    /// weekdays, the goal and `days.rawValue` recorded.
    ///
    /// Each slot names the catalog exercise that has exactly the template's name. `catalog` is the stored
    /// exercises (`ExerciseRepository.all()`): custom exercises are ignored, and of two catalog exercises with
    /// one name the first is used. A slot's start load is its exercise's `startLoad(in: request.units)`, copied
    /// into the slot, so a later catalog refresh never changes the block (decision #24); its `step` is `nil`,
    /// resolved per unit when read. The deload week keeps every training day, except the 4-day split's
    /// Saturday (spec §6.4); its loads, sets and RPE are `ProgressionRules`' business.
    ///
    /// Deterministic: the same request, catalog, `id` and `newID` sequence give an equal `Program`. `newID` is
    /// called once per week, for weeks 0…7 in order, then for each day in order: once for the day, then once
    /// for each of its slots in order. That is 28 calls for the 4-day split.
    ///
    /// - Throws: `ProgramTemplateError.unknownExercise`, naming the first template exercise `catalog` lacks, in
    ///   day and slot order. Every exercise is looked up before the first id is drawn, so a call that throws it
    ///   has not called `newID`. `SlotValidationError` and `ProgramValidationError` propagate from the model's
    ///   initializers; no template causes one (`ProgramTemplatesTests`).
    public static func program(
        _ request: Request,
        catalog: [Exercise],
        id: ProgramID,
        newID: () -> UUID
    ) throws -> Program {
        let split = split(for: request.days)
        let exercises = Dictionary(catalog.lazy.filter { !$0.isCustom }.map { ($0.name, $0) }) { first, _ in first }
        // Every lift finds its exercise before the first id is drawn: a block that cannot be written draws none.
        let resolved = try split.days.map { day in try (day: day, lifts: lifts(of: day, in: exercises)) }
        let weekIDs = (0 ..< weekCount).map { _ in WeekID(newID()) }
        var days: [DayTemplate] = []
        var training: [Weekday: DayTemplateID] = [:]
        for (day, lifts) in resolved {
            let dayID = DayTemplateID(newID())
            let slots = try lifts.map { lift, exercise in
                let scheme = split.scheme(for: lift, goal: request.goal)
                return try slot(
                    id: SlotID(newID()),
                    lift: lift,
                    exercise: exercise,
                    scheme: scheme,
                    units: request.units
                )
            }
            days.append(DayTemplate(id: dayID, name: day.name, tag: day.tag, slots: slots))
            training[day.weekday] = dayID
        }
        return try Program(
            id: id,
            name: split.name,
            startDate: request.startDate,
            weeks: weeks(ids: weekIDs, training: training, deloadRestDays: split.deloadRestDays),
            days: days,
            goal: request.goal,
            daysPerWeek: request.days.rawValue,
            isActive: true
        )
    }

    /// `day`'s lifts in order, each with the catalog exercise of its name; throws for the first that has none.
    private static func lifts(
        of day: Day,
        in exercises: [String: Exercise]
    ) throws(ProgramTemplateError) -> [(lift: Lift, exercise: Exercise)] {
        var found: [(lift: Lift, exercise: Exercise)] = []
        for lift in day.lifts {
            guard let exercise = exercises[lift.exercise] else {
                throw .unknownExercise(lift.exercise)
            }
            found.append((lift, exercise))
        }
        return found
    }

    /// The slot for `lift` on `exercise`: what `scheme` prescribes, the exercise's start load in `units` copied
    /// in, and no step of its own.
    private static func slot(
        id: SlotID,
        lift: Lift,
        exercise: Exercise,
        scheme: Scheme,
        units: Units
    ) throws(SlotValidationError) -> Slot {
        try Slot(
            id: id,
            exerciseID: exercise.id,
            sets: scheme.sets,
            reps: scheme.reps.lowerBound,
            repsHi: scheme.reps.upperBound,
            rpe: scheme.rpe,
            restSeconds: scheme.rest,
            progression: scheme.progression,
            startLoad: exercise.startLoad(in: units),
            isSupersetWithPrevious: lift.isSupersetWithPrevious,
            dropSets: lift.dropSets
        )
    }

    /// One week per id, in order: each trains the days of `training` on their weekdays, and the last, the
    /// deload, rests on `deloadRestDays` as well.
    private static func weeks(
        ids: [WeekID],
        training: [Weekday: DayTemplateID],
        deloadRestDays: Set<Weekday>
    ) -> [Week] {
        let deload = training.filter { !deloadRestDays.contains($0.key) }
        return ids.enumerated().map { index, id in
            let isDeload = index == ids.count - 1
            return Week(id: id, index: index, isDeload: isDeload, schedule: isDeload ? deload : training)
        }
    }
}
