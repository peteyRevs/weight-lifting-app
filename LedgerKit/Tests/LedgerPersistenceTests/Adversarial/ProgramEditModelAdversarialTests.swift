import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S2 adversarial round 1: a seeded random builder session against the model "the stored program is the
/// last one saved". Every step saves one to three edits (fields, adds, removals, moves across days, reorders,
/// days and weeks added or removed, misses, ids removed earlier and added back, a delete then a re-save).
@Suite("Adversarial S2 · program edit model", .tags(.persistence, .property), .timeLimit(.minutes(1)))
struct ProgramEditModelAdversarialTests {
    @Test("Every save reads back as the program given, with exactly its live rows", arguments: PropertySeed.all)
    func randomEdits_matchTheModel(seed: PropertySeed) async throws {
        let stack = try await S2Kit.stack()
        let start = try S2Kit.program(1, weeks: 3, days: 3, slotsPerDay: 3)
        var editor = ProgramEditor(program: start, seed: seed.value)
        try await stack.programs.save(start)
        for step in 0 ..< 8 {
            try editor.edit()
            stack.clock.advance()
            if step == 5 {
                try await stack.programs.delete(start.id)
                #expect(try await stack.programs.active() == nil)
            }
            try await stack.programs.save(editor.program)
            let loaded = try await stack.programs.program(id: start.id)
            #expect(loaded == editor.program, "\(seed) step \(step)")
            #expect(
                try await S2Kit.liveCounts(stack.queue) == S2Kit.expectedCounts([editor.program]),
                "\(seed) step \(step)"
            )
            if loaded != editor.program {
                return
            }
        }
        #expect(try await GRDBProgramRepository(stack.queue).active() == editor.program)
        #expect(try await Self.orphans(stack.queue) == 0, "\(seed): a live row under a deleted parent")
    }

    /// Live rows whose parent row is deleted or missing.
    static func orphans(_ queue: DatabaseQueue) async throws -> Int {
        try await queue.read { database in
            try Int.fetchOne(database, sql: """
            SELECT
              (SELECT COUNT(*) FROM program_week w LEFT JOIN program p ON p.id = w.program_id
                 WHERE w.deleted_at IS NULL AND (p.id IS NULL OR p.deleted_at IS NOT NULL))
            + (SELECT COUNT(*) FROM day_template d LEFT JOIN program p ON p.id = d.program_id
                 WHERE d.deleted_at IS NULL AND (p.id IS NULL OR p.deleted_at IS NOT NULL))
            + (SELECT COUNT(*) FROM slot s LEFT JOIN day_template d ON d.id = s.day_template_id
                 WHERE s.deleted_at IS NULL AND (d.id IS NULL OR d.deleted_at IS NOT NULL))
            + (SELECT COUNT(*) FROM slot_miss m LEFT JOIN slot s ON s.id = m.slot_id
                 WHERE m.deleted_at IS NULL AND (s.id IS NULL OR s.deleted_at IS NOT NULL))
            """) ?? -1
        }
    }
}
