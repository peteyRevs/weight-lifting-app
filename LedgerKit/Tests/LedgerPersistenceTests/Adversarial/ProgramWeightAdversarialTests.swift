import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S2 adversarial round 1, ADR-007: a slot's start load and step are stored as exact integer counts of
/// 10⁻⁷ g (`start_load_e7g`, `step_e7g`), read back equal at the `Int64` edges, and refused (with nothing written)
/// when they are not whole counts.
@Suite("Adversarial S2 · slot weights", .tags(.persistence), .timeLimit(.minutes(1)))
struct ProgramWeightAdversarialTests {
    static let unit = Decimal(string: "0.0000001") ?? 0
    static let maxWeight = Weight(grams: ColumnCodec.grams(e7g: .max))

    /// Program 1 with its first slot's loads replaced.
    static func program(startLoad: Weight?, step: Weight?) throws -> Program {
        let base = try S2Kit.program(weeks: 2, days: 1, slotsPerDay: 2)
        var days = base.days
        days[0].slots[0] = try days[0].slots[0].with(startLoad: .some(startLoad), step: .some(step))
        return try base.rebuilt(days: days)
    }

    static func columns(_ queue: DatabaseQueue, _ slot: SlotID) async throws -> [Int64?] {
        try await queue.read { database in
            let row = try Row.fetchOne(
                database,
                sql: "SELECT start_load_e7g, step_e7g FROM slot WHERE id = ?",
                arguments: [
                    ColumnCodec.text(slot)
                ]
            )
            return [row?["start_load_e7g"], row?["step_e7g"]]
        }
    }

    @Test("Loads at the edges round-trip and are stored as the exact count", arguments: [
        (Int64.max, 1), (0, Int64.max), (1, 1), (45_359_237 * 100_000, 45_359_237 * 250), (12_500_000_000, 125_000_000)
    ] as [(Int64, Int64)])
    func edgeLoads_areExactCounts(startCount: Int64, stepCount: Int64) async throws {
        let stack = try await S2Kit.stack()
        let program = try Self.program(
            startLoad: Weight(grams: ColumnCodec.grams(e7g: startCount)),
            step: Weight(grams: ColumnCodec.grams(e7g: stepCount))
        )
        try await stack.programs.save(program)
        #expect(try await stack.programs.active() == program)
        #expect(try await Self.columns(stack.queue, program.days[0].slots[0].id) == [startCount, stepCount])
    }

    @Test("No start load and no step are stored as NULL and read back as nil")
    func nilLoads_areNull() async throws {
        let stack = try await S2Kit.stack()
        let program = try Self.program(startLoad: nil, step: nil)
        try await stack.programs.save(program)
        #expect(try await stack.programs.active() == program)
        #expect(try await Self.columns(stack.queue, program.days[0].slots[0].id) == [nil, nil])
    }

    @Test("An inexact start load or step throws `inexactWeight` with the value, and the saved version stays")
    func inexactLoads_areRefused() async throws {
        let stack = try await S2Kit.stack()
        let saved = try S2Kit.program(weeks: 2, days: 1, slotsPerDay: 2)
        try await stack.programs.save(saved)
        let before = try await ProgramRoundTripAdversarialTests.dump(stack.queue)
        let refused: [(Weight?, Weight?)] = [
            (Weight(grams: Self.maxWeight.grams + Self.unit), nil), (.pounds(0.125), nil), (nil, .pounds(0.001)),
            (nil, Weight(grams: Self.unit / 10)), (Weight(grams: 1 / 3), .pounds(5))
        ]
        for (startLoad, step) in refused {
            let bad = startLoad ?? step ?? .zero
            await #expect(throws: LedgerPersistenceError.inexactWeight(bad.grams)) {
                try await stack.programs.save(Self.program(startLoad: startLoad, step: step))
            }
            #expect(try await ProgramRoundTripAdversarialTests.dump(stack.queue) == before)
        }
    }

    /// Finding S2-3: `SyncedRecord.write` keys stored rows by `String.fromDatabaseValue(row["id"])`, so a row whose
    /// id is a blob is never matched, never soft-deleted, and keeps its program unreadable through every save.
    @Test(
        "A program saved over a damaged slot id repairs it, whatever the id's storage class",
        arguments: ["'nope'", "x'00'", "7"]
    )
    func saveOverDamagedID_repairs(value: String) async throws {
        let stack = try await S2Kit.stack()
        let program = try S2Kit.program(weeks: 2, days: 2, slotsPerDay: 2)
        try await stack.programs.save(program)
        try await S2Kit.damage(stack.queue, "UPDATE slot SET id = \(value) WHERE id = ?", [
            ColumnCodec.text(program.days[1].slots[1].id)
        ])
        await #expect(throws: (any Error).self) { try await stack.programs.active() }
        try await stack.programs.save(program)
        let reread = await Result { try await stack.programs.active() }
        #expect((try? reread.get()) == program, "\(reread.map { $0?.name })")
    }
}
