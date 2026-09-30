import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S2 adversarial round 1: `observeAll()` and `observeActive()` see every change that alters their value,
/// including a change to a child table only (one miss), another writer's SQL, and a switch of the active
/// program. Waits synchronise on the stream only; no sleeps.
@Suite("Adversarial S2 · repository observation", .tags(.persistence), .timeLimit(.minutes(1)))
struct RepositoryObservationAdversarialTests {
    @Test("`observeActive()` follows saves, a child-only edit, `setActive`, a delete and a re-save")
    func observeActive_followsEveryChange() async throws {
        let stack = try await S2Kit.stack()
        var iterator = stack.programs.observeActive().makeAsyncIterator()
        #expect(await iterator.next() == .some(nil))
        let first = try S2Kit.program(1, weeks: 3, days: 2, slotsPerDay: 2, isActive: true)
        try await stack.programs.save(first)
        #expect(await firstValue(&iterator) { $0 == first } != nil)
        var days = first.days
        days[1].slots[1] = try days[1].slots[1].with(misses: days[1].slots[1].misses.union([2]))
        let missed = try first.rebuilt(days: days)
        #expect(missed != first)
        try await stack.programs.save(missed)
        #expect(await firstValue(&iterator) { $0 == missed } != nil, "a new slot_miss row alone")
        let second = try S2Kit.program(2, weeks: 2, days: 1, slotsPerDay: 1, isActive: false)
        try await stack.programs.save(second)
        try await stack.programs.setActive(second.id)
        let secondActive = try second.withActive(true)
        #expect(await firstValue(&iterator) { $0 == secondActive } != nil)
        try await stack.programs.delete(second.id)
        #expect(await firstValue(&iterator) { $0 == nil } != nil)
        try await stack.programs.save(missed)
        #expect(await firstValue(&iterator) { $0 == missed } != nil)
    }

    @Test("`observeActive()` sees an exercise-free edit made by another repository on the same queue")
    func observeActive_seesAnotherRepository() async throws {
        let stack = try await S2Kit.stack()
        let program = try S2Kit.program(weeks: 2, days: 1, slotsPerDay: 3)
        try await stack.programs.save(program)
        var iterator = stack.programs.observeActive().makeAsyncIterator()
        #expect(await iterator.next() == .some(program))
        var days = program.days
        days[0].slots.swapAt(0, 2)
        let reordered = try program.rebuilt(days: days)
        try await GRDBProgramRepository(stack.queue).save(reordered)
        #expect(await firstValue(&iterator) { $0 == reordered } != nil, "a position-only change")
    }

    @Test("`observeAll()` follows a save, a seed, another writer's soft delete, and damage (leaving the row out)")
    func observeAll_followsEveryChange() async throws {
        let queue = try LedgerDatabase.inMemory()
        let repository = GRDBExerciseRepository(queue)
        var iterator = repository.observeAll().makeAsyncIterator()
        #expect(await iterator.next() == [])
        let custom = S2Kit.exercise(1, "Custom", isCustom: true)
        try await repository.save(custom)
        #expect(await firstValue(&iterator) { $0 == [custom] } != nil)
        let catalog = [S2Kit.exercise(2, "Alpha"), S2Kit.exercise(3, "Beta")]
        try await repository.seedIfNeeded(catalog, version: 1)
        #expect(await firstValue(&iterator) { $0.count == 3 } != nil)
        try await queue.write { try $0.execute(sql: "UPDATE exercise SET deleted_at = 'then' WHERE name = 'Alpha'") }
        #expect(await firstValue(&iterator) { $0.map(\.name).sorted() == ["Beta", "Custom"] } != nil)
        try await queue.write { try $0.execute(sql: "UPDATE exercise SET pattern = 'jump' WHERE name = 'Beta'") }
        #expect(await firstValue(&iterator) { $0 == [custom] } != nil, "the stream goes on without the damaged row")
        var renamed = custom
        renamed.name = "Renamed"
        try await repository.save(renamed)
        #expect(await firstValue(&iterator) { $0 == [renamed] } != nil)
    }
}
