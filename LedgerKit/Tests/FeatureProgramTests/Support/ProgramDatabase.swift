import Foundation
import LedgerDomain
import LedgerPersistence
import LedgerTestSupport

/// The repositories of one in-memory database (F05), migrated, with the bundled catalog seeded, the spec's
/// seed program saved as the active one and the settings in pounds: where a store test checks what only the
/// database's transactions show (F11 S13 criterion 2).
nonisolated struct ProgramDatabase: Sendable {
    let exercises: GRDBExerciseRepository
    let programs: GRDBProgramRepository
    let workouts: GRDBWorkoutRepository
    let settings: GRDBSettingsRepository
    let events: GRDBWorkoutEventStore

    init() async throws {
        let queue = try LedgerDatabase.inMemory()
        let now: @Sendable () -> Date = { Fixtures.now }
        exercises = GRDBExerciseRepository(queue, now: now)
        programs = GRDBProgramRepository(queue, now: now)
        workouts = GRDBWorkoutRepository(queue, now: now)
        settings = GRDBSettingsRepository(queue, now: now)
        events = GRDBWorkoutEventStore(queue, now: now)
        try await exercises.seedIfNeeded(ExerciseCatalog.seed(), version: ExerciseCatalog.version)
        try await programs.save(Fixtures.seedProgram())
        try await settings.save(Fixtures.settingsLb)
    }
}
