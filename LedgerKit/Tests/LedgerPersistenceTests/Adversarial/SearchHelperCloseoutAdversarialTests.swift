import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S2 close-out round, review SF2 as a property: the repository's `search` is exactly
/// `ExerciseSearch.matches` and the two filters applied to `all()`, and `all()` is in `ExerciseSearch.sorted`
/// order, so an in-memory fake (F07) or the Library's pills (F12) built on the helper agree with the database.
@Suite("Adversarial S2 close-out · search equals the helper", .tags(.persistence, .property), .timeLimit(.minutes(1)))
struct SearchHelperCloseoutAdversarialTests {
    static let pieces = [
        "Ben", "ch", "PRÉ", "ss", "ß", "ö", "E\u{301}", " ", "\t", "\u{00A0}", "\u{3000}", "\u{200B}", "İ", "ı",
        "ﬁ", "Σ", "ς", "%", "_", "\\", "'", "😀", "Ｒ", "row", "-"
    ]

    static func text(_ generator: inout SeededGenerator, upTo count: Int) -> String {
        (0 ..< Int.random(in: 0 ... count, using: &generator)).map { _ in
            pieces.randomElement(using: &generator) ?? ""
        }.joined()
    }

    @Test(
        "search(q, equipment, muscle) == all() filtered by ExerciseSearch.matches and both filters",
        arguments: PropertySeed.all.prefix(60)
    )
    func search_equalsTheHelperOverAll(seed: PropertySeed) async throws {
        var generator = seed.generator
        let repository = try GRDBExerciseRepository(LedgerDatabase.inMemory())
        let exercises = (0 ..< 14).map { number in
            S2Kit.exercise(
                number,
                Self.text(&generator, upTo: 5),
                short: Self.text(&generator, upTo: 2),
                equipment: Equipment.allCases[Int.random(in: 0 ..< 3, using: &generator)],
                muscle: MuscleGroup.allCases[Int.random(in: 0 ..< 3, using: &generator)],
                isCustom: Bool.random(using: &generator)
            )
        }
        let catalog = exercises.filter { !$0.isCustom }
        try await repository.seedIfNeeded(catalog, version: 1)
        for exercise in exercises where exercise.isCustom {
            try await repository.save(exercise)
        }
        let all = try await repository.all()
        #expect(all == ExerciseSearch.sorted(exercises))
        for _ in 0 ..< 10 {
            let name = exercises.randomElement(using: &generator)?.name ?? ""
            let query = Bool.random(using: &generator)
                ? Self.text(&generator, upTo: 3)
                : String(name.shuffled(using: &generator).prefix(3))
            let equipment = Bool.random(using: &generator)
                ? nil : Equipment.allCases.prefix(3).randomElement(using: &generator)
            let muscle = Bool.random(using: &generator)
                ? nil : MuscleGroup.allCases.prefix(3).randomElement(using: &generator)
            let expected = all.filter { exercise in
                ExerciseSearch.matches(exercise, query: query)
                    && equipment.map { $0 == exercise.equipment } ?? true
                    && muscle.map { $0 == exercise.primaryMuscle } ?? true
            }
            let found = try await repository.search(query, equipment: equipment, muscle: muscle)
            let filters = "\(String(describing: equipment)), \(String(describing: muscle))"
            #expect(found == expected, "query \(query.debugDescription), \(filters)")
        }
    }
}
