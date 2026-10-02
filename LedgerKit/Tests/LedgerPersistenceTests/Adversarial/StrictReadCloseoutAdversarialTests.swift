import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S2 close-out round, S2-2 and S2-3 variants: a damaged `catalog_version` of every storage class, on the
/// newest row, an older one, a deleted one and a custom one; and a blob id on every program table, including a
/// blob holding the very bytes of the text id.
@Suite("Adversarial S2 close-out · strict reads", .tags(.persistence), .timeLimit(.minutes(1)))
struct StrictReadCloseoutAdversarialTests {
    enum Target: String, CaseIterable, Sendable {
        case everyCatalogRow, oneOfTwoRows, aDeletedRow, aCustomRow
    }

    /// `1.0` and `'1'` are no damage: the column's `INTEGER` affinity stores them as the integer 1. The rest stay
    /// `REAL`, `TEXT` or `BLOB`.
    static let values = [
        "9.3e18", "-9.3e18", "1.0", "'1'", "1.5", "0.5", "''", "'v1'", "x'01'", "x''", "'9223372036854775808'"
    ]

    /// S2-2: after the damage, an upgrade either throws `malformedColumn("exercise.catalog_version")` and
    /// changes no byte, or seeds the new entry and records its version on every live catalog row it lists. It
    /// never returns quietly without seeding.
    @Test("A damaged catalog_version never stops an upgrade silently", arguments: Target.allCases, values)
    func damagedVersion_neverStopsAnUpgradeSilently(target: Target, value: String) async throws {
        let kit = try S2CatalogKit()
        let catalog = Array(CatalogRefreshCloseoutAdversarialTests.catalog.prefix(2))
        try await kit.exercises.save(S2Kit.exercise(103, "Mine", isCustom: true))
        try await kit.exercises.seedIfNeeded(catalog, version: 1)
        let ids: [Int] = switch target {
        case .everyCatalogRow: [100, 101]
        case .oneOfTwoRows: [100]
        case .aDeletedRow: [101]
        case .aCustomRow: [103]
        }
        for number in ids {
            let deleted = target == .aDeletedRow ? ", deleted_at = '2026-09-01T00:00:00.000Z'" : ""
            try await S2Kit.damage(kit.queue, "UPDATE exercise SET catalog_version = \(value)\(deleted) WHERE id = ?", [
                ColumnCodec.text(S2Kit.exerciseID(number))
            ])
        }
        let before = try await kit.dump()
        let added = S2Kit.exercise(102, "Overhead Press", short: "OHP", muscle: .shoulders)
        let upgrade = await Result { try await kit.exercises.seedIfNeeded(catalog + [added], version: 2) }
        switch upgrade {
        case let .failure(error):
            #expect(error as? LedgerPersistenceError == .malformedColumn("exercise.catalog_version"), "\(error)")
            #expect(try await kit.dump() == before, "a failed upgrade wrote")
        case .success:
            #expect(try await kit.exercise(102) == added, "the upgrade returned without seeding")
            let versions = try await kit.queue.read { database in
                try Row.fetchAll(
                    database,
                    sql: """
                    SELECT typeof(catalog_version) AS kind, catalog_version FROM exercise
                    WHERE is_custom = 0 AND deleted_at IS NULL
                    """
                ).map { "\($0["kind"] as String? ?? "?") \($0["catalog_version"] as DatabaseValue)" }
            }
            #expect(versions == Array(repeating: "integer 2", count: versions.count), "\(versions)")
        }
    }

    enum BlobID: String, CaseIterable, Sendable {
        case program, week, day, slot, miss
        case weekWithItsOwnBytes, dayWithItsOwnBytes, slotWithItsOwnBytes, programWithItsOwnBytes
    }

    /// S2-3 on every table: a row whose id is a blob (`x'00'`, or the text id's own bytes) is repaired by a save
    /// of its program, which then reads back as saved, with exactly its live rows; a second save changes no byte.
    @Test("A blob id on any program table is repaired by a save", arguments: BlobID.allCases)
    func blobID_isRepairedBySave(damage: BlobID) async throws {
        let stack = try await S2Kit.stack()
        let first = try S2Kit.program(1, weeks: 3, days: 2, slotsPerDay: 2, isActive: true)
        try await stack.programs.save(first)
        let slot = first.days[1].slots[0]
        let missID = try await stack.queue.read { database in
            try String.fetchOne(database, sql: "SELECT id FROM slot_miss WHERE slot_id = ? LIMIT 1", arguments: [
                ColumnCodec.text(slot.id)
            ])
        }
        let (table, id): (String, String?) = switch damage {
        case .program, .programWithItsOwnBytes: ("program", ColumnCodec.text(first.id))
        case .week, .weekWithItsOwnBytes: ("program_week", ColumnCodec.text(first.weeks[1].id))
        case .day, .dayWithItsOwnBytes: ("day_template", ColumnCodec.text(first.days[1].id))
        case .slot, .slotWithItsOwnBytes: ("slot", ColumnCodec.text(slot.id))
        case .miss: ("slot_miss", missID)
        }
        let blob = damage.rawValue.hasSuffix("OwnBytes") ? "CAST(id AS BLOB)" : "x'00'"
        try await S2Kit.damage(stack.queue, "UPDATE \(table) SET id = \(blob) WHERE id = ?", [id])
        stack.clock.advance()
        let saved = await Result { try await stack.programs.save(first) }
        #expect(throws: Never.self) { try saved.get() }
        let reread = await Result { try await stack.programs.active() }
        #expect((try? reread.get()) == first, "\(reread)")
        #expect(try await S2Kit.liveCounts(stack.queue).filter { $0.key != "program" } == S2Kit.expectedCounts([first])
            .filter { $0.key != "program" })
        let settled = try await ProgramRoundTripAdversarialTests.dump(stack.queue)
        stack.clock.advance()
        try await stack.programs.save(first)
        #expect(try await ProgramRoundTripAdversarialTests.dump(stack.queue) == settled, "a second save wrote")
    }
}
