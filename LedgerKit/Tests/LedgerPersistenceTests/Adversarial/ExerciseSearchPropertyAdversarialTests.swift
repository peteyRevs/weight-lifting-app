import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S2 adversarial round 1, decision #23 as a property: over random names built from accented, decomposed,
/// cased and wildcard pieces, `search` returns exactly the exercises whose folded name or short name contains
/// the folded, trimmed query, in `all()` order.
@Suite("Adversarial S2 · exercise search property", .tags(.persistence, .property), .timeLimit(.minutes(1)))
struct ExerciseSearchPropertyAdversarialTests {
    static let pieces = [
        "ben", "CH", "pré", "ss", "ß", "Ö", "row", "é", "e\u{301}", "ÑA", "_", "%", "lat", " ", "-", "Ø", "ı", "İ",
        "\\", "[", "'", "ﬁ", "Å", "a\u{30A}", "😀", "ǅ", "Σ", "ς"
    ]

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// A query: a random run of characters from `text`, each maybe re-cased or stripped of its accent.
    static func query(from text: String, _ generator: inout SeededGenerator) -> String {
        let characters = Array(text)
        guard !characters.isEmpty else {
            return ""
        }
        let start = Int.random(in: 0 ..< characters.count, using: &generator)
        let end = Int.random(in: start ... characters.count, using: &generator)
        return characters[start ..< end].map { character -> String in
            switch Int.random(in: 0 ... 3, using: &generator) {
            case 0: character.uppercased()
            case 1: character.lowercased()
            case 2: fold(String(character))
            default: String(character)
            }
        }.joined()
    }

    @Test("Search equals the folded-substring oracle", arguments: PropertySeed.all.prefix(60))
    func search_matchesTheOracle(seed: PropertySeed) async throws {
        var generator = seed.generator
        let exercises = (0 ..< 10).map { number in
            let name = (0 ..< Int.random(in: 1 ... 5, using: &generator)).map { _ in
                Self.pieces.randomElement(using: &generator) ?? ""
            }.joined()
            let short = Self.pieces.randomElement(using: &generator) ?? ""
            return S2Kit.exercise(number, name, short: short, equipment: Equipment.allCases[number % 2])
        }
        let repository = try GRDBExerciseRepository(LedgerDatabase.inMemory())
        for exercise in exercises {
            try await repository.save(exercise)
        }
        let all = try await repository.all()
        for _ in 0 ..< 12 {
            let source = exercises.randomElement(using: &generator)
            let text = Bool.random(using: &generator) ? source?.name : source?.shortName
            let raw = Self.query(from: text ?? "", &generator)
            let needle = Self.fold(raw.trimmingCharacters(in: .whitespacesAndNewlines))
            let expected = all.filter { exercise in
                needle.isEmpty || Self.fold(exercise.name).contains(needle) || Self.fold(exercise.shortName)
                    .contains(needle)
            }
            let found = try await repository.search(raw, equipment: nil, muscle: nil)
            #expect(found == expected, "\(seed) query \(raw.debugDescription)")
            let barbell = try await repository.search(raw, equipment: .barbell, muscle: nil)
            #expect(barbell == expected.filter { $0.equipment == .barbell }, "\(seed) query \(raw.debugDescription)")
        }
    }
}
