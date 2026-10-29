#if os(iOS)
    import Dependencies
    import Foundation
    @testable import LedgerAppKit
    import LedgerDependencies
    import LedgerDomain
    import LedgerTestSupport

    // F08 S3 adversarial round 1 (G2): onboarding's store is made by the app's root, out of the test's reach,
    // so the test watches the three stores it reads and writes. Each probe forwards to the composition's real
    // store and notes its calls in the journal.
    //
    // The probes' methods run on the main actor, as onboarding's store does. A call that returns to a caller on
    // the same actor continues in the same turn, so by the time a test woken by "… done" runs, the store has
    // finished what it does with that answer (its next suspension, or its end): the failure is shown, or the
    // program is saved. No wait is for time.

    /// The store of programs onboarding saves to.
    final nonisolated class GateProbedPrograms: ProgramRepository {
        private let inner: any ProgramRepository
        private let journal: GateJournal
        private let hold: GateSaveHold

        init(_ inner: any ProgramRepository, _ journal: GateJournal, _ hold: GateSaveHold) {
            self.inner = inner
            self.journal = journal
            self.hold = hold
        }

        @MainActor
        func active() async throws -> Program? {
            journal.note("programs.active")
            return try await inner.active()
        }

        @MainActor
        func save(_ program: Program) async throws {
            journal.note("programs.save begins")
            if let waiter = hold.waiter {
                journal.note("programs.save waits")
                await waiter.sleepThroughCancellation()
            }
            if Task.isCancelled {
                journal.note("programs.save on a cancelled task")
            }
            do {
                try await inner.save(program)
            } catch {
                journal.note("programs.save failed")
                throw error
            }
            journal.note("programs.save done")
        }

        /// F11's `update`, added to the protocol since this suite was written (F08 S2/S3 port): onboarding
        /// never edits a program.
        @MainActor
        func update(_ id: ProgramID, _ change: @Sendable (Program) throws -> Program) async throws -> Program {
            journal.note("programs.update")
            return try await inner.update(id, change)
        }

        @MainActor
        func setActive(_ id: ProgramID) async throws {
            journal.note("programs.setActive")
            try await inner.setActive(id)
        }

        @MainActor
        func delete(_ id: ProgramID) async throws {
            journal.note("programs.delete")
            try await inner.delete(id)
        }

        func observeActive() -> AsyncStream<Program?> {
            journal.note("programs.observeActive")
            return inner.observeActive()
        }
    }

    /// Makes the next save wait until the test lets it go: a save in flight.
    final class GateSaveHold {
        var waiter: GateWaiter?
    }

    /// The catalog onboarding's generator reads.
    final nonisolated class GateProbedExercises: ExerciseRepository {
        private let inner: any ExerciseRepository
        private let journal: GateJournal

        init(_ inner: any ExerciseRepository, _ journal: GateJournal) {
            self.inner = inner
            self.journal = journal
        }

        @MainActor
        func all() async throws -> [Exercise] {
            journal.note("exercises.all begins")
            let exercises = try await inner.all()
            journal.note("exercises.all done \(exercises.count)")
            return exercises
        }

        func exercise(id: ExerciseID) async throws -> Exercise? {
            try await inner.exercise(id: id)
        }

        func search(_ query: String, equipment: Equipment?, muscle: MuscleGroup?) async throws -> [Exercise] {
            try await inner.search(query, equipment: equipment, muscle: muscle)
        }

        func save(_ exercise: Exercise) async throws {
            try await inner.save(exercise)
        }

        func seedIfNeeded(_ catalog: [Exercise], version: Int) async throws {
            try await inner.seedIfNeeded(catalog, version: version)
        }

        func observeAll() -> AsyncStream<[Exercise]> {
            inner.observeAll()
        }
    }

    /// The settings onboarding reads its unit and week start from.
    final nonisolated class GateProbedSettings: SettingsRepository {
        private let inner: any SettingsRepository
        private let journal: GateJournal

        init(_ inner: any SettingsRepository, _ journal: GateJournal) {
            self.inner = inner
            self.journal = journal
        }

        @MainActor
        func load() async throws -> LedgerDomain.Settings {
            journal.note("settings.load begins")
            let settings = try await inner.load()
            journal.note("settings.load done")
            return settings
        }

        func save(_ settings: LedgerDomain.Settings) async throws {
            journal.note("settings.save")
            try await inner.save(settings)
        }

        func seedIfAbsent(_ settings: LedgerDomain.Settings) async throws {
            journal.note("settings.seedIfAbsent")
            try await inner.seedIfAbsent(settings)
        }

        func observe() -> AsyncStream<LedgerDomain.Settings> {
            inner.observe()
        }
    }

    /// Runs `operation` with the keys onboarding's store reads bound as the app binds them, to `composition`'s
    /// real stores when its database is open (each behind a probe that notes its calls in `journal`), with the
    /// date fixed on Wednesday 2026-09-16, real UUIDs, and a Gregorian UTC calendar in en_US. A root must be
    /// hosted, and laid out, inside `operation`: the store keeps the dependencies of the moment it is made.
    ///
    /// That holds for the screen a root draws on its first layout. A root that switches to onboarding later,
    /// while the test is suspended, usually has its store made by SwiftUI's own update, in no task and so
    /// outside this scope (`AppRootFollowingAdversarialTests.delete` has the measurement). The app does not
    /// have this limit: it prepares the keys process-wide when the database opens, which a test must not.
    func withGateDependencies<Result>(
        _ composition: AppComposition,
        _ journal: GateJournal,
        hold: GateSaveHold = GateSaveHold(),
        operation: () async throws -> Result
    ) async rethrows -> Result {
        try await withDependencies {
            composition.bind(&$0)
            if let stores = composition.stores {
                $0.programRepository = GateProbedPrograms(stores.programs, journal, hold)
                $0.exerciseRepository = GateProbedExercises(stores.exercises, journal)
                $0.settingsRepository = GateProbedSettings(stores.settings, journal)
            }
            $0.date = .constant(GateApp.wednesday)
            $0.uuid = UUIDGenerator { UUID() }
            $0.calendar = Fixtures.calendar
            $0.locale = Fixtures.locale
            $0.logger = .disabled
        } operation: {
            try await operation()
        }
    }
#endif
