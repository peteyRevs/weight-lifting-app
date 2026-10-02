import Foundation
import LedgerDomain
import Testing

/// Product decision #23's matching and the name order, as the one public rule the repositories (F05), the
/// Library (F12) and the in-memory fakes (F07) share. The repository contract checks the same rule end to end.
@Suite("ExerciseSearch", .tags(.domain))
struct ExerciseSearchTests {
    static func exercise(_ number: UInt8, _ name: String, short: String = "") -> Exercise {
        Exercise(
            id: ExerciseID(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, number))),
            name: name,
            shortName: short,
            equipment: .barbell,
            primaryMuscle: .chest,
            pattern: .horizontalPush,
            defaultStartLoad: [:]
        )
    }

    @Test("A key is folded for case and diacritics and trimmed, the same in every locale")
    func key_trimsAndFolds() {
        #expect(ExerciseSearch.key("  Élévation LATÉRALE \n") == "elevation laterale")
        #expect(ExerciseSearch.key("E\u{301}le\u{301}vation") == "elevation") // decomposed accents
        #expect(ExerciseSearch.key("Box Squat (50%)") == "box squat (50%)")
        #expect(ExerciseSearch.key(" \t ").isEmpty)
    }

    @Test("A key folds width too, and trims after folding, so a key is its own key (S2 fix round 2)")
    func key_foldsWidth_thenTrims() {
        #expect(ExerciseSearch.key("ＢＥＮＣＨ Ｐｒｅｓｓ") == "bench press") // fullwidth letters
        #expect(ExerciseSearch.key("bench \u{301}") == "bench") // the blank folding uncovers is trimmed
        #expect(ExerciseSearch.key("\u{3000}Ｒｏｗ\t") == "row")
        for text in ["bench \u{301}", "Ｅ\u{301}LE \u{301}", "  Élévation\u{A0}"] {
            let key = ExerciseSearch.key(text)
            #expect(ExerciseSearch.key(key) == key, "\(text.debugDescription)")
        }
        // Letters that are not a base letter plus a mark stay themselves (locale-neutral folding).
        #expect(ExerciseSearch.key("Ilık Øresund") == "ilık øresund")
    }

    @Test("A query matches a substring of the name or short name, ignoring case, diacritics, width and blanks")
    func matches_nameOrShortName() {
        let row = Self.exercise(1, "Chest-Supported Row", short: "CS Row")
        let rdl = Self.exercise(2, "Romanian Deadlift", short: "RDL")
        let lateral = Self.exercise(3, "Élévation Latérale")
        #expect(ExerciseSearch.matches(row, query: "row"))
        #expect(ExerciseSearch.matches(row, query: "  SUPPORTED "))
        #expect(ExerciseSearch.matches(rdl, query: "rdl"))
        #expect(ExerciseSearch.matches(lateral, query: "elev"))
        #expect(ExerciseSearch.matches(lateral, query: "É"))
        #expect(ExerciseSearch.matches(rdl, query: "ｒｄｌ"), "fullwidth, as a Japanese IME types it")
        #expect(!ExerciseSearch.matches(rdl, query: "row"))
        #expect(!ExerciseSearch.matches(row, query: "row cs"), "the text never spans name and short name")
        #expect(ExerciseSearch.matches(rdl, query: ""), "a blank query matches every exercise")
        #expect(ExerciseSearch.matches(rdl, query: " \n"))
        #expect(!ExerciseSearch.matches(rdl, query: "%"), "% is a plain character")
    }

    @Test("Name order is the name's key, then the id; the comparator and sorted agree")
    func nameOrder_keyThenID() {
        let exercises = [
            Self.exercise(4, "Row"),
            Self.exercise(3, "élévation"),
            Self.exercise(2, "Élévation"),
            Self.exercise(1, "bench"),
            Self.exercise(5, "  Arnold Press")
        ]
        // The two "elevation" keys are equal, so the lower id (2, "Élévation") comes first.
        #expect(ExerciseSearch.sorted(exercises).map(\.name) == [
            "  Arnold Press",
            "bench",
            "Élévation",
            "élévation",
            "Row"
        ])
        #expect(exercises.sorted(by: ExerciseSearch.isInNameOrder) == ExerciseSearch.sorted(exercises))
        #expect(!ExerciseSearch.isInNameOrder(exercises[0], exercises[0]))
    }
}
