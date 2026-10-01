import Foundation
import LedgerDomain
import Testing

/// F05 S2 close-out round, review SF2: `ExerciseSearch`, the one public rule for decision #23. Folding across
/// case, diacritics, width and whitespace; blank queries; and the helper's laws (a key is a fixed point over
/// text without a lone combining mark, the two `matches` agree, the name order is a strict total order that
/// `sorted` follows whatever the input order).
@Suite("Adversarial S2 close-out · ExerciseSearch", .tags(.domain))
struct ExerciseSearchCloseoutAdversarialTests {
    static func exercise(_ number: Int, _ name: String, short: String = "") -> Exercise {
        Exercise(
            id: ExerciseID(Fixtures.uuid(number)),
            name: name,
            shortName: short,
            equipment: .barbell,
            primaryMuscle: .chest,
            pattern: .horizontalPush,
            defaultStartLoad: [:]
        )
    }

    struct Case: Sendable, CustomStringConvertible {
        let name: String
        let query: String
        let matches: Bool

        var description: String {
            "\(name.debugDescription) ∋ \(query.debugDescription): \(matches)"
        }
    }

    static let folding: [Case] = [
        Case(name: "Bench Press", query: "BENCH pRESS", matches: true),
        Case(name: "ÉLÉVATION LATÉRALE", query: "elevation lat", matches: true),
        Case(name: "Elevation", query: "ÉLÉV", matches: true),
        Case(name: "E\u{301}le\u{301}vation", query: "élé", matches: true), // decomposed name, precomposed query
        Case(name: "Élévation", query: "E\u{301}LE\u{301}", matches: true), // precomposed name, decomposed query
        Case(name: "Ñandú Row", query: "nandu", matches: true),
        Case(name: "İnce Curl", query: "ince", matches: true),
        Case(name: "ΣΙΣΥΦΟΣ Push", query: "σισυφος", matches: true), // final sigma folds like medial
        Case(name: "Bench Press", query: "  bench  ", matches: true),
        Case(name: "Bench Press", query: "\t\nbench press\r\n", matches: true),
        Case(name: "Bench Press", query: "\u{00A0}bench\u{3000}", matches: true), // NBSP, ideographic space
        Case(name: "  Bench Press  ", query: "bench press", matches: true),
        // (documents) not folded: width, internal blanks, zero-width characters, dotless i
        Case(name: "Bench Press", query: "ＢＥＮＣＨ", matches: false), // fullwidth Latin
        Case(name: "ＢＥＮＣＨ Press", query: "bench", matches: false),
        Case(name: "Bench Press", query: "bench  press", matches: false),
        Case(name: "Bench Press", query: "bench\u{00A0}press", matches: false),
        Case(name: "Bench Press", query: "bench\tpress", matches: false),
        Case(name: "Ilık Row", query: "ilik", matches: false),
        Case(name: "Øresund Carry", query: "oresund", matches: false), // Ø is a letter, not O plus a mark
        // (documents) Foundation's whitespace set still holds U+200B, so a zero-width space is an outer blank
        Case(name: "Bench Press", query: "\u{200B}bench", matches: true)
    ]

    @Test("Folding: case, diacritics and outer blanks never matter; width and inner blanks do", arguments: folding)
    func folding_matchesAsDocumented(_ test: Case) {
        let exercise = Self.exercise(1, test.name)
        #expect(ExerciseSearch.matches(exercise, query: test.query) == test.matches)
        let asShortName = Self.exercise(1, "zzz", short: test.name)
        #expect(ExerciseSearch.matches(asShortName, query: test.query) == test.matches, "as the short name")
    }

    @Test(
        "An empty or blank query matches every exercise, even one with empty names",
        arguments: ["", " ", "\t", "\n", "\r\n", "\u{00A0}", "\u{2003}", "\u{3000}", "\u{85}", " \u{2028} "]
    )
    func blankQuery_matchesEverything(query: String) {
        #expect(ExerciseSearch.key(query).isEmpty)
        for exercise in [Self.exercise(1, ""), Self.exercise(2, "Squat", short: "SQ"), Self.exercise(3, "😀")] {
            #expect(ExerciseSearch.matches(exercise, query: query))
        }
    }

    /// Nit (documents): `key` trims before it folds, so a blank that folding uncovers (a space carrying a
    /// combining mark) stays, and `key` is then not a fixed point. Folding first, then trimming, would make it
    /// one. No keyboard types a lone combining mark after a space, so this only pins the behaviour.
    @Test("(documents) A blank carrying a combining mark is folded to a blank that is not trimmed")
    func blankWithAMark_isNotTrimmed() {
        #expect(ExerciseSearch.key("bench \u{301}") == "bench ")
        #expect(ExerciseSearch.key(ExerciseSearch.key("bench \u{301}")) == "bench")
        #expect(!ExerciseSearch.matches(Self.exercise(1, "Bench"), query: "bench \u{301}"))
    }

    static let pieces = [
        "ben", "CH", "pré", "ß", "Ö", "e\u{301}", " ", "  ", "\t", "\u{00A0}", "İ", "ı", "ﬁ", "Σ", "ς", "ǅ",
        "%", "_", "😀", "Ａ", "a\u{30A}", "-", "row"
    ]

    static func text(_ generator: inout SeededGenerator) -> String {
        (0 ..< Int.random(in: 0 ... 5, using: &generator)).map { _ in
            pieces.randomElement(using: &generator) ?? ""
        }.joined()
    }

    @Test(
        "Laws: the two matches agree, a key's key is itself, and a key matches its own source",
        arguments: PropertySeed.all.prefix(100)
    )
    func laws_hold(seed: PropertySeed) {
        var generator = seed.generator
        for _ in 0 ..< 20 {
            let name = Self.text(&generator)
            let short = Self.text(&generator)
            let query = Self.text(&generator)
            let exercise = Self.exercise(1, name, short: short)
            let needle = ExerciseSearch.key(query)
            #expect(
                ExerciseSearch.matches(exercise, query: query)
                    == ExerciseSearch.matches(name: name, shortName: short, needle: needle)
            )
            #expect(ExerciseSearch.key(needle) == needle, "key is not idempotent on \(query.debugDescription)")
            #expect(ExerciseSearch.matches(exercise, query: name), "a name misses itself: \(name.debugDescription)")
        }
    }

    @Test(
        "Name order: a strict total order, and `sorted` gives one order whatever the input order",
        arguments: PropertySeed.all.prefix(50)
    )
    func nameOrder_isTotal(seed: PropertySeed) {
        var generator = seed.generator
        let exercises = (0 ..< 12).map { Self.exercise($0, Self.text(&generator)) }
        let sorted = ExerciseSearch.sorted(exercises)
        #expect(sorted == exercises.sorted(by: ExerciseSearch.isInNameOrder))
        #expect(ExerciseSearch.sorted(exercises.shuffled(using: &generator)) == sorted)
        for lhs in exercises {
            #expect(!ExerciseSearch.isInNameOrder(lhs, lhs))
            for rhs in exercises where lhs.id != rhs.id {
                #expect(ExerciseSearch.isInNameOrder(lhs, rhs) != ExerciseSearch.isInNameOrder(rhs, lhs))
            }
        }
        for (earlier, later) in zip(sorted, sorted.dropFirst()) {
            #expect(ExerciseSearch.key(earlier.name) <= ExerciseSearch.key(later.name))
        }
    }
}
