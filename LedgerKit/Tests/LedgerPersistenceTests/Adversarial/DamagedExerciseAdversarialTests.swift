import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S2 adversarial round 1: strict reads of a damaged `exercise` row (a foreign writer, a later version or
/// damage). The row is left out of `all()`, `search` and `observeAll()`, `exercise(id:)` throws, the other rows
/// still read, nothing traps, and no damaged value is read as a plausible one (`3.5` as 3, `2` as `true`).
@Suite("Adversarial S2 · damaged exercise rows", .tags(.persistence), .timeLimit(.minutes(1)))
struct DamagedExerciseAdversarialTests {
    static let target = S2Kit.exercise(
        2,
        "Target Press",
        short: "TP",
        secondary: [.triceps],
        alternatives: [S2Kit.exerciseID(1)]
    )

    static let damages: [String] = [
        "equipment = 'laser'", "equipment = 'Barbell'", "primary_muscle = 'neck'", "pattern = 'jump'",
        "equipment = 7", "secondary_muscles = '['", "secondary_muscles = '[\"neck\"]'", "secondary_muscles = 'null'",
        "secondary_muscles = '{}'", "secondary_muscles = '[1]'", "secondary_muscles = ''", "secondary_muscles = 3",
        "curated_alternatives = '[\"nope\"]'", "curated_alternatives = '['", "curated_alternatives = 'null'",
        "curated_alternatives = '[\"\"]'", "start_load_lb_e7g = 1.5", "start_load_lb_e7g = 'heavy'",
        "start_load_lb_e7g = x'01'", "start_load_lb_e7g = 9.3e18", "start_load_kg_e7g = -9.3e18",
        "is_custom = 0.5", "is_custom = 'yes'", "is_custom = x'00'",
        "name = x'FF'", "name = x'C0AF'", "short_name = x'EDA080'", "id = 'nope'", "id = x'00'"
    ]

    static func damaged(_ damage: String) async throws -> (DatabaseQueue, GRDBExerciseRepository) {
        let queue = try LedgerDatabase.inMemory()
        let repository = GRDBExerciseRepository(queue)
        for exercise in [S2Kit.exercise(1, "Kept Row"), target, S2Kit.exercise(3, "Kept Press")] {
            try await repository.save(exercise)
        }
        try await queue.write { database in
            try database.execute(
                sql: "UPDATE exercise SET \(damage) WHERE id = ?",
                arguments: [ColumnCodec.text(target.id)]
            )
        }
        return (queue, repository)
    }

    @Test(
        "A damaged row is left out of `all()`, `search` and `observeAll()`; `exercise(id:)` throws",
        arguments: damages
    )
    func damagedRow_isLeftOut(damage: String) async throws {
        let (_, repository) = try await Self.damaged(damage)
        let kept: Set<ExerciseID> = [S2Kit.exerciseID(1), S2Kit.exerciseID(3)]
        #expect(try await Set(repository.all().map(\.id)) == kept)
        #expect(try await Set(repository.search("", equipment: nil, muscle: nil).map(\.id)) == kept)
        #expect(try await repository.search("row", equipment: nil, muscle: nil).map(\.id) == [S2Kit.exerciseID(1)])
        #expect(try await repository.search("press", equipment: .barbell, muscle: .chest)
            .map(\.id) == [S2Kit.exerciseID(3)])
        var iterator = repository.observeAll().makeAsyncIterator()
        #expect(await iterator.next().map { Set($0.map(\.id)) } == kept)
        if !damage.hasPrefix("id =") {
            await #expect(throws: (any Error).self) { try await repository.exercise(id: Self.target.id) }
        }
    }

    /// Spec question (documents): a flag holding an integer other than 0 or 1 reads as `true`, where a fraction,
    /// text or a blob is refused. Harmless for `is_custom`; recorded so the rule is a decision, not an accident.
    @Test("(documents) `is_custom` of 2 or -1 reads as true")
    func outOfRangeFlag_readsAsTrue() async throws {
        for damage in ["is_custom = 2", "is_custom = -1"] {
            let (_, repository) = try await Self.damaged(damage)
            #expect(try await repository.exercise(id: Self.target.id)?.isCustom == true, "\(damage)")
            #expect(try await repository.all().count == 3, "\(damage)")
        }
    }

    /// Every column but `catalog_version`, which a seed listing the row may move (documented).
    static func targetRow(_ queue: DatabaseQueue) async throws -> [String] {
        try await queue.read { database in
            try Row.fetchAll(database, sql: """
            SELECT id, name, short_name, equipment, primary_muscle, secondary_muscles, pattern, start_load_lb_e7g,
                   start_load_kg_e7g, is_custom, curated_alternatives, created_at, updated_at, deleted_at
            FROM exercise WHERE name = 'Target Press'
            """).map(\.description)
        }
    }

    @Test("A damaged row stays stored, byte for byte, through reads, a seed and another row's save")
    func damagedRow_isKept() async throws {
        let (queue, repository) = try await Self.damaged("primary_muscle = 'neck'")
        let before = try await Self.targetRow(queue)
        _ = try await repository.all()
        try await repository.seedIfNeeded([Self.target, S2Kit.exercise(4, "New")], version: 1)
        try await repository.save(S2Kit.exercise(1, "Kept Row Renamed"))
        #expect(try await Self.targetRow(queue) == before)
        #expect(!before.isEmpty)
    }

    @Test("A damaged `catalog_version` never traps a seed", arguments: [
        "'v1'", "x'01'", "1.5", "9.3e18", "-1", "''"
    ])
    func damagedCatalogVersion_neverTraps(value: String) async throws {
        let queue = try LedgerDatabase.inMemory()
        let repository = GRDBExerciseRepository(queue)
        try await repository.seedIfNeeded([S2Kit.exercise(1, "One")], version: 1)
        try await queue.write { try $0.execute(sql: "UPDATE exercise SET catalog_version = \(value)") }
        let outcome = await Result { try await repository.seedIfNeeded(
            [S2Kit.exercise(1, "One"), S2Kit.exercise(2, "Two")],
            version: 2
        ) }
        let stored = try await S2Kit.count(queue, "exercise")
        #expect(stored == ((try? outcome.get()) == nil ? 1 : 2), "\(outcome)")
    }
}
