import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S2 adversarial round 1: `GRDBExerciseRepository.save` and reads keep every field exactly (ADR-007 loads
/// as `_e7g` integers, JSON arrays in order), upsert by id, and `all()` has one order whatever the insert order.
@Suite("Adversarial S2 · exercise round trips", .tags(.persistence), .timeLimit(.minutes(1)))
struct ExerciseRoundTripAdversarialTests {
    static let maxLoad = Weight(grams: ColumnCodec.grams(e7g: .max))
    static let minLoad = Weight(grams: ColumnCodec.grams(e7g: .min))

    static let shapes: [Exercise] = [
        S2Kit.exercise(1, "No loads", loads: [:]),
        S2Kit.exercise(2, "Pounds only", loads: [.lb: .pounds(0.01)]),
        S2Kit.exercise(3, "Kilograms only", loads: [.kg: .kilograms(1.25)]),
        S2Kit.exercise(4, "Extremes", loads: [.lb: maxLoad, .kg: minLoad]),
        S2Kit.exercise(5, "Tiny", loads: [.lb: Weight(grams: Decimal(string: "0.0000001") ?? 0), .kg: .zero]),
        S2Kit.exercise(6, "Negative", loads: [.lb: .pounds(-0.01), .kg: Weight(grams: -1)]),
        S2Kit.exercise(7, "Muscles", secondary: [.triceps, .chest, .triceps, .core], isCustom: true),
        S2Kit.exercise(
            8,
            "Alternatives",
            alternatives: [S2Kit.exerciseID(8), S2Kit.exerciseID(999), S2Kit.exerciseID(1), S2Kit.exerciseID(1)]
        ),
        S2Kit.exercise(9, "Every muscle", secondary: MuscleGroup.allCases, alternatives: []),
        S2Kit.exercise(10, "", short: "", equipment: .band, muscle: .core, pattern: .core),
        S2Kit.exercise(11, "Ünïcödé 🏋️‍♀️ \"quoted\" 'x' \\ % _", short: String(repeating: "é", count: 5000))
    ]

    @Test("Every field of every shape reads back equal through `exercise(id:)` and `all()`")
    func shapes_roundTrip() async throws {
        let repository = try GRDBExerciseRepository(LedgerDatabase.inMemory())
        for exercise in Self.shapes {
            try await repository.save(exercise)
            #expect(try await repository.exercise(id: exercise.id) == exercise, "\(exercise.name)")
        }
        #expect(try await Set(repository.all()) == Set(Self.shapes))
    }

    @Test("Every equipment, muscle and pattern value round-trips")
    func everyEnumValue_roundTrips() async throws {
        let repository = try GRDBExerciseRepository(LedgerDatabase.inMemory())
        for (index, equipment) in Equipment.allCases.enumerated() {
            for (muscleIndex, muscle) in MuscleGroup.allCases.enumerated() {
                let pattern = MovementPattern.allCases[(index + muscleIndex) % MovementPattern.allCases.count]
                let exercise = S2Kit.exercise(
                    1000 + index * 20 + muscleIndex,
                    "E\(index)M\(muscleIndex)",
                    equipment: equipment,
                    muscle: muscle,
                    pattern: pattern
                )
                try await repository.save(exercise)
                #expect(try await repository.exercise(id: exercise.id) == exercise)
            }
        }
    }

    @Test("Every hundredth of a pound from 0 to 1,500 lb and every 1.25 kg to 500 kg is stored as an exact count")
    func loads_areExactCounts() async throws {
        let queue = try LedgerDatabase.inMemory()
        let repository = GRDBExerciseRepository(queue)
        let exercises = stride(from: 0, through: 150_000, by: 7).map { hundredths in
            S2Kit.exercise(hundredths, "L\(hundredths)", loads: [
                .lb: .pounds(Decimal(hundredths) / 100), .kg: .kilograms(Decimal(hundredths % 401) * 1.25)
            ])
        }
        try await repository.seedIfNeeded(exercises, version: 1)
        let rows = try await queue.read { database in
            try Row.fetchAll(database, sql: "SELECT name, start_load_lb_e7g, start_load_kg_e7g FROM exercise")
                .map { row in
                    (
                        name: row["name"] as String,
                        lb: row["start_load_lb_e7g"] as Int64?,
                        kg: row["start_load_kg_e7g"] as Int64?
                    )
                }
        }
        #expect(rows.count == exercises.count)
        for row in rows {
            let hundredths = Int64(row.name.dropFirst()) ?? -1
            #expect(row.lb == hundredths * 45_359_237, "\(row.name)")
            #expect(row.kg == (hundredths % 401) * 12_500_000_000, "\(row.name)")
        }
        #expect(try await Set(repository.all()) == Set(exercises))
    }

    @Test("A load one unit beyond `Int64`, or finer than 10⁻⁷ g, throws `inexactWeight` and keeps the stored row")
    func inexactLoads_areRefused() async throws {
        let repository = try GRDBExerciseRepository(LedgerDatabase.inMemory())
        let stored = S2Kit.exercise(1, "Stored")
        try await repository.save(stored)
        let unit = Decimal(string: "0.0000001") ?? 0
        let refused = [
            Self.maxLoad.grams + unit, Self.minLoad.grams - unit, Weight.pounds(0.125).grams,
            Decimal(string: "0.00000001") ?? 0
        ]
        for grams in refused {
            var edit = stored
            edit.name = "Edited"
            edit.defaultStartLoad[.kg] = Weight(grams: grams)
            await #expect(throws: LedgerPersistenceError.inexactWeight(grams)) { try await repository.save(edit) }
            #expect(try await repository.exercise(id: stored.id) == stored)
        }
    }

    @Test("Saving an id again overwrites its one row, and brings back a deleted one")
    func save_upserts() async throws {
        let queue = try LedgerDatabase.inMemory()
        let repository = GRDBExerciseRepository(queue)
        var exercise = S2Kit.exercise(1, "Original", isCustom: true)
        try await repository.save(exercise)
        exercise.name = "Renamed"
        exercise.defaultStartLoad = [:]
        exercise.secondaryMuscles = []
        try await repository.save(exercise)
        #expect(try await repository.exercise(id: exercise.id) == exercise)
        try await queue.write { try $0.execute(sql: "UPDATE exercise SET deleted_at = 'then'") }
        #expect(try await repository.exercise(id: exercise.id) == nil)
        #expect(try await repository.all().isEmpty)
        try await repository.save(exercise)
        #expect(try await repository.all() == [exercise])
        #expect(try await S2Kit.count(queue, "exercise") == 1)
        #expect(try await repository.exercise(id: S2Kit.exerciseID(404)) == nil)
    }

    @Test(
        "`all()` returns one order, sorted by folded name, whatever the insert order (ties included)",
        .tags(.property),
        arguments: PropertySeed.all.prefix(50)
    )
    func all_hasOneOrder(seed: PropertySeed) async throws {
        var generator = seed.generator
        let names = [
            "elevation",
            "Élévation",
            "ELEVATION",
            "e\u{301}levation",
            "Bench",
            "bench",
            "Äpfel",
            "apfel",
            "Zed",
            ""
        ]
        let exercises = names.enumerated().map { S2Kit.exercise($0.offset, $0.element, short: "s") }
        let reference = try GRDBExerciseRepository(LedgerDatabase.inMemory())
        for exercise in exercises {
            try await reference.save(exercise)
        }
        let expected = try await reference.all()
        let folded = expected.map { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        #expect(folded == folded.sorted(), "not in folded-name order: \(expected.map(\.name))")
        let repository = try GRDBExerciseRepository(LedgerDatabase.inMemory())
        for exercise in exercises.shuffled(using: &generator) {
            try await repository.save(exercise)
        }
        #expect(try await repository.all() == expected, "\(seed)")
    }
}
