import Foundation

/// What the phone tells the watch, from what the phone stores (F19 S5; criteria 1, 3, 10): the context and the
/// program file `ProgramPusher` sends, and the revision it sends the context under.
///
/// Pure: it reads no clock and no store. The moment and the calendar are passed in, and every day is the calendar
/// day of the calendar's time zone, found with `WeekCalendar` as Today finds it, so the watch's idle screen names
/// the week and the day the phone's Today names for the same moment, across a 23- or 25-hour day too.
public enum CompanionContextBuilder {
    /// How many of the watch's records the context acknowledges, newest first: about two months of daily training
    /// on the watch, and some 2 500 bytes of a context's 256 000.
    public static let acknowledgedWindow = 64

    /// Everything the context is built from.
    public struct Inputs: Sendable {
        /// The active program, or nil when there is none.
        public var program: Program?
        /// The stored exercises by id: the slots name theirs by id.
        public var exercises: [ExerciseID: Exercise]
        public var settings: Settings
        /// The finished workouts that started today (`day(of:calendar:)`); any other is ignored.
        public var todaysWorkouts: [WorkoutState]
        /// The finished logs the phone stores (`CompanionStore.unacknowledgedLogs()`, every one on the phone).
        public var storedLogs: [FinishedLogEntry]
        /// The phone itself: its own archived logs are not the watch's records and acknowledge nothing.
        public var device: DeviceID
        public var now: Date
        /// Its time zone decides which calendar day `now` falls on.
        public var calendar: Calendar

        public init(
            program: Program?,
            exercises: [ExerciseID: Exercise],
            settings: Settings,
            todaysWorkouts: [WorkoutState],
            storedLogs: [FinishedLogEntry],
            device: DeviceID,
            now: Date,
            calendar: Calendar
        ) {
            self.program = program
            self.exercises = exercises
            self.settings = settings
            self.todaysWorkouts = todaysWorkouts
            self.storedLogs = storedLogs
            self.device = device
            self.now = now
            self.calendar = calendar
        }
    }

    /// The context for `inputs`, under `revision`. Without a program it names none: week 0 of 0 and no day.
    public static func context(_ inputs: Inputs, revision: UInt64) -> CompanionContext {
        let program = inputs.program
        let weeks = program.map { WeekCalendar(
            startDate: $0.startDate,
            weekStart: inputs.settings.weekStart,
            calendar: inputs.calendar
        ) }
        let weekIndex = weeks?.weekIndex(for: inputs.now) ?? 0
        return CompanionContext(
            revision: revision,
            programID: program?.id,
            programName: program?.name,
            weekIndex: weekIndex,
            weekCount: program?.weeks.count ?? 0,
            isDeload: program?.week(at: weekIndex)?.isDeload ?? false,
            nextDay: program.flatMap { program in weeks.flatMap { nextDay(program, $0, inputs) } },
            settings: WatchSettings(inputs.settings),
            acknowledgedWorkoutIDs: acknowledged(inputs.storedLogs, device: inputs.device)
        )
    }

    /// The program file for `program`: with the custom exercises its slots name, in id order, and the last
    /// performance of the exercises its slots name, of those `lastPerformance` holds. Nil without a program.
    public static func programFile(
        _ program: Program?,
        exercises: [ExerciseID: Exercise],
        lastPerformance: [ExerciseID: LastPerformance]
    ) -> CompanionFile? {
        guard let program else {
            return nil
        }
        let named = exerciseIDs(of: program)
        let custom = named.compactMap { exercises[$0] }.filter(\.isCustom)
        return .program(
            program,
            customExercises: custom,
            lastPerformance: lastPerformance.filter { named.contains($0.key) }
        )
    }

    /// The exercises `program`'s slots name, each once, in id order.
    public static func exerciseIDs(of program: Program) -> [ExerciseID] {
        Set(program.days.flatMap(\.slots).map(\.exerciseID)).sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
    }

    /// The revision of the next context: above `stored`, the last one handed out (criterion 2: the watch applies
    /// only a higher one), and at least the milliseconds since 1970 at `now`, so a store that was lost or reset
    /// still starts above what the watch holds. Saturates at the largest revision rather than wrap.
    public static func revision(after stored: UInt64?, now: Date) -> UInt64 {
        let next = stored.map { $0 == .max ? $0 : $0 + 1 } ?? 1
        let milliseconds = (now.timeIntervalSince1970 * 1000).rounded(.down)
        guard milliseconds.isFinite, milliseconds >= 0, milliseconds < 0x1p64 else {
            return next
        }
        return max(next, UInt64(milliseconds))
    }

    /// The calendar day `now` falls on, from its first moment to the next day's: what `Inputs.todaysWorkouts` is
    /// read for. Nil outside the years 1 to 9999.
    public static func day(of now: Date, calendar: Calendar) -> Range<Date>? {
        guard let today = CivilDate(now, in: calendar), let tomorrow = today.adding(days: 1) else {
            return nil
        }
        return today.startOfDay(in: calendar) ..< tomorrow.startOfDay(in: calendar)
    }
}

// MARK: - The day and the acknowledgements

extension CompanionContextBuilder {
    /// Today's session when one is scheduled today, else the block's next one; nil when none is left. Its counts
    /// are of the prescriptions of its own program week, as Today's card counts them (a deload week has fewer
    /// sets), over the slots whose exercise is stored.
    static func nextDay(_ program: Program, _ weeks: WeekCalendar, _ inputs: Inputs) -> NextDay? {
        guard let session = session(program, weeks, inputs.now), let week = program.week(at: session.weekIndex) else {
            return nil
        }
        let planned = session.day.slots.compactMap { slot in
            inputs.exercises[slot.exerciseID].map { exercise in
                let prescription = ProgressionRules.prescribe(
                    week: week,
                    weekIndex: session.weekIndex,
                    slot: slot,
                    exercise: exercise,
                    units: inputs.settings.units
                )
                return (name: exercise.name, sets: prescription.sets)
            }
        }
        let source = WorkoutSource(programID: program.id, weekIndex: session.weekIndex, dayTemplateID: session.day.id)
        let today = CivilDate(inputs.now, in: inputs.calendar)
        return NextDay(
            dayTemplateID: session.day.id,
            name: session.day.name,
            tag: session.day.tag,
            weekday: session.weekday,
            exerciseCount: planned.count,
            setCount: planned.reduce(0) { $0 + $1.sets },
            firstExerciseName: planned.first?.name,
            isToday: session.isToday,
            // Today's rule (`TodayPresentation.loggedWorkout`): a workout of this session that started today.
            isLoggedToday: session.isToday && inputs.todaysWorkouts.contains { workout in
                workout.phase == .finished && workout.source == source
                    && CivilDate(workout.startedAt, in: inputs.calendar) == today
            }
        )
    }

    /// A session of the program: a day template in a program week, on a weekday.
    private struct Session {
        let day: DayTemplate
        let weekIndex: Int
        let weekday: Weekday
        let isToday: Bool
    }

    /// The session `nextDay` describes: today's while the block runs and today is scheduled, else the next one.
    private static func session(_ program: Program, _ weeks: WeekCalendar, _ now: Date) -> Session? {
        let todays = weeks.isBlockComplete(program, on: now) ? nil : weeks.scheduledDay(on: now, in: program)
        if let day = program.days.first(where: { $0.id == todays }) {
            return Session(
                day: day,
                weekIndex: weeks.weekIndex(for: now),
                weekday: weeks.weekday(of: now),
                isToday: true
            )
        }
        return weeks.nextScheduledDay(after: now, in: program).flatMap { next in
            program.days.first { $0.id == next.dayTemplateID }.map {
                Session(day: $0, weekIndex: next.weekIndex, weekday: next.weekday, isToday: false)
            }
        }
    }

    /// The ids of the newest `acknowledgedWindow` records the watch sent that the phone stores, newest first: the
    /// logs whose device is not the phone's own. `storedLogs` comes oldest first, as the store lists them.
    static func acknowledged(_ storedLogs: [FinishedLogEntry], device: DeviceID) -> [WorkoutID] {
        Array(storedLogs.filter { $0.record.device != device }.reversed().prefix(acknowledgedWindow)
            .map(\.record.workoutID))
    }
}
