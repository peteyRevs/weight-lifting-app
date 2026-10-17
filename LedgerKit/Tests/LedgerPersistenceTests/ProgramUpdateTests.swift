import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// `GRDBProgramRepository.update` at the level of rows and statements, where the shared contract
/// (`ProgramRepositoryContract`'s update clauses) cannot look: one transaction with the change inside it,
/// only the rows that changed written, and nothing at all for an update that changes nothing or is refused
/// (F11 S3 criteria 1 and 3 to 6).
@Suite("GRDBProgramRepository · update", .tags(.persistence), .timeLimit(.minutes(1)))
struct ProgramUpdateTests {
    typealias Contract = ProgramRepositoryContract
    typealias ChangeRefused = ProgramUpdateInterleavingTests.ChangeRefused

    /// Every row of the five program tables, live or deleted, with when it was last written: equal before
    /// and after a call that wrote nothing.
    static let everyRow = """
    SELECT 'program ' || id || ' ' || updated_at || ' ' || quote(deleted_at) || ' ' || is_active FROM program
    UNION ALL SELECT 'week ' || id || ' ' || updated_at || ' ' || quote(deleted_at) FROM program_week
    UNION ALL SELECT 'day ' || id || ' ' || updated_at || ' ' || quote(deleted_at) FROM day_template
    UNION ALL SELECT 'slot ' || id || ' ' || updated_at || ' ' || quote(deleted_at) || ' ' || exercise_id FROM slot
    UNION ALL SELECT 'miss ' || id || ' ' || updated_at || ' ' || quote(deleted_at) FROM slot_miss
    ORDER BY 1
    """

    /// The rows written at `stamp`, by table: program, week, day, slot, miss.
    static let writtenAt = """
    SELECT (SELECT COUNT(*) FROM program WHERE updated_at = :stamp) || ' '
        || (SELECT COUNT(*) FROM program_week WHERE updated_at = :stamp) || ' '
        || (SELECT COUNT(*) FROM day_template WHERE updated_at = :stamp) || ' '
        || (SELECT COUNT(*) FROM slot WHERE updated_at = :stamp) || ' '
        || (SELECT COUNT(*) FROM slot_miss WHERE updated_at = :stamp)
    """

    /// The contract program saved in a fresh database, and the clock moved on, so a row written from here
    /// on has a stamp of its own.
    static func saved() async throws -> (repositories: Repositories, program: Program) {
        let repositories = try await Repositories.withProgramExercises()
        let program = try Contract.program()
        try await repositories.programs.save(program)
        repositories.clock.advance()
        return (repositories, program)
    }

    static func renamed(_ program: Program) -> Program {
        var changed = program
        changed.name += " (renamed)"
        return changed
    }

    @Test("An update is one write transaction: the read, then the change, then the rows, then the commit")
    func update_isOneTransaction_withItsChangeBetweenTheReadAndTheWrite() async throws {
        let (repositories, program) = try await Self.saved()
        let log = StatementLog()
        try await repositories.queue.writeWithoutTransaction { database in
            database.trace { event in
                if case let .statement(statement) = event {
                    log.lines.withLock { $0.append(String(statement.sql.prefix { $0 != " " })) }
                }
            }
        }
        _ = try await repositories.programs.update(program.id) { stored in
            log.lines.withLock { $0.append("change") }
            return Self.renamed(stored)
        }
        try await repositories.queue.writeWithoutTransaction { database in database.trace() }
        let steps = log.lines.withLock { $0 }
        let change = try #require(steps.firstIndex(of: "change"))
        let firstWrite = try #require(steps.firstIndex { $0 == "INSERT" || $0 == "UPDATE" })
        #expect(steps.first == "BEGIN" && steps.last == "COMMIT")
        #expect(steps.count { $0 == "BEGIN" || $0 == "COMMIT" } == 2)
        #expect(steps.count { $0 == "change" } == 1)
        #expect(steps[1 ..< change].allSatisfy { $0 == "SELECT" } && change > 1)
        #expect(firstWrite > change)
    }

    @Test("An update writes only the rows its change altered, and soft-deletes what the result no longer has")
    func update_writesOnlyTheRowsThatChanged() async throws {
        let (repositories, program) = try await Self.saved()
        let edit = repositories.clock.timestamp
        let returned = try await repositories.programs.update(program.id) { try Contract.edited($0) }
        let isEdited = try returned == Contract.edited(program)
        #expect(isEdited)
        // As `save` writes the same edit (`ProgramRepositoryTests.partialUpdate_diffsChildren`): the last day
        // went, with its 5 slots and their 6 misses; one slot and one miss came.
        #expect(try await repositories.texts(ProgramRepositoryTests.liveCounts) == ["1 8 3 16 15"])
        let deleted = """
        SELECT (SELECT COUNT(*) FROM day_template WHERE deleted_at = :edit) || ' '
            || (SELECT COUNT(*) FROM slot WHERE deleted_at = :edit) || ' '
            || (SELECT COUNT(*) FROM slot_miss WHERE deleted_at = :edit)
        """
        #expect(try await repositories.texts(deleted, ["edit": edit]) == ["1 5 6"])
        // Written: the program, 8 weeks (their schedules), 2 days (one renamed, one deleted), 7 slots (one
        // rebuilt, one new, 5 deleted) and 11 misses (5 new, 6 deleted). Every other row keeps its stamp.
        #expect(try await repositories.texts(Self.writtenAt, ["stamp": edit]) == ["1 8 2 7 11"])
    }

    @Test("An update whose change returns the stored program, or only reorders its weeks, writes no row")
    func updateThatChangesNothing_writesNoRow() async throws {
        let (repositories, program) = try await Self.saved()
        let before = try await repositories.texts(Self.everyRow)
        let same = try await repositories.programs.update(program.id) { $0 }
        let reordered = try await repositories.programs.update(program.id) { stored in
            var changed = stored
            changed.weeks.reverse()
            return changed
        }
        let after = try await repositories.texts(Self.everyRow)
        let isUnchanged = after == before && same == program && reordered == program
        #expect(isUnchanged)
        #expect(try await repositories.texts(Self.writtenAt, ["stamp": repositories.clock.timestamp]) == ["0 0 0 0 0"])
    }
}

/// What an update leaves alone: other programs, a refused result's rows, a program it cannot read, and
/// observers of an update that changed nothing.
extension ProgramUpdateTests {
    @Test("An update writes no row of another program, and leaves each program's active flag as it was")
    func update_leavesOtherProgramsAndTheActiveFlag() async throws {
        let repositories = try await Repositories.withProgramExercises()
        let active = try Contract.program(number: 1, isActive: true)
        let inactive = try Contract.program(number: 2, isActive: false)
        try await repositories.programs.save(active)
        try await repositories.programs.save(inactive)
        let flags = "SELECT group_concat(name || ' ' || is_active, ', ') FROM (SELECT * FROM program ORDER BY id)"
        for (program, flagsAfter) in [
            (inactive, "Block 1 1, Block 2 (renamed) 0"),
            (active, "Block 1 (renamed) 1, Block 2 (renamed) 0")
        ] {
            repositories.clock.advance()
            _ = try await repositories.programs.update(program.id, Self.renamed)
            // One row: the renamed program's own. Not the other program's, and no week, day, slot or miss.
            let written = try await repositories.texts(Self.writtenAt, ["stamp": repositories.clock.timestamp])
            #expect(written == ["1 0 0 0 0"])
            #expect(try await repositories.texts(flags) == [flagsAfter])
        }
        #expect(try await repositories.programs.active()?.id == active.id)
    }

    @Test("A refused update, and one whose change throws, leave every row as it was: one transaction")
    func refusedUpdate_leavesEveryRow() async throws {
        let (repositories, program) = try await Self.saved()
        let before = try await repositories.texts(Self.everyRow)
        // The last slot's start load is ⅛ lb, which its column cannot keep: its encoding fails after the
        // program, its weeks and days, and every other slot of the edit were written.
        let eighth = Weight.pounds(0.125)
        await #expect(throws: LedgerPersistenceError.inexactWeight(eighth.grams)) {
            _ = try await repositories.programs.update(program.id) { stored in
                var edited = try Contract.edited(stored)
                edited.days[2].slots[4].startLoad = eighth
                return edited
            }
        }
        await #expect(throws: ChangeRefused()) {
            _ = try await repositories.programs.update(program.id) { _ in throw ChangeRefused() }
        }
        let after = try await repositories.texts(Self.everyRow)
        let isUntouched = after == before
        #expect(isUntouched)
        #expect(try await repositories.programs.active()?.name == program.name)
    }

    @Test("A program whose rows cannot be read cannot be updated: the read's error, no change called, no row written")
    func update_ofAProgramThatCannotBeRead_throwsWhatReadingThrows() async throws {
        let (repositories, program) = try await Self.saved()
        let first = "position = 0 AND day_template_id = (SELECT id FROM day_template WHERE position = 0)"
        try await repositories.execute("UPDATE slot SET sets = 99 WHERE \(first)")
        let before = try await repositories.texts(Self.everyRow)
        let calls = StatementLog()
        await #expect(throws: SlotValidationError.setsOutOfRange(99)) {
            _ = try await repositories.programs.update(program.id) { stored in
                calls.lines.withLock { $0.append("change") }
                return Self.renamed(stored)
            }
        }
        let after = try await repositories.texts(Self.everyRow)
        let isUntouched = after == before
        #expect(isUntouched)
        #expect(calls.lines.withLock { $0 } == [])
        // A whole save repairs the row, as before, and then the program can be updated.
        try await repositories.programs.save(program)
        #expect(try await repositories.programs.update(program.id, Self.renamed).name == "Block 0 (renamed)")
    }

    @Test("observeActive's observation emits once per update that changes the program, and for no other update")
    func observation_emitsOncePerUpdateThatChanges() async throws {
        let (repositories, program) = try await Self.saved()
        let programs = repositories.programs
        let observation = GRDBProgramRepository.activeObservation()
        var values = ObservationTests.everyValue(observation, in: repositories.queue).makeAsyncIterator()
        #expect(await values.next()??.name == program.name)
        // None of these may emit: this stream drops no value, so one would be the next value read.
        _ = try await programs.update(program.id) { $0 }
        await #expect(throws: ChangeRefused()) {
            _ = try await programs.update(program.id) { _ in throw ChangeRefused() }
        }
        await #expect(throws: ProgramValidationError.tooFewWeeks(count: 1)) {
            _ = try await programs.update(program.id) { stored in
                var result = stored
                result.weeks = [stored.weeks[0]]
                return result
            }
        }
        _ = try await programs.update(program.id, Self.renamed)
        #expect(await values.next()??.name == "Block 0 (renamed)")
        let edited = try await programs.update(program.id) { try Contract.edited($0) }
        let isEdited = await (values.next() ?? nil) == edited
        #expect(isEdited)
    }
}
