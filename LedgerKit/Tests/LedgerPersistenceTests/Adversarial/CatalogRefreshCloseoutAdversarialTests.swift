import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S2 close-out round, review SF1 / product decision #24: an upgrade refreshes the live catalog rows it
/// lists in place. Content changes move `updated_at`; an upgrade that changes nothing moves only
/// `catalog_version`. Deleted rows, custom rows and catalog rows the lifter saved are never written; lower and
/// equal versions do nothing; repeated launches change no byte.
@Suite("Adversarial S2 close-out · catalog refresh", .tags(.persistence), .timeLimit(.minutes(1)))
struct CatalogRefreshCloseoutAdversarialTests {
    /// The catalog: entries 100 … 103.
    static let catalog: [Exercise] = [
        S2Kit.exercise(100, "Back Squat", short: "Squat", equipment: .barbell, muscle: .quads),
        S2Kit.exercise(101, "Bench Press", short: "Bench"),
        S2Kit.exercise(
            102, "Romanian Deadlift", short: "RDL", muscle: .hamstrings, alternatives: [S2Kit.exerciseID(100)]
        ),
        S2Kit.exercise(103, "Pull-Up", short: "Pull-Up", equipment: .bodyweight, muscle: .back, loads: [:])
    ]

    @Test("An upgrade that changes no content moves only catalog_version, on every row, across repeated launches")
    func noChangeUpgrade_keepsUpdatedAt() async throws {
        let kit = try S2CatalogKit()
        try await kit.exercises.seedIfNeeded(Self.catalog, version: 1)
        let seededAt = kit.stamp()
        for (launch, version) in [2, 2, 3, 3, 3, 1].enumerated() {
            kit.clock.advance()
            try await kit.exercises.seedIfNeeded(Self.catalog, version: version)
            let expected = max(version, launch >= 2 ? 3 : 2)
            for number in 100 ... 103 {
                #expect(
                    try await kit.meta(number) == [expected.databaseValue, seededAt, seededAt, .null],
                    "launch \(launch), exercise \(number)"
                )
            }
        }
        #expect(try await kit.exercises.all() == ExerciseSearch.sorted(Self.catalog))
    }

    @Test("A changed field refreshes its row in place: same id and created_at, new updated_at; others keep theirs")
    func contentChange_refreshesOnlyThatRow() async throws {
        let kit = try S2CatalogKit()
        try await kit.exercises.seedIfNeeded(Self.catalog, version: 1)
        let seededAt = kit.stamp()
        let edits: [(String, (inout Exercise) -> Void)] = [
            ("name", { $0.name = "Back Squat (High Bar)" }),
            ("short name", { $0.shortName = "HBBS" }),
            ("equipment", { $0.equipment = .machine }),
            ("primary muscle", { $0.primaryMuscle = .glutes }),
            ("secondary muscles", { $0.secondaryMuscles = [.glutes, .hamstrings] }),
            ("pattern", { $0.pattern = .squat }),
            ("a load", { $0.defaultStartLoad[.lb] = .pounds(50) }),
            ("a load removed", { $0.defaultStartLoad[.kg] = nil }),
            ("alternatives", { $0.curatedAlternatives = [S2Kit.exerciseID(101)] })
        ]
        for (index, (label, edit)) in edits.enumerated() {
            let version = index + 2
            var catalog = Self.catalog
            catalog = try await kit.exercises.all().filter { catalog.map(\.id).contains($0.id) }
            edit(&catalog[catalog.firstIndex { $0.id == S2Kit.exerciseID(100) } ?? 0])
            kit.clock.advance()
            let before = try await (101 ... 103).asyncMap { try await kit.meta($0) }
            try await kit.exercises.seedIfNeeded(catalog, version: version)
            #expect(
                try await kit.meta(100) == [version.databaseValue, seededAt, kit.stamp(), .null],
                "\(label): the refreshed row's metadata"
            )
            #expect(try await kit.exercise(100) == catalog.first { $0.id == S2Kit.exerciseID(100) }, "\(label)")
            let after = try await (101 ... 103).asyncMap { try await kit.meta($0) }
            #expect(after.map { Array($0.dropFirst()) } == before.map { Array($0.dropFirst()) }, "\(label): others")
        }
    }

    @Test("A catalog entry marked custom refreshes as a catalog row, and the flag alone is no content change")
    func customFlagInTheEntry_isNotAChange() async throws {
        let kit = try S2CatalogKit()
        try await kit.exercises.seedIfNeeded(Self.catalog, version: 1)
        let seededAt = kit.stamp()
        kit.clock.advance()
        let flagged = Self.catalog.map { entry in
            var copy = entry
            copy.isCustom = true
            return copy
        }
        try await kit.exercises.seedIfNeeded(flagged, version: 2)
        #expect(try await kit.meta(101) == [2.databaseValue, seededAt, seededAt, .null])
        #expect(try await kit.exercise(101)?.isCustom == false)
    }

    @Test("Deleted rows, custom rows holding a catalog id, and rows the lifter saved are never refreshed")
    func deletedCustomAndLifterRows_areUntouched() async throws {
        let kit = try S2CatalogKit()
        let custom = S2Kit.exercise(103, "My Pull-Up", equipment: .bodyweight, muscle: .back, isCustom: true)
        try await kit.exercises.save(custom)
        try await kit.exercises.seedIfNeeded(Self.catalog, version: 1)
        try await kit.queue.write { database in
            try database.execute(
                sql: "UPDATE exercise SET deleted_at = '2026-09-01T00:00:00.000Z' WHERE id = ?",
                arguments: [ColumnCodec.text(S2Kit.exerciseID(102))]
            )
        }
        let seededAt = kit.stamp()
        kit.clock.advance()
        // An unchanged save: the row becomes the lifter's, and its updated_at stays (N1).
        try await kit.exercises.save(Self.catalog[1])
        #expect(try await kit.meta(101) == [.null, seededAt, seededAt, .null], "the lifter's save")
        let before = try await kit.dump()
        kit.clock.advance()
        let changed = Self.catalog.map { entry in
            var copy = entry
            copy.name += " (v2)"
            return copy
        }
        try await kit.exercises.seedIfNeeded(changed, version: 2)
        let after = try await kit.dump()
        for number in 101 ... 103 {
            let id = ColumnCodec.text(S2Kit.exerciseID(number))
            #expect(after.filter { $0.contains(id) } == before.filter { $0.contains(id) }, "row \(number) changed")
        }
        #expect(try await kit.exercise(100)?.name == "Back Squat (v2)")
        #expect(try await kit.exercise(101) == Self.catalog[1])
        #expect(try await kit.exercise(103) == custom)
    }

    @Test("A lifter's save of a deleted catalog row revives it as the lifter's; an upgrade then leaves it")
    func revivedByTheLifter_isNotRefreshed() async throws {
        let kit = try S2CatalogKit()
        try await kit.exercises.seedIfNeeded(Self.catalog, version: 1)
        try await kit.queue.write { database in
            try database.execute(
                sql: "UPDATE exercise SET deleted_at = '2026-09-01T00:00:00.000Z' WHERE id = ?",
                arguments: [ColumnCodec.text(S2Kit.exerciseID(101))]
            )
        }
        try await kit.exercises.save(Self.catalog[1])
        #expect(try await kit.meta(101).first == .null)
        var changed = Self.catalog
        changed[1].name = "Bench Press (v2)"
        try await kit.exercises.seedIfNeeded(changed, version: 2)
        #expect(try await kit.exercise(101) == Self.catalog[1])
    }
}

/// An exercise repository over an in-memory database, with a settable clock and SQL probes.
struct S2CatalogKit {
    let queue: DatabaseQueue
    let clock: S2Kit.Clock
    let exercises: GRDBExerciseRepository

    init() throws {
        queue = try LedgerDatabase.inMemory()
        let settable = S2Kit.Clock()
        clock = settable
        exercises = GRDBExerciseRepository(queue, now: { settable.now })
    }

    /// Every column of every exercise row, `catalog_version` included.
    func dump() async throws -> [String] {
        try await queue.read { database in
            try Row.fetchAll(database, sql: "SELECT * FROM exercise ORDER BY id").map(\.description)
        }
    }

    /// One row's metadata: catalog_version, created_at, updated_at, deleted_at.
    func meta(_ number: Int) async throws -> [DatabaseValue] {
        try await queue.read { database in
            let row = try Row.fetchOne(
                database,
                sql: "SELECT catalog_version, created_at, updated_at, deleted_at FROM exercise WHERE id = ?",
                arguments: [ColumnCodec.text(S2Kit.exerciseID(number))]
            )
            return row.map { row in row.columnNames.map { row[$0] as DatabaseValue } } ?? []
        }
    }

    func stamp() -> DatabaseValue {
        ColumnCodec.timestamp(clock.now).databaseValue
    }
}

extension S2CatalogKit {
    func exercise(_ number: Int) async throws -> Exercise? {
        try await exercises.exercise(id: S2Kit.exerciseID(number))
    }
}

extension ClosedRange<Int> {
    func asyncMap<Value>(_ transform: (Int) async throws -> Value) async rethrows -> [Value] {
        var values: [Value] = []
        for element in self {
            try await values.append(transform(element))
        }
        return values
    }
}
