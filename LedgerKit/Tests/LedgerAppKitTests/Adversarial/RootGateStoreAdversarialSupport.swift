import Dispatch
import Foundation
import GRDB
@testable import LedgerAppKit
import LedgerDependencies
import LedgerDomain
import LedgerPersistence
import LedgerTestSupport
import Synchronization

// F08 S3 adversarial round 1 (G2): the real launch and the real stores, on a database file of the test's own,
// with one journal of what happened in order: the launch's events, the statements the database ran, and the
// values the store handed to the gate.

/// A composition on a database file in a temporary directory of its own (testing-strategy §3 rule 3), as
/// `Harness` builds one, with everything the launch does noted in `journal`: "launch began seedCatalog",
/// "launch failed seedCatalog", "handler", "companion". Booting twice from one `GateApp` is a relaunch on the
/// same file.
final class GateApp {
    /// Wednesday 2026-09-16, 05:20 UTC: criterion 6's day.
    nonisolated static let wednesday = Fixtures.now
    nonisolated static let deviceUUID = UUID(uuidString: "00000000-0000-4000-8000-0000000000D8") ?? UUID()

    let directory: URL
    let journal = GateJournal()
    /// Called with each of the launch's events as it happens, in the launch's own turn of the main actor: a
    /// test reads there what a gate or a root shows at that very step.
    var onEvent: ((LaunchEvent) -> Void)?

    init(_ name: String = #function) {
        let safe = name.filter { $0.isLetter || $0.isNumber }
        directory = FileManager.default.temporaryDirectory
            .appending(path: "LedgerGateAdversarial-\(ProcessInfo.processInfo.processIdentifier)-\(safe)")
        try? FileManager.default.removeItem(at: directory) // absent unless an earlier run of this test crashed
    }

    var databaseURL: URL {
        directory.appending(path: "Database/ledger.sqlite")
    }

    /// A composition over `databaseURL`, not yet booted.
    func composition() -> AppComposition {
        let notes = journal
        return AppComposition(
            AppComposition.Environment(
                databaseURL: databaseURL,
                now: { Self.wednesday },
                newID: { Self.deviceUUID },
                logger: .disabled,
                record: { [weak self] event in
                    notes.note("launch \(Self.name(event))")
                    self?.onEvent?(event)
                },
                assignMirroringHandler: { notes.note("handler") },
                activateCompanionSession: { notes.note("companion") },
                preparesDependencies: false,
                processStart: nil
            )
        )
    }

    /// An event as the journal spells it: "began seedCatalog", "failed resumeWorkout".
    nonisolated static func name(_ event: LaunchEvent) -> String {
        switch event {
        case let .began(step): "began \(step.rawValue)"
        case let .failed(step): "failed \(step.rawValue)"
        }
    }

    /// A composition booted as `App.init` boots it, with every statement its connection runs noted as
    /// "sql <statement>".
    func booted() -> AppComposition {
        let composition = composition()
        composition.boot()
        if let queue = composition.stores?.queue {
            Self.trace(queue, into: journal)
        }
        return composition
    }

    /// Opens the file the composition will open, for a test to arrange it, then closes it.
    func arrange(_ updates: @escaping @Sendable (DatabaseQueue) async throws -> Void) async throws {
        let queue = try LedgerDatabase.open(at: databaseURL)
        try await updates(queue)
        try queue.close()
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory) // cleanup only: a leftover temporary file fails nothing
    }

    /// Notes every statement `queue`'s connection runs. Not on the main actor: SQLite calls back on GRDB's queue.
    private nonisolated static func trace(_ queue: DatabaseQueue, into journal: GateJournal) {
        queue.inDatabase { database in
            database.trace { event in
                journal.note("sql \(event)")
            }
        }
    }
}

nonisolated extension GateJournal {
    /// The statements that read which program is active (`GRDBProgramRepository`'s query).
    var activeProgramReads: [String] {
        entries.filter { $0.hasPrefix("sql ") && $0.contains("FROM program WHERE is_active = 1") }
    }

    /// The position of the first statement that touches a program table, if any ran.
    var firstProgramStatement: Int? {
        entries.firstIndex { $0.hasPrefix("sql ") && $0.contains("program") }
    }

    /// Suspends until a relayed stream has handed `value` (a program's id, or "none") to its consumer at or
    /// after `mark`, and the consumer has come back for the next value or the stream has ended: the gate has
    /// dealt with it.
    @discardableResult
    func untilDealtWith(_ value: String, since mark: Int) async -> Bool {
        await until { entries in
            let recent = entries.dropFirst(mark)
            guard let handed = recent.firstIndex(where: { $0.hasSuffix(" value \(value)") }) else {
                return false
            }
            let stream = entries[handed].split(separator: " ").dropFirst().first.map(String.init) ?? "?"
            return entries[(handed + 1)...].contains { $0 == "relay \(stream) asks" || $0 == "relay \(stream) ended" }
        }
    }
}

/// A store of programs that relays the real one's `observeActive()` one value at a time and notes, in the
/// journal, each value it hands over ("relay 0 value <id or none>"), each time its consumer asks for the next
/// ("relay 0 asks") and the stream's end ("relay 0 ended"). The values, their order and the stream's end are the
/// real store's; the relay adds only the notes, so a test knows when the gate has dealt with a value.
final nonisolated class GateRelayedPrograms: ProgramRepository {
    private let inner: any ProgramRepository
    private let journal: GateJournal
    private let streams = Mutex(0)

    init(_ inner: any ProgramRepository, _ journal: GateJournal) {
        self.inner = inner
        self.journal = journal
    }

    func active() async throws -> Program? {
        journal.note("relay active()")
        return try await inner.active()
    }

    func save(_ program: Program) async throws {
        try await inner.save(program)
    }

    func setActive(_ id: ProgramID) async throws {
        try await inner.setActive(id)
    }

    func delete(_ id: ProgramID) async throws {
        try await inner.delete(id)
    }

    func observeActive() -> AsyncStream<Program?> {
        let index = streams.withLock { count -> Int in
            defer { count += 1 }
            return count
        }
        let relay = Relay(inner.observeActive(), name: "relay \(index)", journal)
        return AsyncStream(unfolding: { await relay.next() })
    }

    /// One relayed stream. Unchecked: an `AsyncStream`'s `unfolding` is called by its one consumer, one call at
    /// a time, so the iterator is never used from two tasks.
    private final class Relay: @unchecked Sendable {
        private var iterator: AsyncStream<Program?>.Iterator
        private let name: String
        private let journal: GateJournal

        init(_ stream: AsyncStream<Program?>, name: String, _ journal: GateJournal) {
            iterator = stream.makeAsyncIterator()
            self.name = name
            self.journal = journal
        }

        func next() async -> Program?? {
            journal.note("\(name) asks")
            guard let value = await iterator.next() else {
                journal.note("\(name) ended")
                return nil
            }
            journal.note("\(name) value \(GatePrograms.name(value))")
            return .some(value)
        }
    }
}

/// Programs for the store tests, written by the Domain's generator over the bundled catalog, each with ids of
/// its own.
nonisolated enum GatePrograms {
    struct Unavailable: Error {}

    static func make(isActive: Bool = true, days: DaysPerWeek = .four) throws -> Program {
        guard let start = CivilDate(year: 2026, month: 9, day: 14) else {
            throw Unavailable()
        }
        var program = try ProgramTemplates.program(
            ProgramTemplates.Request(goal: .both, days: days, units: .lb, startDate: start),
            catalog: ExerciseCatalog.seed(),
            id: ProgramID(UUID()),
            newID: { UUID() }
        )
        program.isActive = isActive
        return program
    }

    /// How the journal names what a stream reported.
    static func name(_ program: Program?) -> String {
        program?.id.rawValue.uuidString ?? "none"
    }

    /// Seeds the bundled catalog into `queue` and saves `programs`, as a launch and a lifter did before.
    static func store(_ programs: [Program], in queue: DatabaseQueue) async throws {
        try await GRDBExerciseRepository(queue).seedIfNeeded(ExerciseCatalog.seed(), version: ExerciseCatalog.version)
        for program in programs {
            try await GRDBProgramRepository(queue).save(program)
        }
    }
}

/// Holds the database's one connection until freed, so whatever the launch does next waits (a slow pass).
final nonisolated class GateWriterHold: @unchecked Sendable {
    private let held = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)

    init(_ queue: DatabaseQueue) {
        DispatchQueue.global().async { [held, release] in
            queue.inDatabase { _ in
                held.signal()
                release.wait()
            }
        }
        held.wait()
    }

    func free() {
        release.signal()
    }
}
