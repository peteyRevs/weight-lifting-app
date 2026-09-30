import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// The repositories' `ValueObservation` streams (`observeAll`, `observeActive`): the current value first, then
/// one value per change that alters it, and none for a write that does not. `LedgerPersistenceTests` runs in the
/// PR-Watch plan too, so these emissions are checked on the watch simulator as well (F05 risk
/// "ValueObservation on watchOS"). S3 adds `observeRecent` (criterion 10).
@Suite("Repository observation", .tags(.persistence), .timeLimit(.minutes(1)))
struct ObservationTests {
    @Test("observeAll emits the catalog now, then after a custom save, and skips a save that changes nothing")
    func observeAll_emitsOnChange_only() async throws {
        let repositories = try Repositories()
        let catalog = Seeders.catalog(count: 3, version: 1).exercises
        try await repositories.exercises.seedIfNeeded(catalog, version: 1)
        var values = repositories.exercises.observeAll().makeAsyncIterator()
        #expect(await values.next().map(Set.init) == Set(catalog))
        try await repositories.exercises.seedIfNeeded(catalog, version: 1) // no change
        try await repositories.exercises.save(ExerciseRepositoryContract.landmine)
        #expect(await values.next().map(Set.init) == Set(catalog + [ExerciseRepositoryContract.landmine]))
    }

    @Test("observeActive emits nil, the program, each edit and nil after delete; an unchanged save emits nothing")
    func observeActive_emitsEachChange_only() async throws {
        let programs = try await Repositories.withProgramExercises().programs
        let program = try ProgramRepositoryContract.program()
        let edited = try ProgramRepositoryContract.edited(program)
        var values = programs.observeActive().makeAsyncIterator()
        #expect(await values.next() == .some(nil))
        try await programs.save(program)
        #expect(await values.next() == program)
        try await programs.save(program) // no change
        try await programs.save(edited)
        #expect(await values.next() == edited)
        try await programs.delete(program.id)
        #expect(await values.next() == .some(nil))
    }

    @Test("observeActive follows setActive to another program, and ignores an inactive one's edits")
    func observeActive_followsSetActive() async throws {
        let programs = try await Repositories.withProgramExercises().programs
        let first = try ProgramRepositoryContract.program(number: 1, isActive: true)
        let second = try ProgramRepositoryContract.program(number: 2, isActive: false)
        try await programs.save(first)
        var values = programs.observeActive().makeAsyncIterator()
        #expect(await values.next() == first)
        try await programs.save(second) // an inactive program: the active one is unchanged
        try await programs.setActive(second.id)
        var active = second
        active.isActive = true
        #expect(await values.next() == active)
    }
}
