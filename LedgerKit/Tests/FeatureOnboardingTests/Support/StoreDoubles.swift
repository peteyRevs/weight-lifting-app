import Foundation
import LedgerDomain
import Synchronization

/// What a failing double throws: "a repository may throw" (brief, criterion 7).
nonisolated struct StoreFailure: Error, Equatable {}

/// A program store that forwards to another and keeps every program a `save` wrote, in order: how a test counts
/// saves. The protocol itself can only say which program is active.
final nonisolated class RecordingPrograms: ProgramRepository {
    private let inner: any ProgramRepository
    private let written = Mutex<[Program]>([])
    /// When set, `save` waits there after the write has succeeded.
    private let afterWrite: Gate?

    init(_ inner: any ProgramRepository, afterWrite: Gate? = nil) {
        self.inner = inner
        self.afterWrite = afterWrite
    }

    /// Every program saved, oldest first.
    var saved: [Program] {
        written.withLock { $0 }
    }

    func save(_ program: Program) async throws {
        try await inner.save(program)
        written.withLock { $0.append(program) }
        await afterWrite?.pass()
    }

    func active() async throws -> Program? {
        try await inner.active()
    }

    func setActive(_ id: ProgramID) async throws {
        try await inner.setActive(id)
    }

    func delete(_ id: ProgramID) async throws {
        try await inner.delete(id)
    }

    func observeActive() -> AsyncStream<Program?> {
        inner.observeActive()
    }
}

/// A program store whose `save` always throws and writes nothing.
nonisolated struct FailingPrograms: ProgramRepository {
    func save(_: Program) async throws {
        throw StoreFailure()
    }

    func active() async throws -> Program? {
        nil
    }

    func setActive(_: ProgramID) async throws {}

    func delete(_: ProgramID) async throws {}

    func observeActive() -> AsyncStream<Program?> {
        AsyncStream { $0.finish() }
    }
}

/// A settings store that cannot be read.
nonisolated struct FailingSettings: SettingsRepository {
    func load() async throws -> Settings {
        throw StoreFailure()
    }

    func save(_: Settings) async throws {}

    func observe() -> AsyncStream<Settings> {
        AsyncStream { $0.finish() }
    }
}

/// An exercise store whose catalog read throws, or, given a gate, waits there before answering from `inner`.
nonisolated struct StubbedExercises: ExerciseRepository {
    var inner: (any ExerciseRepository)?
    var gate: Gate?

    func all() async throws -> [Exercise] {
        await gate?.pass()
        guard let inner else {
            throw StoreFailure()
        }
        return try await inner.all()
    }

    func exercise(id _: ExerciseID) async throws -> Exercise? {
        nil
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

/// A place where a double waits until the test lets it through, so that a test can act while a save is under
/// way without sleeping: the double calls `pass()`, the test awaits `entered()`, acts, then calls `open()`.
/// Once open it stays open. A task cancelled while it waits passes at once, as a cancelled read returns.
final nonisolated class Gate: Sendable {
    private let arrivals = AsyncStream<Void>.makeStream()
    private let openings = AsyncStream<Void>.makeStream()
    private let isOpen = Mutex(false)

    func pass() async {
        arrivals.continuation.yield()
        guard !isOpen.withLock(\.self) else {
            return
        }
        for await _ in openings.stream {
            return
        }
    }

    /// Returns once a caller has reached `pass()`.
    func entered() async {
        for await _ in arrivals.stream {
            return
        }
    }

    func open() {
        isOpen.withLock { $0 = true }
        openings.continuation.yield()
    }
}
