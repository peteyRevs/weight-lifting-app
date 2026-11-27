import Foundation
import LedgerDependencies
import LedgerDomain

/// Today's session of the active program, as the watch starts it: "Start" on the screen before a workout (F18
/// criterion 2), and the watch's own workout when the phone asked for one that did not arrive within 5 s (F17
/// criterion 8, `startOwnWorkout`). The day is the one the phone's calendar rules schedule today (`WeekCalendar`,
/// decision #18), built through `StartWorkoutUseCase` from what the watch stores.
public struct WatchTodayStart: Sendable {
    let session: any WorkoutSessionClient
    let programs: any ProgramRepository
    let exercises: any ExerciseRepository
    let stats: any StatsQueries
    let settings: any SettingsRepository
    let device: DeviceID
    let calendar: Calendar
    let now: @Sendable () -> Date
    let newID: @Sendable () -> UUID
    let logger: LedgerLogger

    public init(
        session: any WorkoutSessionClient,
        programs: any ProgramRepository,
        exercises: any ExerciseRepository,
        stats: any StatsQueries,
        settings: any SettingsRepository,
        device: DeviceID,
        calendar: Calendar,
        now: @escaping @Sendable () -> Date,
        newID: @escaping @Sendable () -> UUID,
        logger: LedgerLogger
    ) {
        self.session = session
        self.programs = programs
        self.exercises = exercises
        self.stats = stats
        self.settings = settings
        self.device = device
        self.calendar = calendar
        self.now = now
        self.newID = newID
        self.logger = logger
    }

    /// Starts today's scheduled day, or resumes it when it is the live workout (rule 17); nil when there is
    /// nothing to start: no program on the watch, a rest day, a day outside the block's weeks, or another
    /// device's start that won (its workout is the one the session shows). A live workout of another day is a
    /// conflict, and nothing replaces it.
    @discardableResult
    func start() async throws -> StartWorkoutUseCase.Outcome? {
        guard let program = try await programs.active() else {
            return nil
        }
        let today = now()
        let weeks = try await WeekCalendar(
            startDate: program.startDate, weekStart: settings.load().weekStart, calendar: calendar
        )
        guard let day = weeks.scheduledDay(on: today, in: program) else {
            return nil
        }
        let source = WorkoutSource(programID: program.id, weekIndex: weeks.weekIndex(for: today), dayTemplateID: day)
        let useCase = StartWorkoutUseCase(
            session: session, programs: programs, exercises: exercises, stats: stats, settings: settings,
            device: device, now: now, newID: newID
        )
        do {
            return try await useCase.start(source)
        } catch WorkoutSessionError.workoutInProgress {
            return nil
        }
    }

    /// The watch's own workout when the phone's did not come (`WatchComposition`'s `startOwnWorkout`): today's day,
    /// or, with none to start, nothing but a line in the log.
    public func startOwnWorkout() async {
        do {
            let outcome = try await start()
            if outcome == nil {
                logger.log.notice("The phone's workout did not come and there is no day to start today")
            }
        } catch {
            logger.log.error("The watch's own workout did not start: \(String(describing: error), privacy: .public)")
        }
    }
}
