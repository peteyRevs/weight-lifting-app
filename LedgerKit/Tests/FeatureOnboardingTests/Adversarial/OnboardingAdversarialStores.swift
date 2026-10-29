import Dependencies
import Foundation
import LedgerDomain
import LedgerTestSupport
import Synchronization

// F08 S2 adversarial round 1: the three stores onboarding reads and writes, wrapped so a test can count, hold
// and refuse each call (`CallScript`), and the id generator it injects.

/// The program store, with every save noted, counted and open to a plan.
final nonisolated class ProbedPrograms: ProgramRepository {
    let base: InMemoryProgramRepository
    let script = CallScript()
    private let journal: Journal
    private let record = Mutex<(offered: [Program], saved: [Program])>(([], []))

    init(_ base: InMemoryProgramRepository, _ journal: Journal) {
        self.base = base
        self.journal = journal
    }

    /// Every program handed to `save`, and those the store kept.
    var offered: [Program] {
        record.withLock { $0.offered }
    }

    var saved: [Program] {
        record.withLock { $0.saved }
    }

    func active() async throws -> Program? {
        try await base.active()
    }

    func save(_ program: Program) async throws {
        record.withLock { $0.offered.append(program) }
        try await script.run("programs.save", in: journal)
        try await base.save(program)
        record.withLock { $0.saved.append(program) }
    }

    /// Onboarding never edits a stored program (F11's `update`, added since this round): noted, so that a test
    /// that reads the journal would see a call it does not expect.
    func update(_ id: ProgramID, _ change: @Sendable (Program) throws -> Program) async throws -> Program {
        journal.note("programs.update")
        return try await base.update(id, change)
    }

    func setActive(_ id: ProgramID) async throws {
        journal.note("programs.setActive")
        try await base.setActive(id)
    }

    func delete(_ id: ProgramID) async throws {
        journal.note("programs.delete")
        try await base.delete(id)
    }

    func observeActive() -> AsyncStream<Program?> {
        base.observeActive()
    }
}

/// The settings store, with every read noted and open to a plan.
final nonisolated class ProbedSettings: SettingsRepository {
    let base: InMemorySettingsRepository
    let script = CallScript()
    private let journal: Journal

    init(_ base: InMemorySettingsRepository, _ journal: Journal) {
        self.base = base
        self.journal = journal
    }

    func load() async throws -> Settings {
        try await script.run("settings.load", in: journal)
        return try await base.load()
    }

    func save(_ settings: Settings) async throws {
        journal.note("settings.save")
        try await base.save(settings)
    }

    func seedIfAbsent(_ settings: Settings) async throws {
        journal.note("settings.seedIfAbsent")
        try await base.seedIfAbsent(settings)
    }

    func observe() -> AsyncStream<Settings> {
        base.observe()
    }
}

/// The exercise store, with every read of the catalog noted and open to a plan.
final nonisolated class ProbedExercises: ExerciseRepository {
    let base: InMemoryExerciseRepository
    let script = CallScript()
    private let journal: Journal

    init(_ base: InMemoryExerciseRepository, _ journal: Journal) {
        self.base = base
        self.journal = journal
    }

    func all() async throws -> [Exercise] {
        try await script.run("exercises.all", in: journal)
        return try await base.all()
    }

    func exercise(id: ExerciseID) async throws -> Exercise? {
        try await base.exercise(id: id)
    }

    func search(_ query: String, equipment: Equipment?, muscle: MuscleGroup?) async throws -> [Exercise] {
        try await base.search(query, equipment: equipment, muscle: muscle)
    }

    func save(_ exercise: Exercise) async throws {
        journal.note("exercises.save")
        try await base.save(exercise)
    }

    func seedIfNeeded(_ catalog: [Exercise], version: Int) async throws {
        journal.note("exercises.seedIfNeeded")
        try await base.seedIfNeeded(catalog, version: version)
    }

    func observeAll() -> AsyncStream<[Exercise]> {
        base.observeAll()
    }
}

/// The injected id generator: `Fixtures.uuid(7000)`, `uuid(7001)` … and a record of every id it gave.
final nonisolated class DrawnIDs: Sendable {
    static let first = 7000
    private let drawn = Mutex<[UUID]>([])

    var generator: UUIDGenerator {
        UUIDGenerator { [self] in
            drawn.withLock { drawn in
                let id = Fixtures.uuid(Self.first + drawn.count)
                drawn.append(id)
                return id
            }
        }
    }

    var all: [UUID] {
        drawn.withLock { $0 }
    }
}
