import Foundation
@testable import LedgerDomain
import Testing

// Conformances written from the F02 brief's protocol listing: if a requirement's signature
// drifts from the brief, this file stops compiling.

private struct BriefExerciseRepository: ExerciseRepository {
    func all() async throws -> [Exercise] {
        [Fixtures.bench]
    }

    func exercise(id: ExerciseID) async throws -> Exercise? {
        Fixtures.catalog[id]
    }

    func search(_: String, equipment _: Equipment?, muscle _: MuscleGroup?) async throws -> [Exercise] {
        []
    }

    func save(_: Exercise) async throws {}
    func seedIfNeeded(_: [Exercise], version _: Int) async throws {}
    func observeAll() -> AsyncStream<[Exercise]> {
        AsyncStream { $0.finish() }
    }
}

private struct BriefProgramRepository: ProgramRepository {
    func active() async throws -> Program? {
        nil
    }

    func save(_: Program) async throws {}
    func update(_ id: ProgramID, _: @Sendable (Program) throws -> Program) async throws -> Program {
        throw RepositoryError.missingRow("program \(id.rawValue.uuidString)")
    }

    func setActive(_: ProgramID) async throws {}
    func delete(_: ProgramID) async throws {}
    func observeActive() -> AsyncStream<Program?> {
        AsyncStream { $0.finish() }
    }
}

private struct BriefWorkoutRepository: WorkoutRepository {
    func materialize(_: WorkoutState, slotUpdates _: [Slot], droppingLog _: Bool) async throws -> Bool {
        false
    }

    func workout(id _: WorkoutID) async throws -> WorkoutState? {
        nil
    }

    func recent(limit _: Int) async throws -> [WorkoutState] {
        []
    }

    func workouts(in _: Range<Date>) async throws -> [WorkoutState] {
        []
    }

    func updateSets(workoutExerciseID _: WorkoutExerciseID, sets _: [LoggedSet]) async throws {}
    func updateSets(_: [WorkoutExerciseID: [LoggedSet]], of _: WorkoutID) async throws {}
    func delete(id _: WorkoutID) async throws {}
    func observeRecent(limit _: Int) -> AsyncStream<[WorkoutState]> {
        AsyncStream { $0.finish() }
    }

    func historyEntries() async throws -> [HistoryEntry] {
        []
    }

    func observeHistoryEntries() -> AsyncStream<[HistoryEntry]> {
        AsyncStream { $0.finish() }
    }

    func observeWorkout(id _: WorkoutID) -> AsyncStream<RecordedWorkout?> {
        AsyncStream { $0.finish() }
    }
}

private struct BriefSettingsRepository: SettingsRepository {
    func load() async throws -> Settings {
        .default
    }

    func save(_: Settings) async throws {}

    func seedIfAbsent(_: Settings) async throws {}

    func switchUnits(_: Settings) async throws {}
    func observe() -> AsyncStream<Settings> {
        AsyncStream { $0.finish() }
    }
}

private struct BriefStatsQueries: StatsQueries {
    func lastPerformance(exerciseID _: ExerciseID) async throws -> LastPerformance? {
        nil
    }

    func bestSet(exerciseID _: ExerciseID) async throws -> (weight: Weight, reps: Reps)? {
        (pounds("200"), .one)
    }

    func bestSets() async throws -> [ExerciseID: BestSet] {
        [:]
    }

    func exerciseSessions(exerciseID _: ExerciseID) async throws -> [ExerciseSession] {
        []
    }

    func observeExerciseSessions(exerciseID _: ExerciseID) -> AsyncStream<[ExerciseSession]> {
        AsyncStream { $0.finish() }
    }

    func observeLibraryStats(recentLimit _: Int) -> AsyncStream<LibraryStats> {
        AsyncStream { $0.finish() }
    }

    func bestE1RM(exerciseID _: ExerciseID) async throws -> Weight? {
        nil
    }

    func e1RMByWeek(
        exerciseID _: ExerciseID,
        lastWeeks _: Int,
        calendar _: WeekCalendar
    ) async throws -> [WeekKey: Weight] {
        [:]
    }

    func weeklyVolume(in _: Range<Date>) async throws -> Volume {
        .zero
    }

    func sessionsCompleted(in _: Range<Date>) async throws -> Int {
        0
    }

    func sessionCount(exerciseID _: ExerciseID) async throws -> Int {
        0
    }

    func personalRecords(exerciseID _: ExerciseID) async throws -> [PersonalRecord] {
        []
    }

    func recentlyLogged(limit _: Int) async throws -> [ExerciseID] {
        []
    }

    func bests(before _: WorkoutState, for _: Set<ExerciseID>) async throws -> PersonalRecords.Bests {
        PersonalRecords.Bests()
    }
}

/// F19's `CompanionTransport`, from the brief's signatures.
private struct BriefShapes: CompanionTransport {
    var receivedContext: AsyncStream<CompanionContext> {
        AsyncStream { $0.finish() }
    }

    var receivedFiles: AsyncStream<CompanionFile> {
        AsyncStream { $0.finish() }
    }

    var receivedRecords: AsyncStream<FinishedWorkoutRecord> {
        AsyncStream { $0.finish() }
    }

    var isPaired: Bool {
        get async { false }
    }

    var isWatchAppInstalled: Bool {
        get async { false }
    }

    func updateContext(_: CompanionContext) async throws {}

    func transfer(_: CompanionFile) async throws {}

    func enqueue(_: FinishedWorkoutRecord) async throws {}
}

/// F17's `LiveWorkoutTransport`, from the brief's signatures.
private struct BriefLiveWorkoutTransport: LiveWorkoutTransport {
    var incoming: AsyncStream<WireFrame> {
        AsyncStream { $0.finish() }
    }

    var link: AsyncStream<Bool> {
        AsyncStream { $0.finish() }
    }

    func send(_: WireFrame) async throws {
        throw TransportError.unreachable
    }
}

/// F16's `HealthStore` and `RemoteSessionChannel`, from the brief's signatures.
private struct BriefHealthStore: HealthStore, RemoteSessionChannel {
    var events: AsyncStream<HealthSessionEvent> {
        AsyncStream { $0.finish() }
    }

    var remoteChannel: any RemoteSessionChannel {
        self
    }

    var connection: AsyncStream<Bool> {
        AsyncStream { $0.finish() }
    }

    var incoming: AsyncStream<[Data]> {
        AsyncStream { $0.finish() }
    }

    func authorization() async -> HealthAuthorization {
        .notDetermined
    }

    func requestAuthorization() async throws -> HealthAuthorization {
        .authorized
    }

    func startSession(workoutID _: WorkoutID, at _: Date) async throws {}

    func heartRate() async -> AsyncStream<HeartRateSample> {
        AsyncStream { $0.finish() }
    }

    func endSession(metadata _: HealthWorkoutMetadata, at _: Date) async throws -> HealthWorkoutRecord {
        throw HealthError.noActiveSession
    }

    func discardSession() async throws {}

    func recoverActiveSession() async throws -> Bool {
        false
    }

    func noteStartRequestedByPhone() {}

    func requestWatchStart() async throws {}

    func saveWorkout(
        metadata _: HealthWorkoutMetadata,
        start _: Date,
        end _: Date
    ) async throws -> HealthWorkoutRecord {
        throw HealthError.notAuthorized
    }

    func workoutRecord(healthKitUUID _: UUID) async throws -> HealthWorkoutRecord? {
        nil
    }

    func send(_: Data) async throws {}
}

@Suite("Protocols (adversarial)", .tags(.domain))
struct ProtocolsAdversarialTests {}

extension ProtocolsAdversarialTests {
    @Test("Every brief protocol accepts a conformance written from the brief's signatures.")
    func protocols_acceptBriefConformances() async throws {
        let exercises: any ExerciseRepository = BriefExerciseRepository()
        let stats: any StatsQueries = BriefStatsQueries()
        let settings: any SettingsRepository = BriefSettingsRepository()
        let programs: any ProgramRepository = BriefProgramRepository()
        let workouts: any WorkoutRepository = BriefWorkoutRepository()
        let shapes: [any Sendable] = [
            BriefHealthStore() as any HealthStore,
            BriefLiveWorkoutTransport() as any LiveWorkoutTransport,
            BriefShapes() as any CompanionTransport
        ]
        #expect(try await exercises.all() == [Fixtures.bench])
        #expect(try await stats.bestSet(exerciseID: Fixtures.bench.id)?.weight == pounds("200"))
        #expect(try await settings.load() == .default)
        #expect(try await programs.active() == nil)
        #expect(try await workouts.recent(limit: 5).isEmpty)
        #expect(shapes.count == 3)
    }
}
