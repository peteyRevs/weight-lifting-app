import Foundation
@testable import LedgerDomain
import Testing

/// Criterion 1: the loader throws a `CatalogError` on every malformed entry and never skips one.
@Suite("Exercise catalog loader (adversarial)", .tags(.domain))
struct CatalogLoaderAdversarialTests {
    /// One field edit: `key` of entry `index` set to raw JSON `value`, or dropped when `nil`.
    struct Change: Sendable {
        let key: String
        let value: String?
        let index: Int
    }

    /// One malformed variant of the valid three-entry document.
    struct Variant: Sendable, CustomTestStringConvertible {
        let label: String
        var changes: [Change]
        var testDescription: String {
            label
        }

        init(_ label: String, _ key: String, _ value: String?, at index: Int = 0) {
            self.label = label
            changes = [Change(key: key, value: value, index: index)]
        }

        init(_ label: String, _ changes: [(String, String?)]) {
            self.label = label
            self.changes = changes.map { Change(key: $0.0, value: $0.1, index: 0) }
        }

        var document: CatalogDocument {
            var edited = CatalogDocument()
            for change in changes {
                edited.set(change.key, change.value, at: change.index)
            }
            return edited
        }
    }

    static let keys = [
        "id", "name", "shortName", "equipment", "primaryMuscle", "secondaryMuscles", "pattern", "startLoad",
        "alternatives", "aliases"
    ]

    static let shapes: [Variant] = keys.map { Variant("missing \($0)", $0, nil) }
        + keys.map { Variant("\($0): null", $0, "null") }
        + [
            Variant("name is a number", "name", "42"),
            Variant("shortName is an array", "shortName", "[]"),
            Variant("secondaryMuscles is a string", "secondaryMuscles", "\"triceps\""),
            Variant("alternatives is a string", "alternatives", "\"\(CatalogDocument.idB)\""),
            Variant("aliases is a string", "aliases", "\"Alpha\""),
            Variant("startLoad is a number", "startLoad", "45"),
            Variant("startLoad without kg", "startLoad", "{ \"lb\": 45 }"),
            Variant("startLoad without lb", "startLoad", "{ \"kg\": 20 }"),
            Variant("startLoad lb is a string", "startLoad", "{ \"lb\": \"45\", \"kg\": 20 }"),
            Variant("startLoad kg is null", "startLoad", "{ \"lb\": 45, \"kg\": null }")
        ]

    static let enums: [Variant] = [
        Variant("equipment capitalised", "equipment", "\"Barbell\""),
        Variant("equipment unknown", "equipment", "\"smith\""),
        Variant("equipment empty", "equipment", "\"\""),
        Variant("primaryMuscle from the prototype's five", "primaryMuscle", "\"legs\""),
        Variant("primaryMuscle capitalised", "primaryMuscle", "\"Chest\""),
        Variant("secondary muscle unknown", "secondaryMuscles", "[\"triceps\", \"arms\"]"),
        Variant("pattern unknown", "pattern", "\"push\""),
        Variant("pattern snake case", "pattern", "\"horizontal_push\""),
        Variant("loadKind unknown", "loadKind", "\"assisted\""),
        Variant("loadKind capitalised", [
            ("equipment", "\"bodyweight\""),
            ("loadKind", "\"Bodyweight\""),
            ("startLoad", "{ \"lb\": 0, \"kg\": 0 }")
        ])
    ]

    static let ids: [Variant] = [
        Variant("id not a UUID", "id", "\"not-a-uuid\""),
        Variant("id empty", "id", "\"\""),
        Variant("id without hyphens", "id", "\"0A2B4C6D00004000800000000000000A\""),
        Variant("id in braces", "id", "\"{0A2B4C6D-0000-4000-8000-00000000000A}\""),
        Variant("id one digit short", "id", "\"0A2B4C6D-0000-4000-8000-00000000000\""),
        Variant("id with a trailing space", "id", "\"0A2B4C6D-0000-4000-8000-00000000000A \""),
        Variant("id is a number", "id", "42"),
        Variant("alternative not a UUID", "alternatives", "[\"\(CatalogDocument.idB)\", \"nope\"]"),
        Variant("duplicate id", "id", "\"\(CatalogDocument.idA)\"", at: 1)
    ]
}

// MARK: - Loads, text, alternatives, muscles

extension CatalogLoaderAdversarialTests {
    static func load(_ lb: String, _ kg: String) -> String {
        "{ \"lb\": \(lb), \"kg\": \(kg) }"
    }

    static let loads: [Variant] = [
        Variant("negative barbell load", "startLoad", load("-45", "-20")),
        Variant("negative kg only", "startLoad", load("45", "-20")),
        Variant("lb off the 5 lb barbell step", "startLoad", load("47.5", "20")),
        Variant("kg off the 2.5 kg barbell step", "startLoad", load("45", "21.25")),
        Variant("lb a hair above a step (exact decimal)", "startLoad", load("45.000000000000000000001", "20")),
        Variant("kg a hair below a step (exact decimal)", "startLoad", load("45", "19.9999999999999999")),
        Variant("lb too large for a Decimal", "startLoad", load("1e400", "20")),
        Variant("kettlebell lb on the old 2.5 lb step", [
            ("equipment", "\"kettlebell\""),
            ("startLoad", load("22.5", "10"))
        ]),
        Variant("kettlebell kg on the old 1.25 kg step", [
            ("equipment", "\"kettlebell\""),
            ("startLoad", load("25", "11.25"))
        ]),
        Variant("kettlebell kg odd", [("equipment", "\"kettlebell\""), ("startLoad", load("25", "13"))]),
        Variant("dumbbell kg off 1.25", [("equipment", "\"dumbbell\""), ("startLoad", load("15", "3"))]),
        Variant("bodyweight 0 without loadKind", [("equipment", "\"bodyweight\""), ("startLoad", load("0", "0"))]),
        Variant("loadKind bodyweight with a load", [("equipment", "\"bodyweight\""), ("loadKind", "\"bodyweight\"")]),
        Variant("loadKind bodyweight on a barbell", [("loadKind", "\"bodyweight\""), ("startLoad", load("0", "0"))]),
        Variant("zero lb only", "startLoad", load("0", "20")),
        Variant("zero kg only", "startLoad", load("45", "0")),
        Variant("misspelt loadKind", [
            ("equipment", "\"bodyweight\""),
            ("loadkind", "\"bodyweight\""),
            ("startLoad", load("0", "0"))
        ])
    ]

    static let texts: [Variant] = [
        Variant("name empty", "name", "\"\""),
        Variant("name leading space", "name", "\" Alpha Press\""),
        Variant("name trailing space", "name", "\"Alpha Press \""),
        Variant("name trailing newline", "name", "\"Alpha Press\\n\""),
        Variant("shortName empty", "shortName", "\"\""),
        Variant("alias empty", "aliases", "[\"\"]"),
        Variant("alias padded", "aliases", "[\" Alpha\"]"),
        Variant("name repeats another's, other case", "name", "\"alpha PRESS\"", at: 1),
        Variant("alias repeats another's name", "aliases", "[\"ALPHA PRESS\"]", at: 2),
        Variant("alias repeated across entries", [("aliases", "[\"Press A\"]")]).adding("aliases", "[\"press a\"]", 1)
    ]

    static let alternatives: [Variant] = [
        Variant("alternative is self", "alternatives", "[\"\(CatalogDocument.idA)\", \"\(CatalogDocument.idB)\"]"),
        Variant("one alternative", "alternatives", "[\"\(CatalogDocument.idB)\"]"),
        Variant("no alternatives", "alternatives", "[]"),
        Variant("repeated alternative", "alternatives", "[\"\(CatalogDocument.idB)\", \"\(CatalogDocument.idB)\"]"),
        Variant(
            "unknown alternative",
            "alternatives",
            "[\"\(CatalogDocument.idB)\", \"0A2B4C6D-0000-4000-8000-0000000000FF\"]"
        ),
        Variant("alternative with another pattern", "pattern", "\"squat\"", at: 1),
        Variant("secondary repeats primary", "secondaryMuscles", "[\"chest\"]"),
        Variant("secondary repeated", "secondaryMuscles", "[\"triceps\", \"triceps\"]")
    ]
}

extension CatalogLoaderAdversarialTests.Variant {
    func adding(_ key: String, _ value: String?, _ index: Int) -> Self {
        var copy = self
        copy.changes.append(CatalogLoaderAdversarialTests.Change(key: key, value: value, index: index))
        return copy
    }
}

// MARK: - Tests

extension CatalogLoaderAdversarialTests {
    @Test("The unedited three-entry document loads (the control for every attack below).")
    func control_loads() throws {
        let exercises = try CatalogDocument().load()
        #expect(exercises.map(\.name) == ["Alpha Press", "Bravo Press", "Charlie Press"])
        var weighted = CatalogDocument()
        weighted.set("equipment", "\"bodyweight\"")
        weighted.set("startLoad", Self.load("10", "5"))
        #expect(try weighted.load().first?.defaultStartLoad[.kg] == .kilograms(5))
        var bell = CatalogDocument()
        bell.set("equipment", "\"kettlebell\"")
        bell.set("startLoad", Self.load("25", "12"))
        #expect(try bell.load().first?.defaultStartLoad[.lb] == .pounds(25))
    }

    @Test("A missing, null or mistyped field throws.", arguments: shapes)
    func malformedShape_throws(variant: Variant) {
        #expect(throws: CatalogError.self) { try variant.document.load() }
    }

    @Test("An unknown enum value throws.", arguments: enums)
    func unknownEnum_throws(variant: Variant) {
        #expect(throws: CatalogError.self) { try variant.document.load() }
    }

    @Test("A bad or repeated UUID throws.", arguments: ids)
    func badUUID_throws(variant: Variant) {
        #expect(throws: CatalogError.self) { try variant.document.load() }
    }

    @Test("A bad start load or load kind throws.", arguments: loads)
    func badLoad_throws(variant: Variant) {
        #expect(throws: CatalogError.self) { try variant.document.load() }
    }

    @Test("Empty, padded or duplicate text throws.", arguments: texts)
    func badText_throws(variant: Variant) {
        #expect(throws: CatalogError.self) { try variant.document.load() }
    }

    @Test("Bad alternatives or muscles throw.", arguments: alternatives)
    func badAlternatives_throws(variant: Variant) {
        #expect(throws: CatalogError.self) { try variant.document.load() }
    }

    @Test("A malformed document throws.", arguments: [
        "", "not json", "[]", "{}", "{ \"exercises\": null }", "{ \"exercises\": {} }", "{ \"exercises\": [1] }",
        "{ \"exercises\": [{ \"id\": "
    ])
    func malformedDocument_throws(text: String) {
        #expect(throws: CatalogError.self) { try ExerciseCatalog.exercises(from: Data(text.utf8)) }
    }

    @Test("A key written twice in one entry throws rather than one value silently winning.")
    func duplicateKey_throws() {
        let document = CatalogDocument().json.replacingOccurrences(
            of: "\"name\": \"Alpha Press\"", with: "\"name\": \"Alpha Press\", \"name\": \"Bravo Press\""
        )
        #expect(throws: CatalogError.self) { try ExerciseCatalog.exercises(from: Data(document.utf8)) }
    }
}
