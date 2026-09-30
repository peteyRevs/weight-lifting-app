import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S2 adversarial round 1, criterion 11: `seedIfNeeded` is idempotent at one version, additive at a higher
/// one, never writes a custom exercise, and never skips a catalog id because a stored exercise has its name.
@Suite("Adversarial S2 · catalog seeding", .tags(.persistence), .timeLimit(.minutes(1)))
struct ExerciseSeedingAdversarialTests {
    /// Catalog entries `range`, with exact loads in both units.
    static func catalog(_ range: Range<Int>) -> [Exercise] {
        range.map { number in
            S2Kit.exercise(
                100 + number, "Catalog \(number)", short: "C\(number)", equipment: Equipment.allCases[number % 7],
                muscle: MuscleGroup.allCases[number % 11], secondary: [.core, .glutes],
                loads: [.lb: .pounds(Decimal(number) * 2.5), .kg: .kilograms(Decimal(number) * 1.25)],
                alternatives: [S2Kit.exerciseID(100 + (number + 1) % 10)]
            )
        }
    }

    static let custom = S2Kit.exercise(1, "Bench Press", short: "BP", loads: [.lb: .pounds(0.01)], isCustom: true)

    static func dump(_ queue: DatabaseQueue) async throws -> [String] {
        try await queue.read { database in
            try Row.fetchAll(database, sql: "SELECT * FROM exercise ORDER BY id").map(\.description)
        }
    }

    static func stack() async throws -> (DatabaseQueue, GRDBExerciseRepository) {
        let queue = try LedgerDatabase.inMemory()
        let repository = GRDBExerciseRepository(queue)
        try await repository.save(custom)
        return (queue, repository)
    }

    @Test("Seeding the same version twice changes no byte, and the custom exercise is untouched")
    func sameVersionTwice_changesNothing() async throws {
        let (queue, repository) = try await Self.stack()
        try await repository.seedIfNeeded(Self.catalog(0 ..< 10), version: 1)
        let once = try await Self.dump(queue)
        try await repository.seedIfNeeded(Self.catalog(0 ..< 10), version: 1)
        try await repository.seedIfNeeded(Self.catalog(0 ..< 12), version: 1)
        #expect(try await Self.dump(queue) == once)
        #expect(try await repository.exercise(id: Self.custom.id) == Self.custom)
        #expect(try await repository.all().count == 11)
    }

    @Test("Every seeded entry reads back equal, loads exact, as a catalog row")
    func seeded_roundTrip() async throws {
        let (_, repository) = try await Self.stack()
        let catalog = Self.catalog(0 ..< 10)
        try await repository.seedIfNeeded(catalog, version: 3)
        for entry in catalog {
            #expect(try await repository.exercise(id: entry.id) == entry)
        }
    }

    @Test("A higher version adds only the new ids, duplicates nothing, and a lower version then does nothing")
    func upgrade_isAdditive() async throws {
        let (queue, repository) = try await Self.stack()
        try await repository.seedIfNeeded(Self.catalog(0 ..< 10), version: 1)
        try await repository.seedIfNeeded(Self.catalog(5 ..< 15), version: 2)
        #expect(try await repository.all().count == 16)
        #expect(try await S2Kit.count(queue, "exercise") == 16)
        let upgraded = try await Self.dump(queue)
        try await repository.seedIfNeeded(Self.catalog(0 ..< 30), version: 1)
        try await repository.seedIfNeeded(Self.catalog(0 ..< 30), version: 2)
        #expect(try await Self.dump(queue) == upgraded)
        try await repository.seedIfNeeded(Self.catalog(0 ..< 20), version: 3)
        #expect(try await repository.all().count == 21)
    }

    @Test("A catalog entry named like a custom exercise (any case or accents) is still seeded; the custom one stays")
    func nameClash_seedsTheCatalogID() async throws {
        let (_, repository) = try await Self.stack()
        let clashes = [
            S2Kit.exercise(201, "bench press", short: "BP"), S2Kit.exercise(202, "BÉNCH PRÉSS", short: "bp"),
            S2Kit.exercise(203, "Bench Press", short: "BP")
        ]
        try await repository.seedIfNeeded(clashes, version: 1)
        for entry in clashes {
            #expect(try await repository.exercise(id: entry.id) == entry)
        }
        #expect(try await repository.exercise(id: Self.custom.id) == Self.custom)
        #expect(try await repository.search("bench press", equipment: nil, muscle: nil).count == 4)
    }

    @Test("A catalog entry whose id a custom exercise holds leaves the custom exercise as it is")
    func idClash_leavesTheCustomRow() async throws {
        let (queue, repository) = try await Self.stack()
        let before = try await Self.dump(queue)
        let entry = S2Kit.exercise(1, "Catalog Bench", short: "CB", equipment: .machine)
        try await repository.seedIfNeeded([entry], version: 1)
        #expect(try await Self.dump(queue) == before)
        #expect(try await repository.exercise(id: Self.custom.id) == Self.custom)
    }

    @Test("An entry with an inexact load seeds nothing, and the same version then seeds once the catalog is fixed")
    func inexactEntry_seedsNothing() async throws {
        let (queue, repository) = try await Self.stack()
        let before = try await Self.dump(queue)
        var broken = Self.catalog(0 ..< 10)
        broken[9].defaultStartLoad[.lb] = .pounds(0.125)
        await #expect(throws: LedgerPersistenceError.inexactWeight(Weight.pounds(0.125).grams)) {
            try await repository.seedIfNeeded(broken, version: 1)
        }
        #expect(try await Self.dump(queue) == before)
        try await repository.seedIfNeeded(Self.catalog(0 ..< 10), version: 1)
        #expect(try await repository.all().count == 11)
    }

    /// F03 validates unique catalog ids, so only a broken bundle lists one twice.
    @Test("(documents) A catalog listing one id twice stores it once: the last entry wins")
    func duplicateIDsInTheCatalog() async throws {
        let (queue, repository) = try await Self.stack()
        let first = S2Kit.exercise(300, "First", short: "F")
        let second = S2Kit.exercise(300, "Second", short: "S", equipment: .band)
        try await repository.seedIfNeeded([first, second], version: 1)
        #expect(try await repository.exercise(id: first.id) == second)
        #expect(try await S2Kit.count(queue, "exercise") == 2)
    }

    @Test("A lifter's edit of a catalog exercise, and a deleted catalog row, survive a later upgrade")
    func upgrade_leavesStoredRowsAsTheyAre() async throws {
        let (queue, repository) = try await Self.stack()
        let catalog = Self.catalog(0 ..< 5)
        try await repository.seedIfNeeded(catalog, version: 1)
        var edited = catalog[0]
        edited.name = "My Row"
        try await repository.save(edited)
        try await queue.write { database in
            try database.execute(sql: "UPDATE exercise SET deleted_at = 'then' WHERE id = ?", arguments: [
                ColumnCodec.text(catalog[1].id)
            ])
        }
        try await repository.seedIfNeeded(Self.catalog(0 ..< 8), version: 2)
        #expect(try await repository.exercise(id: edited.id) == edited)
        #expect(try await repository.exercise(id: catalog[1].id) == nil)
        #expect(try await repository.all().count == 1 + 8 - 1)
    }

    @Test("Eight concurrent seeds of one version, and two racing upgrades, store each id once")
    func concurrentSeeds_storeEachIDOnce() async throws {
        let (queue, repository) = try await Self.stack()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0 ..< 8 {
                group.addTask { try await repository.seedIfNeeded(Self.catalog(0 ..< 40), version: 1 + index % 2) }
            }
            try await group.waitForAll()
        }
        #expect(try await S2Kit.count(queue, "exercise") == 41)
        #expect(try await repository.all().count == 41)
    }
}
