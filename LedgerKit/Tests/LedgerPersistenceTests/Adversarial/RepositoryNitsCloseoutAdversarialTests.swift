import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S2 close-out round, review N1 and N2: an exercise save that changes nothing keeps `updated_at` (and so
/// never wins a last-writer-wins merge it should lose); `delete` clears `is_active`, so no revival of a deleted
/// program can make it active again behind the lifter's back.
@Suite("Adversarial S2 close-out · N1 and N2", .tags(.persistence), .timeLimit(.minutes(1)))
struct RepositoryNitsCloseoutAdversarialTests {
    @Test("N1: an identical exercise save keeps updated_at; a changed one or a revival moves it")
    func exerciseSave_stampsOnlyChanges() async throws {
        let kit = try S2CatalogKit()
        let custom = S2Kit.exercise(300, "Landmine Press", short: "LMP", isCustom: true)
        try await kit.exercises.save(custom)
        let savedAt = kit.stamp()
        for _ in 0 ..< 3 {
            kit.clock.advance()
            try await kit.exercises.save(custom)
            #expect(try await kit.meta(300) == [.null, savedAt, savedAt, .null])
        }
        var renamed = custom
        renamed.secondaryMuscles = [.triceps]
        kit.clock.advance()
        try await kit.exercises.save(renamed)
        #expect(try await kit.meta(300) == [.null, savedAt, kit.stamp(), .null])
        try await kit.queue.write { database in
            try database.execute(sql: "UPDATE exercise SET deleted_at = updated_at")
        }
        kit.clock.advance()
        try await kit.exercises.save(renamed)
        #expect(try await kit.meta(300) == [.null, savedAt, kit.stamp(), .null], "a revival is a change")
        #expect(try await kit.exercise(300) == renamed)
    }

    @Test("N2: delete clears is_active on the deleted program only; a revival without a save is never active")
    func delete_clearsOnlyItsActiveFlag() async throws {
        let stack = try await S2Kit.stack()
        let first = try S2Kit.program(1, weeks: 2, days: 1, slotsPerDay: 1, isActive: true)
        let second = try S2Kit.program(2, weeks: 2, days: 1, slotsPerDay: 1, isActive: false)
        try await stack.programs.save(second)
        try await stack.programs.save(first)
        let flags = { @Sendable () async throws -> [String] in
            try await stack.queue.read { database in
                try Row.fetchAll(database, sql: "SELECT is_active, deleted_at IS NULL AS live FROM program ORDER BY id")
                    .map { "\($0["is_active"] as Int64? ?? -1)/\($0["live"] as Int64? ?? -1)" }
            }
        }
        stack.clock.advance()
        try await stack.programs.delete(second.id) // an inactive program: the active one keeps every byte
        #expect(try await flags() == ["1/1", "0/0"])
        #expect(try await stack.programs.active() == first)
        stack.clock.advance()
        try await stack.programs.delete(first.id)
        #expect(try await flags() == ["0/0", "0/0"])
        let revival = "UPDATE program SET deleted_at = NULL, updated_at = '9999-01-01T00:00:00.000Z'"
        try await S2Kit.damage(stack.queue, revival)
        #expect(try await stack.programs.active() == nil, "a revived program became active")
        try await stack.programs.save(first)
        #expect(try await stack.programs.active() == first)
        #expect(try await flags() == ["1/1", "0/1"])
    }
}
