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
    func delete(id _: WorkoutID) async throws {}
    func observeRecent(limit _: Int) -> AsyncStream<[WorkoutState]> {
        AsyncStream { $0.finish() }
    }
}

private struct BriefSettingsRepository: SettingsRepository {
    func load() async throws -> Settings {
        .default
    }

    func save(_: Settings) async throws {}
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

private struct BriefShapes: HealthStore, LiveWorkoutTransport, CompanionTransport {}

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
        let shapes: [any Sendable] = [BriefShapes() as any HealthStore, BriefShapes() as any CompanionTransport]
        #expect(try await exercises.all() == [Fixtures.bench])
        #expect(try await stats.bestSet(exerciseID: Fixtures.bench.id)?.weight == pounds("200"))
        #expect(try await settings.load() == .default)
        #expect(try await programs.active() == nil)
        #expect(try await workouts.recent(limit: 5).isEmpty)
        #expect(shapes.count == 2)
    }
}
