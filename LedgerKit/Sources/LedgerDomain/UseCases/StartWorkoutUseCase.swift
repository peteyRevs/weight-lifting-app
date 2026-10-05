import Foundation

/// Why `StartWorkoutUseCase` started nothing.
public enum StartWorkoutError: Error, Equatable, Sendable {
    /// The program is not the active one: it was replaced or deleted after its day was shown.
    case programNotActive(ProgramID)
    /// The active program holds no such day.
    case dayNotInProgram(DayTemplateID)
    /// The day has no exercise, so there would be nothing to log.
    case emptyDay(DayTemplateID)
}

/// "Start workout" for a program day (F10 criteria 1 and 2; spec §7.3, rule 17): resumes the live workout
/// when it is that day's, reports a conflict when it is another's, and otherwise builds the session from
/// what is stored now (`SessionBuilder`) and starts it on the session client.
///
/// It decides and reads; the one workout at a time is the session client's to guard. When another caller
/// starts a workout between this use case's look and its start, `start` throws the client's
/// `workoutInProgress`, and asking again reports the conflict.
public struct StartWorkoutUseCase: Sendable {
    public enum Outcome: Hashable, Sendable {
        /// A new workout, built and now live.
        case started(WorkoutState)
        /// The live workout is this day's (rule 17): nothing was built or stored.
        case resumed(WorkoutState)
        /// A workout of another day is live, and nothing changed: the caller asks the lifter, then calls
        /// again with `replacingLive` or shows the live one.
        case conflict(live: WorkoutState)
    }

    private let session: any WorkoutSessionClient
    private let programs: any ProgramRepository
    private let exercises: any ExerciseRepository
    private let stats: any StatsQueries
    private let settings: any SettingsRepository
    private let device: DeviceID
    private let now: @Sendable () -> Date
    private let newID: @Sendable () -> UUID

    /// - Parameters:
    ///   - device: this install's device, the new workout's `originDevice`.
    ///   - now: the injected date: when the new workout starts, and when a replaced one ends.
    ///   - newID: the injected UUID source, for the new workout's id.
    public init(
        session: any WorkoutSessionClient,
        programs: any ProgramRepository,
        exercises: any ExerciseRepository,
        stats: any StatsQueries,
        settings: any SettingsRepository,
        device: DeviceID,
        now: @escaping @Sendable () -> Date,
        newID: @escaping @Sendable () -> UUID
    ) {
        self.session = session
        self.programs = programs
        self.exercises = exercises
        self.stats = stats
        self.settings = settings
        self.device = device
        self.now = now
        self.newID = newID
    }

    /// Starts the workout of `source`, a week and day of the active program.
    ///
    /// - A live workout with the same source is resumed, whatever `replacingLive` says (rule 17).
    /// - A live workout with another source is a conflict; with `replacingLive` it is discarded, at the time
    ///   the new one starts, once the new one is built: a build that fails leaves it live.
    ///
    /// Throws `StartWorkoutError`, before it looks at the session; `SessionBuilderError` (`weekOutOfRange`
    /// once the block has ended, `unknownExercise` for a slot whose exercise is not stored); and whatever
    /// the stores or the session client throw. Only a throw from `start` itself can follow a discard.
    public func start(_ source: WorkoutSource, replacingLive: Bool = false) async throws -> Outcome {
        guard let program = try await programs.active(), program.id == source.programID else {
            throw StartWorkoutError.programNotActive(source.programID)
        }
        guard let day = program.days.first(where: { $0.id == source.dayTemplateID }) else {
            throw StartWorkoutError.dayNotInProgram(source.dayTemplateID)
        }
        guard !day.slots.isEmpty else {
            throw StartWorkoutError.emptyDay(day.id)
        }
        let live = try await session.current()
        if let live {
            if let same = SessionBuilder.resumable(live, program: program, weekIndex: source.weekIndex, day: day) {
                return .resumed(same)
            }
            guard replacingLive else {
                return .conflict(live: live)
            }
        }
        let workout = try await build(program, weekIndex: source.weekIndex, day: day)
        if live != nil {
            try await session.discard(endedAt: workout.startedAt)
        }
        try await session.start(workout)
        return .started(workout)
    }

    /// The day's session as stored now: each slot's exercise, its last performance (the "Last" line and
    /// "Repeat"), and the lifter's units and auto-rest setting.
    private func build(_ program: Program, weekIndex: Int, day: DayTemplate) async throws -> WorkoutState {
        var catalog: [ExerciseID: Exercise] = [:]
        var history: [ExerciseID: LastPerformance] = [:]
        for exerciseID in Set(day.slots.map(\.exerciseID)) {
            catalog[exerciseID] = try await exercises.exercise(id: exerciseID)
            history[exerciseID] = try await stats.lastPerformance(exerciseID: exerciseID)
        }
        return try await SessionBuilder.build(
            program: program,
            weekIndex: weekIndex,
            day: day,
            exercises: catalog,
            history: history,
            settings: settings.load(),
            id: WorkoutID(newID()),
            device: device,
            now: now()
        )
    }
}
