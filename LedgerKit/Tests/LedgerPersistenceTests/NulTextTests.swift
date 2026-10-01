import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// S2-4 (orchestrator, 2026-09-30: refuse, don't truncate). GRDB binds text as a C string, so SQLite would keep a
/// value only up to its first U+0000. Every record write refuses such text with `nulInText("table.column")`, in
/// one place (`SyncedRecord`), and the transaction writes nothing.
@Suite("Text holding NUL", .tags(.persistence), .timeLimit(.minutes(1)))
struct NulTextTests {
    static let nul = "before\u{0}after"

    @Test("An exercise whose name or short name holds NUL is refused by column, and nothing is written")
    func exercise_isRefused() async throws {
        let repositories = try Repositories()
        var named = ExerciseRepositoryContract.landmine
        named.name = Self.nul
        await #expect(throws: LedgerPersistenceError.nulInText("exercise.name")) {
            try await repositories.exercises.save(named)
        }
        var short = ExerciseRepositoryContract.landmine
        short.shortName = Self.nul
        await #expect(throws: LedgerPersistenceError.nulInText("exercise.short_name")) {
            try await repositories.exercises.save(short)
        }
        var catalog = Seeders.catalog(count: 3, version: 1).exercises
        catalog[2].name = Self.nul
        await #expect(throws: LedgerPersistenceError.nulInText("exercise.name")) {
            try await repositories.exercises.seedIfNeeded(catalog, version: 1)
        }
        #expect(try await repositories.count("SELECT COUNT(*) FROM exercise") == 0)
    }

    @Test("A day whose name or tag holds NUL is refused by column, and the stored program is unchanged")
    func day_isRefused() async throws {
        let repositories = try await Repositories.withProgramExercises()
        let program = try ProgramRepositoryContract.program()
        try await repositories.programs.save(program)
        for (column, edit) in [("name", \DayTemplate.name), ("tag", \DayTemplate.tag)] {
            var edited = program
            edited.days[1][keyPath: edit] = Self.nul
            await #expect(throws: LedgerPersistenceError.nulInText("day_template.\(column)")) {
                try await repositories.programs.save(edited)
            }
        }
        #expect(try await repositories.programs.active() == program)
    }

    @Test("Other control characters are stored whole")
    func otherControlCharacters_roundTrip() async throws {
        let repositories = try Repositories()
        var exercise = ExerciseRepositoryContract.landmine
        exercise.name = "tab\there, bell\u{7}, unit separator\u{1F}, DEL\u{7F}"
        try await repositories.exercises.save(exercise)
        #expect(try await repositories.exercises.exercise(id: exercise.id) == exercise)
    }
}
