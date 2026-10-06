import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Synchronization

/// F11 S3 adversarial round 1: what the `ProgramRepository.update` attacks share. Written from the
/// specification's eleven criteria and the protocol's doc comment, before reading the implementation or its
/// tests. The stores are F10 S3's `LinkedStores` (exercises, program 2 and, active, program 1), on an in-memory
/// database, on a WAL file as the apps run it, and in memory.
enum UpdateKit {
    typealias Fixture = LinkedFixture

    enum Place: String, Sendable, CaseIterable, CustomStringConvertible {
        case database, file, memory

        var description: String {
            rawValue
        }
    }

    static let one = S2Kit.programID(1)
    static let two = S2Kit.programID(2)

    /// What a change throws on purpose.
    struct Thrown: Error, Equatable {
        let code: Int
    }

    /// The stores of `place`, and the directory to remove afterwards when they are on a file.
    static func make(_ place: Place, _ name: String = #function) async throws -> (LinkedStores, TemporaryDirectory?) {
        switch place {
        case .database:
            return try await (LinkedStores.make(.database), nil)
        case .memory:
            return try await (LinkedStores.make(.memory), nil)
        case .file:
            let directory = TemporaryDirectory("update\(name)")
            let time = S2Kit.Clock()
            let stores = try opened(directory.file("ledger.sqlite"), time)
            try await stores.exercises.seedIfNeeded(Fixture.exercises, version: 1)
            for program in try [Fixture.program(2), Fixture.program(1)] {
                try await stores.programs.save(program)
            }
            return (stores, directory)
        }
    }

    /// The database's stores over the file at `url`, opened (again) as a launch opens it.
    static func opened(_ url: URL, _ time: S2Kit.Clock) throws -> LinkedStores {
        let queue = try LedgerDatabase.open(at: url)
        let stores = LedgerStores(queue, deviceID: S3Kit.device, now: { time.now })
        return LinkedStores(
            kind: .database, exercises: stores.exercises, programs: stores.programs, workouts: stores.workouts,
            events: stores.events, queue: queue, clock: time
        )
    }

    /// Program `number` as stored, `isActive` included; `nil` when it is deleted. The database is read without
    /// a write. The in-memory stores offer no read by id, so there the program is made active for a moment and
    /// what was active before (a program, or none) is put back.
    static func read(_ stores: LinkedStores, _ number: Int) async throws -> Program? {
        let wanted = S2Kit.programID(number)
        if let queue = stores.queue {
            return try await GRDBProgramRepository(queue).program(id: wanted)
        }
        let active = try await stores.programs.active()
        if active?.id == wanted {
            return active
        }
        do {
            try await stores.programs.setActive(wanted)
        } catch RepositoryError.missingRow {
            return nil
        }
        var read = try await stores.programs.active()
        read?.isActive = false
        if let active {
            try await stores.programs.setActive(active.id)
        } else if let read {
            try await stores.programs.save(read)
        }
        return read
    }

    /// How an `update` ended: "stored" or the error.
    static func attempt(
        _ programs: any ProgramRepository,
        _ id: ProgramID = one,
        _ change: @Sendable (Program) throws -> Program
    ) async -> String {
        do {
            _ = try await programs.update(id, change)
            return "stored"
        } catch {
            return "\(error)"
        }
    }

    /// How a `save` ended: "stored" or the error.
    static func attemptSave(_ programs: any ProgramRepository, _ program: Program) async -> String {
        do {
            try await programs.save(program)
            return "stored"
        } catch {
            return "\(error)"
        }
    }

    /// The number a program's name counts, for changes that add one to it.
    static func count(_ program: Program?) -> Int {
        Int(program?.name ?? "") ?? -1
    }

    /// A change that counts one more in the program's name.
    static let increment: @Sendable (Program) throws -> Program = { program in
        var changed = program
        changed.name = "\(count(program) + 1)"
        return changed
    }

    /// Sets the stored name of program 1 to "0", so that `increment` counts from there.
    static func zero(_ stores: LinkedStores) async throws {
        _ = try await stores.programs.update(one) { program in
            var changed = program
            changed.name = "0"
            return changed
        }
    }

    /// How many rows `body` inserted, updated or deleted on `queue` (SQLite's own count of changes). A
    /// statement that matches no row is not a write: `save` runs one for an active program that stays active.
    static func rowsChanged(on queue: DatabaseQueue, during body: () async throws -> Void) async throws -> Int {
        let before = try await queue.read { $0.totalChangesCount }
        try await body()
        return try await queue.read { $0.totalChangesCount } - before
    }
}

/// `update` as the sequence the requirement replaces: read, change and save in three steps. The attacks are
/// run against it once, to show that they notice a lost update when there is one.
struct ThreeStepPrograms: ProgramRepository {
    let base: any ProgramRepository

    func update(_ id: ProgramID, _ change: @Sendable (Program) throws -> Program) async throws -> Program {
        guard let stored = try await base.active(), stored.id == id else {
            throw RepositoryError.missingRow("program \(id.rawValue.uuidString)")
        }
        await Task.yield()
        let changed = try change(stored)
        await Task.yield()
        try await base.save(changed)
        return changed
    }

    func active() async throws -> Program? {
        try await base.active()
    }

    func save(_ program: Program) async throws {
        try await base.save(program)
    }

    func setActive(_ id: ProgramID) async throws {
        try await base.setActive(id)
    }

    func delete(_ id: ProgramID) async throws {
        try await base.delete(id)
    }

    func observeActive() -> AsyncStream<Program?> {
        base.observeActive()
    }
}

/// Everything a store holds that an update could have touched: every row of the database, or, in memory, both
/// programs and which is active. Two of them are compared in a line, never printed whole.
struct UpdateSnapshot {
    let rows: [String: [String]]
    let programs: [Program?]
    let active: ProgramID?

    init(_ stores: LinkedStores) async throws {
        rows = try await stores.dump()
        active = try await stores.programs.active()?.id
        programs = try await [UpdateKit.read(stores, 1), UpdateKit.read(stores, 2)]
    }

    /// `nil` when nothing differs, else where it does.
    func difference(from other: UpdateSnapshot) -> String? {
        if let changed = LinkedStores.difference(other.rows, rows) {
            return changed
        }
        guard active == other.active else {
            return "the active program changed"
        }
        for (index, pair) in zip(programs, other.programs).enumerated() where pair.0 != pair.1 {
            let line = LinkedDifference.of(pair.0, pair.1, "program \(index + 1)")
            return line ?? "program \(index + 1) differs in its activity"
        }
        return nil
    }
}

/// A count several tasks and a store's own thread add to.
final class UpdateTally: Sendable {
    private let value = Mutex(0)

    var count: Int {
        value.withLock { $0 }
    }

    var isZero: Bool {
        count < 1
    }

    func add() {
        value.withLock { $0 += 1 }
    }
}

/// A gate a synchronous change waits at, with a limit so that a store that never lets the other side run fails
/// its test instead of hanging the suite. `wait()` answers whether it was opened in time.
final class UpdateGate: Sendable {
    private let opened = DispatchSemaphore(value: 0)
    private let reached = Mutex<CheckedContinuation<Void, Never>?>(nil)
    private let arrived = Mutex(false)

    /// Called by the change, on the store's thread: tells the test it is inside, then waits to be let go.
    func wait(seconds: Int = 20) -> Bool {
        arrived.withLock { $0 = true }
        reached.withLock { waiting in
            waiting?.resume()
            waiting = nil
        }
        return opened.wait(timeout: .now() + .seconds(seconds)) == .success
    }

    /// Returns once a change is waiting at the gate.
    func untilReached() async {
        await withCheckedContinuation { continuation in
            let isThere = arrived.withLock { $0 }
            if isThere {
                continuation.resume()
            } else {
                reached.withLock { $0 = continuation }
                // The change may have arrived between the two locks.
                if arrived.withLock({ $0 }) {
                    reached.withLock { waiting in
                        waiting?.resume()
                        waiting = nil
                    }
                }
            }
        }
    }

    func open() {
        opened.signal()
    }
}
