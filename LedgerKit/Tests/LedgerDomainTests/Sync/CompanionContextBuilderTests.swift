import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F19 S5: `CompanionContextBuilder`'s context, from the spec's seed program (8 weeks from Monday 2026-08-17: Upper A
/// Monday, Lower A Wednesday, Upper B Friday, Lower B Saturday; week 8 a deload without Saturday). The week and the
/// day are the calendar's, as Today reads them (criterion 3), across week boundaries and DST days.
@Suite("CompanionContextBuilder", .tags(.domain))
struct CompanionContextBuilderTests {
    typealias Seed = LedgerFakes.Fixtures

    @Test("On a scheduled day the next day is today's: Wednesday's Lower A in week 5, with its counts and settings")
    func context_scheduledToday() throws {
        let program = try Seed.seedProgram()
        let context = try Self.context(at: Self.utc(2026, 9, 16, hour: 5), settings: Seed.settingsKg)
        let lowerA = program.days[1]
        let names = try Self.exercises()
        #expect(context.revision == 7 && context.programID == program.id && context.programName == "Upper / Lower")
        #expect(context.weekIndex == 4 && context.weekCount == 8 && !context.isDeload)
        let expected = NextDay(
            dayTemplateID: lowerA.id,
            name: lowerA.name,
            tag: lowerA.tag,
            weekday: .wednesday,
            exerciseCount: lowerA.slots.count,
            setCount: lowerA.slots.map(\.sets).reduce(0, +),
            firstExerciseName: names[lowerA.slots[0].exerciseID]?.name,
            isToday: true,
            isLoggedToday: false
        )
        let sameDay = context.nextDay == expected
        #expect(sameDay, "today's day is not Lower A as scheduled")
        #expect(context.settings == WatchSettings(Seed.settingsKg))
    }

    @Test("Logged today: a finished workout of today's session that started today, and no other")
    func context_loggedToday() throws {
        let program = try Seed.seedProgram()
        let now = Self.utc(2026, 9, 16, hour: 18)
        let lowerA = WorkoutSource(programID: program.id, weekIndex: 4, dayTemplateID: program.days[1].id)
        let upperB = WorkoutSource(programID: program.id, weekIndex: 4, dayTemplateID: program.days[2].id)
        func logged(_ workouts: [WorkoutState]) throws -> Bool {
            try #require(Self.context(at: now, todaysWorkouts: workouts).nextDay).isLoggedToday
        }
        #expect(try logged([Self.workout(lowerA, startedAt: Self.utc(2026, 9, 16, hour: 7))]) == true)
        #expect(try logged([Self.workout(lowerA, startedAt: Self.utc(2026, 9, 15, hour: 23))]) == false)
        #expect(try logged([Self.workout(upperB, startedAt: Self.utc(2026, 9, 16, hour: 7))]) == false)
        #expect(try logged([Self.workout(lowerA, startedAt: Self.utc(2026, 9, 16, hour: 7), phase: .live)]) == false)
        #expect(try logged([]) == false)
    }

    @Test("On a rest day the next day is the next session: Thursday gives Friday's Upper B, not today's")
    func context_restDay() throws {
        let program = try Seed.seedProgram()
        let upperB = WorkoutSource(programID: program.id, weekIndex: 4, dayTemplateID: program.days[2].id)
        let now = Self.utc(2026, 9, 17, hour: 12)
        let next = try #require(try Self.context(at: now, todaysWorkouts: [Self.workout(upperB, startedAt: now)])
            .nextDay)
        #expect(next.dayTemplateID == program.days[2].id && next.weekday == .friday)
        #expect(!next.isToday && !next.isLoggedToday)
    }

    @Test("Across a week boundary the day's counts are of its own week: Sunday before the deload names a deload Monday")
    func context_weekBoundary() throws {
        let upperA = try Seed.seedProgram().days[0]
        let sunday = try Self.context(at: Self.utc(2026, 9, 20, hour: 22))
        #expect(sunday.weekIndex == 4 && sunday.nextDay?.dayTemplateID == upperA.id)
        #expect(sunday.nextDay?.weekday == .monday && sunday.nextDay?.setCount == upperA.slots.map(\.sets).reduce(0, +))
        let beforeDeload = try Self.context(at: Self.utc(2026, 10, 4, hour: 22))
        #expect(beforeDeload.weekIndex == 6 && !beforeDeload.isDeload)
        let deloadSets = upperA.slots.map { max(1, $0.sets - 1) }.reduce(0, +)
        #expect(beforeDeload.nextDay?.setCount == deloadSets && beforeDeload.nextDay?.isToday == false)
        let deloadMonday = try Self.context(at: Self.utc(2026, 10, 5, hour: 6))
        #expect(deloadMonday.weekIndex == 7 && deloadMonday.isDeload && deloadMonday.nextDay?.isToday == true)
    }

    @Test("The block's ends: none left after the last session, none after the block, the first before it")
    func context_blockEdges() throws {
        let lastSaturday = try Self.context(at: Self.utc(2026, 10, 10, hour: 9))
        #expect(lastSaturday.weekIndex == 7 && lastSaturday.nextDay == nil)
        let after = try Self.context(at: Self.utc(2026, 10, 12, hour: 9))
        #expect(after.weekIndex == 8 && after.weekCount == 8 && !after.isDeload && after.nextDay == nil)
        let before = try Self.context(at: Self.utc(2026, 8, 12, hour: 9))
        #expect(before.weekIndex == -1 && before.nextDay?.weekday == .monday && before.nextDay?.isToday == false)
        #expect(try before.nextDay?.dayTemplateID == Seed.seedProgram().days[0].id)
    }

    @Test(
        "Without a program the context names none: week 0 of 0, no day, the settings and acknowledgements all the same"
    )
    func context_noProgram() throws {
        let logs = [Self.log(1, device: EventBuilders.watch, created: 0)]
        let context = try Self.context(at: Self.utc(2026, 9, 16, hour: 5), program: .some(nil), storedLogs: logs)
        #expect(context.programID == nil && context.programName == nil && context.nextDay == nil)
        #expect(context.weekIndex == 0 && context.weekCount == 0 && !context.isDeload)
        #expect(context.settings == WatchSettings(Seed.settingsLb) && context
            .acknowledgedWorkoutIDs == [Self.workoutID(1)])
    }

    @Test("A slot whose exercise is not stored is not counted, as Today shows no row for it")
    func context_unstoredExercise() throws {
        let lowerA = try Seed.seedProgram().days[1]
        var exercises = try Self.exercises()
        exercises[lowerA.slots[0].exerciseID] = nil
        let next = try Self.context(at: Self.utc(2026, 9, 16, hour: 5), exercises: exercises).nextDay
        #expect(next?.exerciseCount == lowerA.slots.count - 1)
        #expect(next?.setCount == lowerA.slots.dropFirst().map(\.sets).reduce(0, +))
        #expect(next?.firstExerciseName == exercises[lowerA.slots[1].exerciseID]?.name)
    }
}

// MARK: - DST and the calendar's time zone

extension CompanionContextBuilderTests {
    static let newYork = TimeZone(identifier: "America/New_York") ?? .gmt

    static func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    @Test("The calendar's zone decides today: Sunday 23:30 in New York after fall-back is Monday in UTC")
    func context_fallBack_zoneDecidesToday() throws {
        var program = try Seed.seedProgram()
        program.startDate = try #require(CivilDate(year: 2026, month: 10, day: 12))
        let now = Seed.date(2026, 11, 1, hour: 23, minute: 30, in: Self.newYork)
        let local = try Self.context(at: now, program: program, calendar: Self.calendar(Self.newYork))
        #expect(local.weekIndex == 2 && local.nextDay?.weekday == .monday && local.nextDay?.isToday == false)
        let utc = try Self.context(at: now, program: program, calendar: Self.calendar(Seed.utc))
        #expect(utc.weekIndex == 3 && utc.nextDay?.weekday == .monday && utc.nextDay?.isToday == true)
        let day = try #require(CompanionContextBuilder.day(of: now, calendar: Self.calendar(Self.newYork)))
        #expect(day.upperBound.timeIntervalSince(day.lowerBound) == 25 * 3600)
    }

    @Test("After spring-forward's 23-hour Sunday, 00:30 Monday is the new week's day, and Sunday is still week 1")
    func context_springForward() throws {
        var program = try Seed.seedProgram()
        program.startDate = try #require(CivilDate(year: 2026, month: 3, day: 2))
        let calendar = Self.calendar(Self.newYork)
        let sunday = try Self.context(
            at: Seed.date(2026, 3, 8, hour: 23, minute: 30, in: Self.newYork),
            program: program,
            calendar: calendar
        )
        #expect(sunday.weekIndex == 0 && sunday.nextDay?.weekday == .monday && sunday.nextDay?.isToday == false)
        let monday = try Self.context(
            at: Seed.date(2026, 3, 9, minute: 30, in: Self.newYork),
            program: program,
            calendar: calendar
        )
        #expect(monday.weekIndex == 1 && monday.nextDay?.isToday == true)
        let day = try #require(CompanionContextBuilder.day(
            of: Seed.date(2026, 3, 8, hour: 12, in: Self.newYork),
            calendar: calendar
        ))
        #expect(day.upperBound.timeIntervalSince(day.lowerBound) == 23 * 3600)
    }
}

// MARK: - Helpers

extension CompanionContextBuilderTests {
    static func utc(_ year: Int, _ month: Int, _ day: Int, hour: Int) -> Date {
        Seed.date(year, month, day, hour: hour)
    }

    static func exercises() throws -> [ExerciseID: Exercise] {
        try Dictionary(ExerciseCatalog.seed().map { ($0.id, $0) }) { first, _ in first }
    }

    static func context(
        at now: Date,
        program: Program?? = .none,
        exercises: [ExerciseID: Exercise]? = nil,
        settings: Settings = Seed.settingsLb,
        todaysWorkouts: [WorkoutState] = [],
        storedLogs: [FinishedLogEntry] = [],
        calendar: Calendar = Seed.calendar
    ) throws -> CompanionContext {
        let inputs = try CompanionContextBuilder.Inputs(
            program: program ?? Seed.seedProgram(),
            exercises: exercises ?? Self.exercises(),
            settings: settings,
            todaysWorkouts: todaysWorkouts,
            storedLogs: storedLogs,
            device: EventBuilders.phone,
            now: now,
            calendar: calendar
        )
        return CompanionContextBuilder.context(inputs, revision: 7)
    }

    /// A workout of `source` that started at `startedAt`, finished unless `phase` says otherwise.
    static func workout(_ source: WorkoutSource, startedAt: Date, phase: WorkoutPhase = .finished) -> WorkoutState {
        var workout = EventBuilders.seedSession()
        workout.source = source
        workout.startedAt = startedAt
        workout.phase = phase
        workout.endedAt = phase == .finished ? startedAt.addingTimeInterval(3600) : nil
        return workout
    }

    static func workoutID(_ number: Int) -> WorkoutID {
        WorkoutID(EventBuilders.uuid(0xA000 + number))
    }

    /// A stored finished log of workout `number` from `device`, created `created` seconds after the fixtures' start.
    static func log(_ number: Int, device: DeviceID, created: TimeInterval) -> FinishedLogEntry {
        let record = FinishedWorkoutRecord(
            workoutID: workoutID(number),
            log: [],
            healthKitUUID: nil,
            finishedAt: EventBuilders.start,
            device: device
        )
        return FinishedLogEntry(
            record: record,
            createdAt: EventBuilders.start.addingTimeInterval(created),
            enqueuedAt: nil
        )
    }
}
