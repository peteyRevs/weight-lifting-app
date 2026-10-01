import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// An `exercise` row this app cannot read (a case a later version added, or damage) is left out of `all()`,
/// `search` and `observeAll`, logged and kept, as S1 keeps unreadable event rows; `exercise(id:)` throws by
/// name. Nothing traps.
@Suite("GRDBExerciseRepository · unreadable row", .tags(.persistence), .timeLimit(.minutes(1)))
struct DamagedExerciseRowTests {
    /// A damage in SQL, and the error `exercise(id:)` throws for it.
    struct Damage: Sendable, CustomStringConvertible {
        let description: String
        let error: LedgerPersistenceError
    }

    static let damages = [
        Damage(description: "equipment = 'trapBar'", error: .malformedColumn("exercise.equipment")),
        Damage(description: "primary_muscle = 'neck'", error: .malformedColumn("exercise.primary_muscle")),
        Damage(description: "pattern = 42", error: .malformedColumn("exercise.pattern")),
        Damage(description: "secondary_muscles = '[\"neck\"]'", error: .malformedColumn("exercise.secondary_muscles")),
        Damage(description: "secondary_muscles = 'chest'", error: .malformedColumn("exercise.secondary_muscles")),
        Damage(
            description: "curated_alternatives = '[\"x\"]'",
            error: .malformedColumn("exercise.curated_alternatives")
        ),
        Damage(description: "is_custom = 'yes'", error: .malformedColumn("exercise.is_custom")),
        Damage(description: "start_load_lb_e7g = 1.5", error: .malformedColumn("exercise.start_load_lb_e7g")),
        Damage(description: "short_name = x'80'", error: .malformedColumn("exercise.short_name")),
        Damage(description: "name = x'80'", error: .malformedColumn("exercise.name"))
    ]

    static let damaged = Seeders.catalogEntry(1)

    @Test(
        "An unreadable row is left out of every list, throws by name from exercise(id:), and is kept",
        arguments: damages
    )
    func unreadableRow_isLeftOut_throwsByName_andIsKept(_ damage: Damage) async throws {
        let repositories = try Repositories()
        let exercises = repositories.exercises
        let catalog = Seeders.catalog(count: 3, version: 1).exercises
        try await exercises.seedIfNeeded(catalog, version: 1)
        let id = ColumnCodec.text(Self.damaged.id)
        try await repositories.execute("UPDATE exercise SET \(damage) WHERE id = ?", [id])
        let readable = catalog.filter { $0.id != Self.damaged.id }
        #expect(try await Set(exercises.all()) == Set(readable))
        #expect(try await Set(exercises.search("catalog", equipment: nil, muscle: nil)) == Set(readable))
        var values = exercises.observeAll().makeAsyncIterator()
        #expect(await values.next().map(Set.init) == Set(readable))
        await #expect(throws: damage.error) { try await exercises.exercise(id: Self.damaged.id) }
        #expect(try await repositories.count("SELECT COUNT(*) FROM exercise WHERE id = ?", [id]) == 1)
    }

    @Test("A malformed id, text or bytes, is left out of every list, and a save of the same exercise adds it back")
    func malformedID_isLeftOut() async throws {
        let repositories = try Repositories()
        try await repositories.exercises.seedIfNeeded(Seeders.catalog(count: 3, version: 1).exercises, version: 1)
        try await repositories.execute("UPDATE exercise SET id = 'not-a-uuid' WHERE id = ?", [
            ColumnCodec.text(Seeders.catalogID(0))
        ])
        try await repositories.execute("UPDATE exercise SET id = x'80' WHERE id = ?", [
            ColumnCodec.text(Seeders.catalogID(2))
        ])
        #expect(try await repositories.exercises.all() == [Seeders.catalogEntry(1)])
        try await repositories.exercises.save(Seeders.catalogEntry(0))
        #expect(try await Set(repositories.exercises.all()) == [Seeders.catalogEntry(0), Seeders.catalogEntry(1)])
    }

    /// S2-2: GRDB's integer read would clamp `9.3e18` to `Int64.max`, so every later upgrade would do nothing.
    @Test(
        "An applied catalog version that is not an integer makes seeding throw by name, and seeds nothing",
        arguments: ["9.3e18", "1.5", "'v1'", "x'01'"]
    )
    func damagedCatalogVersion_throwsByName(value: String) async throws {
        let repositories = try Repositories()
        try await repositories.exercises.seedIfNeeded(Seeders.catalog(count: 2, version: 1).exercises, version: 1)
        try await repositories.execute("UPDATE exercise SET catalog_version = \(value) WHERE id = ?", [
            ColumnCodec.text(Seeders.catalogID(0))
        ])
        await #expect(throws: LedgerPersistenceError.malformedColumn("exercise.catalog_version")) {
            try await repositories.exercises.seedIfNeeded(Seeders.catalog(count: 3, version: 2).exercises, version: 2)
        }
        #expect(try await repositories.count("SELECT COUNT(*) FROM exercise") == 2)
    }
}
