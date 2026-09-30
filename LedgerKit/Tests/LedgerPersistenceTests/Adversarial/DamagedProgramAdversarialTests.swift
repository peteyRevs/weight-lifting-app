import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S2 adversarial round 1: strict reads of damaged program rows. `program(id:)` and `active()` throw rather
/// than trap, and never return a program other than the one saved (a fraction read as its integer part, a flag
/// of 2 read as `true`, text or a blob read as 0). Another program's reads are unaffected.
@Suite("Adversarial S2 · damaged program rows", .tags(.persistence), .timeLimit(.minutes(1)))
struct DamagedProgramAdversarialTests {
    struct Damage: Sendable, CustomStringConvertible {
        let table: String
        let set: String
        var description: String {
            "\(table).\(set)"
        }
    }

    static let damages: [Damage] = [
        (
            "program",
            [
                "start_date = '2026-02-30'",
                "start_date = '2026-9-14'",
                "start_date = ''",
                "start_date = 20260914",
                "start_date = x'00'",
                "goal = 'power'",
                "goal = 1",
                "days_per_week = 3.5",
                "days_per_week = 'four'",
                "days_per_week = x'04'",
                "days_per_week = 9.3e18",
                "is_active = 0.5",
                "is_active = 'yes'",
                "name = x'FF'",
                "id = 'nope'"
            ]
        ),
        ("program_week", [
            "week_index = 1.5",
            "week_index = 'one'",
            "week_index = x'01'",
            "week_index = 9.3e18",
            "is_deload = 0.5",
            "is_deload = 'no'",
            "mon = 'garbage'",
            "mon = x'00'",
            "mon = ''",
            "mon = 'AD52000D-0000-4000-8000-00000000FFFF'",
            "id = 'nope'"
        ]),
        ("day_template", ["name = x'FF'", "tag = x'C0'", "id = 'nope'"]),
        ("slot", [
            "sets = 0",
            "sets = 13",
            "sets = 3.5",
            "sets = 'x'",
            "sets = x'03'",
            "sets = 9.3e18",
            "reps = 31",
            "reps_hi = 1",
            "rpe_x2 = 9",
            "rpe_x2 = 21",
            "rpe_x2 = 17.5",
            "rpe_x2 = 'x'",
            "rest_seconds = 31",
            "rest_seconds = 29.5",
            "progression = 'wave'",
            "progression = x'00'",
            "start_load_e7g = 1.5",
            "start_load_e7g = 'x'",
            "start_load_e7g = -10",
            "start_load_e7g = 9.3e18",
            "start_load_e7g = x'01'",
            "step_e7g = 0",
            "step_e7g = -10",
            "step_e7g = 2.5",
            "is_superset_with_previous = 0.5",
            "is_superset_with_previous = 'yes'",
            "drop_sets = 2",
            "drop_sets = -1",
            "drop_sets = 0.5",
            "exercise_id = 'nope'",
            "exercise_id = x'00'",
            "id = 'nope'"
        ]),
        ("slot_miss", ["week_index = 1.5", "week_index = 'x'", "week_index = x'01'", "week_index = 9.3e18"])
    ].flatMap { table, sets in sets.map { Damage(table: table, set: $0) } }

    /// Program 1 (active) and program 2; the damage hits one row of program 1's `table`.
    /// A database holding two programs, one damaged.
    struct Damaged {
        let stack: S2Kit.Stack
        let first: Program
        let second: Program
    }

    static func damaged(_ damage: Damage) async throws -> Damaged {
        let stack = try await S2Kit.stack()
        let first = try S2Kit.program(1, weeks: 3, days: 2, slotsPerDay: 2, isActive: true)
        let second = try S2Kit.program(2, weeks: 3, days: 2, slotsPerDay: 2, isActive: false)
        try await stack.programs.save(first)
        try await stack.programs.save(second)
        let target = switch damage.table {
        case "program": ColumnCodec.text(first.id)
        case "program_week": ColumnCodec.text(first.weeks[1].id)
        case "day_template": ColumnCodec.text(first.days[1].id)
        case "slot": ColumnCodec.text(first.days[1].slots[1].id)
        default: try await Self.missID(stack.queue, slot: first.days[1].slots[1].id)
        }
        try await S2Kit.damage(stack.queue, "UPDATE \(damage.table) SET \(damage.set) WHERE id = ?", [target])
        return Damaged(stack: stack, first: first, second: second)
    }

    static func missID(_ queue: DatabaseQueue, slot: SlotID) async throws -> String {
        try await queue.read { database in
            try String.fetchOne(database, sql: "SELECT id FROM slot_miss WHERE slot_id = ? LIMIT 1", arguments: [
                ColumnCodec.text(slot)
            ]) ?? "none"
        }
    }

    @Test("A damaged row makes its program throw, never trap or read as another program", arguments: damages)
    func damagedRow_throws(damage: Damage) async throws {
        let damaged = try await Self.damaged(damage)
        let (stack, first, second) = (damaged.stack, damaged.first, damaged.second)
        let byID = await Result { try await stack.programs.program(id: first.id) }
        let active = await Result { try await stack.programs.active() }
        if case let .success(program) = byID {
            #expect(program == nil && damage.set.hasPrefix("id ="), "read as \(String(describing: program?.name))")
        }
        switch active {
        case let .success(program):
            #expect(program == nil, "active() read a damaged program")
        case .failure:
            break
        }
        #expect(try await stack.programs.program(id: second.id) == second, "the other program is unaffected")
    }
}

extension DamagedProgramAdversarialTests {
    /// Spec question (documents), as for `exercise.is_custom`: a flag holding an integer other than 0 or 1 reads as
    /// `true`, where a fraction, text or a blob is refused.
    @Test("(documents) `is_deload` and `is_superset_with_previous` of 2 read as true")
    func outOfRangeFlags_readAsTrue() async throws {
        let damaged = try await Self.damaged(Damage(table: "program_week", set: "is_deload = 2"))
        let (stack, first) = (damaged.stack, damaged.first)
        try await S2Kit.damage(stack.queue, "UPDATE slot SET is_superset_with_previous = -1 WHERE id = ?", [
            ColumnCodec.text(first.days[1].slots[1].id)
        ])
        let program = try await stack.programs.program(id: first.id)
        #expect(program?.weeks[1].isDeload == true)
        #expect(program?.days[1].slots[1].isSupersetWithPrevious == true)
    }

    @Test("A damaged active program ends `observeActive()`; the stream never emits a wrong program")
    func damagedActive_endsTheObservation() async throws {
        let stack = try await Self.damaged(Damage(table: "slot", set: "sets = 3.5")).stack
        var iterator = stack.programs.observeActive().makeAsyncIterator()
        #expect(await iterator.next() == nil)
    }

    @Test("A program saved over its damaged rows reads back as saved")
    func saveOverDamage_repairs() async throws {
        for damage in [
            Damage(table: "slot", set: "rpe_x2 = 'x'"),
            Damage(table: "program_week", set: "mon = 'garbage'")
        ] {
            let damaged = try await Self.damaged(damage)
            let (stack, first) = (damaged.stack, damaged.first)
            try await stack.programs.save(first)
            #expect(try await stack.programs.active() == first, "\(damage)")
        }
    }
}
