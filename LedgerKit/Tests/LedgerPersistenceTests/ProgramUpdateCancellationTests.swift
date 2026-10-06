import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// What GRDB does with a write whose task is cancelled (F11 S3 criterion 8; orchestrator ruling 5), established
/// here because the builder's store (S13) relies on it: its save runs in a view's task, which SwiftUI cancels
/// when the screen goes away.
///
/// The finding, for `GRDBProgramRepository.update` on GRDB 7.11:
/// - cancelled before the call, or while the write waits for the writer: `CancellationError`; the change is
///   never called and nothing is stored (GRDB checks the task as its access starts);
/// - cancelled while the transaction runs, as any of its statements starts, rows written or not:
///   `CancellationError`, and the transaction is rolled back (GRDB starts no statement after the cancellation
///   but the rollback, so it never commits);
/// - cancelled as the commit itself starts: still rolled back, on SQLite 3.54 (the interrupt reaches it);
/// - cancelled once the commit has succeeded: too late; the change is stored whole and the call returns.
///
/// So a call stores all of its change or none of it, and throws `CancellationError` only for none. No test
/// here waits on a clock: the task is cancelled from inside the write, by the change, a statement trace or a
/// transaction observer.
@Suite("GRDBProgramRepository · a cancelled update", .tags(.persistence), .timeLimit(.minutes(1)))
struct ProgramUpdateCancellationTests {
    /// How a cancelled update ended, with what the database then held.
    enum Outcome: Equatable, Sendable {
        /// `CancellationError`, and every row as it was.
        case nothing
        /// The call returned the edited program, and that is what is stored.
        case everything
        /// Anything else: half a change, or an answer that does not say what was stored.
        case broken(String)
    }

    /// One update on a fresh database: a small program is saved, `start` starts the update of it with
    /// `edit`, and what the update did is read back.
    struct Run {
        let repositories: Repositories
        let program: Program
        private let before: [String]

        init() async throws {
            repositories = try await Repositories.withProgramExercises()
            let exercises = ProgramRepositoryContract.exercises.map(\.id)
            program = try Seeders.program(weeks: 3, days: 2, slotsPerDay: 2, exercises: exercises)
            try await repositories.programs.save(program)
            before = try await repositories.texts(ProgramUpdateTests.everyRow)
            repositories.clock.advance()
        }

        /// An edit that writes to every table: the block renamed, a week made a deload, a day renamed, a
        /// slot removed with its misses, and a miss recorded.
        static func edit(_ stored: Program) -> Program {
            var edited = stored
            edited.name += ", edited"
            edited.weeks[1].isDeload.toggle()
            edited.days[0].name += ", edited"
            edited.days[1].slots.removeLast()
            edited.days[0].slots[0].misses.insert(1)
            return edited
        }

        func outcome(of result: Result<Program, any Error>) async throws -> Outcome {
            let after = try await repositories.texts(ProgramUpdateTests.everyRow)
            let stored = try await repositories.programs.active()
            switch result {
            case let .success(returned):
                let isWhole = stored == Self.edit(program) && returned == stored
                return isWhole ? .everything : .broken("returned, but the edit is not what is stored")
            case .failure(is CancellationError):
                let isUntouched = after == before && stored == program
                return isUntouched ? .nothing : .broken("threw CancellationError, but rows were written")
            case let .failure(error):
                return .broken("threw \(String(reflecting: error).prefix(160))")
            }
        }
    }

    @Test("Cancelled before the call: CancellationError, the change is never called and nothing is stored")
    func cancelledBeforeItStarts_storesNothing() async throws {
        let run = try await Run()
        let calls = StatementLog()
        let result = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await run.repositories.programs.update(run.program.id) { stored in
                calls.lines.withLock { $0.append("change") }
                return Run.edit(stored)
            }
        }.result
        #expect(try await run.outcome(of: result) == .nothing)
        #expect(calls.lines.withLock { $0 } == [])
    }

    @Test("Cancelled while it waits for the writer: CancellationError, the change is never called, nothing stored")
    func cancelledWhileItWaitsForTheWriter_storesNothing() async throws {
        let run = try await Run()
        let calls = StatementLog()
        let clock = run.repositories.clock
        // `update` reads its clock as it starts and then asks for the writer, which another access holds
        // here. So once the clock is read, the call is under way and its write cannot have begun: it waits,
        // or is about to. (An `update` that went to the database before its clock would never read it, and
        // this test would end at its time limit.)
        let (underWay, begun) = AsyncStream<Void>.makeStream()
        let programs = GRDBProgramRepository(run.repositories.queue) {
            begun.yield()
            return clock.now()
        }
        let hold = WriterHold(run.repositories.queue)
        let task = Task {
            try await programs.update(run.program.id) { stored in
                calls.lines.withLock { $0.append("change") }
                return Run.edit(stored)
            }
        }
        for await _ in underWay {
            break
        }
        task.cancel()
        hold.free()
        #expect(try await run.outcome(of: task.result) == .nothing)
        #expect(calls.lines.withLock { $0 } == [])
    }

    @Test("Cancelled inside its change, after the read: CancellationError, and the transaction is rolled back")
    func cancelledInsideItsChange_storesNothing() async throws {
        let run = try await Run()
        let cancellation = TaskCancelSwitch()
        let result = await cancellation.run {
            try await run.repositories.programs.update(run.program.id) { stored in
                cancellation.fire()
                return Run.edit(stored)
            }
        }.result
        #expect(try await run.outcome(of: result) == .nothing)
    }
}

/// Cancelled while the transaction runs, statement by statement, and once it has committed.
extension ProgramUpdateCancellationTests {
    /// An update whose task is cancelled as its `index`-th statement starts (the first is `BEGIN`): how it
    /// ended, and the statements it ran, each as its first two words.
    static func cancelling(atStatement index: Int) async throws -> (outcome: Outcome, statements: [String]) {
        let run = try await Run()
        let cancellation = TaskCancelSwitch()
        let seen = StatementLog()
        try await run.repositories.queue.writeWithoutTransaction { database in
            database.trace { event in
                guard case let .statement(statement) = event else {
                    return
                }
                let count = seen.lines.withLock { lines in
                    lines.append(statement.sql.split(separator: " ").prefix(2).joined(separator: " "))
                    return lines.count
                }
                if count == index {
                    cancellation.fire()
                }
            }
        }
        let result = await cancellation.run {
            try await run.repositories.programs.update(run.program.id, Run.edit)
        }.result
        try await run.repositories.queue.writeWithoutTransaction { database in database.trace() }
        return try await (run.outcome(of: result), seen.lines.withLock { $0 })
    }

    @Test("Cancelled as any statement before the commit starts, rows written or not: rolled back, nothing stored")
    func cancelledAtAnyStatementBeforeTheCommit_storesNothing() async throws {
        let whole = try await Self.cancelling(atStatement: .max)
        #expect(whole.outcome == .everything)
        #expect(whole.statements.first == "BEGIN IMMEDIATE" && whole.statements.last == "COMMIT TRANSACTION")
        // The edit writes: without a row written before the cancellation, a rollback would show nothing.
        #expect(whole.statements.count { $0.hasPrefix("INSERT") || $0.hasPrefix("UPDATE") } >= 5)
        for index in 1 ..< whole.statements.count {
            let cancelled = try await Self.cancelling(atStatement: index)
            #expect(cancelled.outcome == .nothing, "cancelled at statement \(index), \(whole.statements[index - 1])")
            // The statement the cancellation met may finish; GRDB starts none after it but the rollback.
            #expect(cancelled.statements.count <= index + 1, "statement \(index): ran \(cancelled.statements.count)")
        }
    }

    /// Not GRDB's doing, as the test above is, but SQLite's: the interrupt reaches a commit that has started,
    /// the commit fails, and GRDB rolls back. Should a later SQLite finish that commit, this test alone
    /// fails, and the answer it then finds (stored whole, the call returns) keeps the rule as well.
    @Test("Cancelled as the commit itself starts: the commit fails and is rolled back, nothing stored")
    func cancelledAsTheCommitStarts_storesNothing() async throws {
        let whole = try await Self.cancelling(atStatement: .max)
        let atCommit = try await Self.cancelling(atStatement: whole.statements.count)
        #expect(atCommit.statements.suffix(2) == ["COMMIT TRANSACTION", "ROLLBACK TRANSACTION"])
        #expect(atCommit.outcome == .nothing)
    }

    /// Tells a test that a transaction has committed, before the write that made it returns.
    final class CommitObserver: TransactionObserver, Sendable {
        let onCommit: @Sendable () -> Void

        init(onCommit: @escaping @Sendable () -> Void) {
            self.onCommit = onCommit
        }

        func observes(eventsOfKind _: DatabaseEventKind) -> Bool {
            true
        }

        func databaseDidChange(with _: DatabaseEvent) {}

        func databaseDidCommit(_: Database) {
            onCommit()
        }

        func databaseDidRollback(_: Database) {}
    }

    /// The direction that would hurt: a change that is stored, reported as cancelled, would be sent again by
    /// a caller that keeps what it could not store.
    @Test("Cancelled once the commit has succeeded: too late, the change is stored whole and the call returns")
    func cancelledOnceCommitted_storesEverything() async throws {
        let run = try await Run()
        let cancellation = TaskCancelSwitch()
        let observer = CommitObserver { cancellation.fire() }
        try await run.repositories.queue.writeWithoutTransaction { database in
            database.add(transactionObserver: observer, extent: .databaseLifetime)
        }
        let task = cancellation.run {
            try await run.repositories.programs.update(run.program.id, Run.edit)
        }
        let result = await task.result
        #expect(task.isCancelled)
        #expect(try await run.outcome(of: result) == .everything)
    }
}
