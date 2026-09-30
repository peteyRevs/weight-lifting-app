import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S2 adversarial round 1: the sync columns an edit leaves (ADR-002: soft deletes and `updated_at` on every
/// row, so M4 can push exactly the rows that changed). `save` promises that an unchanged row keeps its
/// `updated_at`; a soft delete must also move `updated_at`, or a sync engine keyed on it never sends it.
@Suite("Adversarial S2 · program sync columns", .tags(.persistence), .timeLimit(.minutes(1)))
struct ProgramTimestampAdversarialTests {
    struct Stamp: Equatable, CustomStringConvertible {
        let table: String
        let id: String
        let created: String
        let updated: String
        let deleted: String?

        var description: String {
            "\(table) \(id.prefix(8))…\(id.suffix(4)) c=\(created) u=\(updated) d=\(deleted ?? "nil")"
        }
    }

    static func stamps(_ queue: DatabaseQueue) async throws -> [String: Stamp] {
        try await queue.read { database in
            var stamps: [String: Stamp] = [:]
            for table in ["program", "program_week", "day_template", "slot", "slot_miss"] {
                for row in try Row.fetchAll(database, sql: "SELECT * FROM \(table)") {
                    let id: String = row["id"]
                    stamps["\(table) \(id)"] = Stamp(
                        table: table, id: id, created: row["created_at"], updated: row["updated_at"],
                        deleted: row["deleted_at"]
                    )
                }
            }
            return stamps
        }
    }

    @Test("Changing one slot's reps moves that slot's `updated_at` only; every other child row keeps its stamps")
    func oneSlotEdit_touchesOneChildRow() async throws {
        let stack = try await S2Kit.stack()
        let program = try S2Kit.program()
        try await stack.programs.save(program)
        let before = try await Self.stamps(stack.queue)
        stack.clock.advance()
        var days = program.days
        days[2].slots[3] = try days[2].slots[3].with(reps: 1, repsHi: 2)
        try await stack.programs.save(program.rebuilt(days: days))
        let after = try await Self.stamps(stack.queue)
        let changed = after.filter { before[$0.key] != $0.value && $0.value.table != "program" }
        #expect(changed.keys.sorted() == ["slot \(ColumnCodec.text(days[2].slots[3].id))"], "\(changed.values)")
        #expect(after.values.allSatisfy { $0.created == before["\($0.table) \($0.id)"]?.created })
    }

    @Test("Removing a slot soft-deletes it and its misses, and moves their `updated_at` to the deletion time")
    func removal_movesUpdatedAt() async throws {
        let stack = try await S2Kit.stack()
        let program = try S2Kit.program(weeks: 3, days: 1, slotsPerDay: 3)
        try await stack.programs.save(program)
        stack.clock.advance()
        let now = ColumnCodec.timestamp(stack.clock.now)
        var days = program.days
        let removed = days[0].slots.removeFirst()
        #expect(!removed.misses.isEmpty)
        try await stack.programs.save(program.rebuilt(days: days))
        let stamps = try await Self.stamps(stack.queue)
        let slot = stamps["slot \(ColumnCodec.text(removed.id))"]
        #expect(slot?.deleted == now)
        #expect(slot?.updated == now, "a soft delete that keeps the old updated_at is invisible to a sync keyed on it")
        let misses = try await Self.missStamps(stack.queue, slot: removed.id)
        #expect(misses.count == removed.misses.count)
        #expect(misses.allSatisfy { $0.deleted == now && $0.updated == now }, "\(misses)")
    }

    @Test("Deleting a program moves `updated_at` with `deleted_at` on every row it soft-deletes")
    func programDelete_movesUpdatedAt() async throws {
        let stack = try await S2Kit.stack()
        let program = try S2Kit.program(weeks: 2, days: 2, slotsPerDay: 2)
        try await stack.programs.save(program)
        stack.clock.advance()
        let now = ColumnCodec.timestamp(stack.clock.now)
        try await stack.programs.delete(program.id)
        let stamps = try await Self.stamps(stack.queue)
        #expect(!stamps.isEmpty)
        let stale = stamps.values.filter { $0.deleted != now || $0.updated != now }
        #expect(stale.isEmpty, "\(stale)")
    }

    @Test("Re-adding a removed slot clears `deleted_at`, moves `updated_at` and keeps `created_at`")
    func reAdd_clearsDeletedAt() async throws {
        let stack = try await S2Kit.stack()
        let program = try S2Kit.program(weeks: 2, days: 1, slotsPerDay: 2)
        let created = ColumnCodec.timestamp(stack.clock.now)
        try await stack.programs.save(program)
        var days = program.days
        let removed = days[0].slots.removeLast()
        stack.clock.advance()
        try await stack.programs.save(program.rebuilt(days: days))
        stack.clock.advance()
        let now = ColumnCodec.timestamp(stack.clock.now)
        try await stack.programs.save(program)
        let slot = try await Self.stamps(stack.queue)["slot \(ColumnCodec.text(removed.id))"]
        #expect(slot == Stamp(
            table: "slot",
            id: ColumnCodec.text(removed.id),
            created: created,
            updated: now,
            deleted: nil
        ))
    }

    @Test("Timestamps are ISO 8601 UTC text, and `created_at` never moves on a later save")
    func timestampFormat() async throws {
        let stack = try await S2Kit.stack()
        let program = try S2Kit.program(weeks: 2, days: 1, slotsPerDay: 1)
        try await stack.programs.save(program)
        stack.clock.advance(seconds: 86400 * 400)
        try await stack.programs.save(program.rebuilt(name: "Renamed"))
        let stamps = try await Self.stamps(stack.queue)
        let parse = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        for stamp in stamps.values {
            #expect(stamp.created.hasSuffix("Z") && stamp.updated.hasSuffix("Z"), "\(stamp)")
            #expect((try? parse.parse(stamp.created)) != nil, "\(stamp)")
            #expect(stamp.created == ColumnCodec.timestamp(Date(timeIntervalSinceReferenceDate: 800_000_000)))
        }
    }

    static func missStamps(_ queue: DatabaseQueue, slot: SlotID) async throws -> [Stamp] {
        try await queue.read { database in
            try Row.fetchAll(database, sql: "SELECT * FROM slot_miss WHERE slot_id = ?", arguments: [
                ColumnCodec.text(slot)
            ]).map {
                Stamp(
                    table: "slot_miss",
                    id: $0["id"],
                    created: $0["created_at"],
                    updated: $0["updated_at"],
                    deleted: $0["deleted_at"]
                )
            }
        }
    }
}
