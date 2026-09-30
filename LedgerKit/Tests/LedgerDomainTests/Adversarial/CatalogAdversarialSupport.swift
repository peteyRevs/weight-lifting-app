import Foundation
@testable import LedgerDomain
import Testing

// Helpers for the F03 adversarial suites. Expected values come from the F03 brief, decisions #21
// and #22, spec §6.2 and the doc comments of `ExerciseCatalog`, never from the catalog tests.

/// The bundled catalog, read once per use: the decoded exercises and the raw file.
enum CatalogUnderTest {
    static func exercises() throws -> [Exercise] {
        try ExerciseCatalog.seed()
    }

    static func data() throws -> Data {
        try ExerciseCatalog.resource("exercises", withExtension: "json")
    }

    static func text() throws -> String {
        try #require(String(bytes: data(), encoding: .utf8))
    }

    /// Each entry as `JSONSerialization` sees it, in file order.
    static func rawEntries() throws -> [[String: Any]] {
        let object = try #require(JSONSerialization.jsonObject(with: data()) as? [String: Any])
        return try #require(object["exercises"] as? [[String: Any]])
    }

    /// The exercise named `name` (exact match).
    static func named(_ name: String, in exercises: [Exercise]) throws -> Exercise {
        try #require(exercises.first { $0.name == name }, "no catalog exercise named \(name)")
    }

    /// Every `"lb": x, "kg": y` pair as written in the file, in order (the exact decimal text).
    static func loadTexts() throws -> [(lb: String, kg: String)] {
        let pattern = /"startLoad":\s*\{\s*"lb":\s*([-0-9.eE+]+)\s*,\s*"kg":\s*([-0-9.eE+]+)\s*\}/
        return try text().matches(of: pattern).map { (String($0.output.1), String($0.output.2)) }
    }
}

/// The file-level guard for finding 1: `JSONDecoder` keeps one value of a key written twice and
/// reports nothing, so the bundled file's text is scanned instead.
enum CatalogScan {
    /// The entries of a file laid out like `exercises.json` (each `{` and `}` indented four spaces,
    /// one key per line), each as the keys it writes, in order.
    static func entryKeys(in text: String) -> [[String]] {
        text.matches(of: /(?s)\n    \{\n(.*?)\n    \}/).map { block in
            String(block.output.1).split(separator: "\n")
                .compactMap { $0.firstMatch(of: /^\s*"(\w+)":/).map { String($0.output.1) } }
        }
    }

    /// For each entry that writes a key more than once, those keys (sorted).
    static func repeatedKeys(in text: String) -> [[String]] {
        entryKeys(in: text)
            .map { keys in
                Dictionary(grouping: keys, by: \.self).filter { $0.value.count > 1 }.keys.sorted()
            }
            .filter { !$0.isEmpty }
    }
}

/// Text keys for duplicate detection that are stricter than the loader's `lowercased()`.
enum CatalogText {
    /// Compatibility-normalised (NFKC), case-, diacritic- and width-folded, with everything that is
    /// not a letter or digit dropped: "Glute-Ham  Raise", "glute ham raise" and "ＧＬＵＴＥ-ＨＡＭ ＲＡＩＳＥ"
    /// share one key.
    static func key(_ text: String) -> String {
        let folded = text.precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        let scalars = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Plain ASCII letters, digits, single spaces, hyphens and apostrophes: no lookalike can hide.
    static func isPlain(_ text: String) -> Bool {
        text.wholeMatch(of: /[A-Za-z0-9](?:[A-Za-z0-9'\-]| (?! ))*/) != nil && !text.hasSuffix(" ")
    }
}

/// The steps as decisions #9 and #22 state them, independent of `Equipment.defaultStep(in:)`.
enum StepOracle {
    static func step(_ equipment: Equipment, _ units: Units) -> Decimal {
        switch (units, equipment) {
        case (.lb, .barbell), (.lb, .kettlebell): dec("5")
        case (.lb, _): dec("2.5")
        case (.kg, .barbell): dec("2.5")
        case (.kg, .kettlebell): dec("2")
        case (.kg, _): dec("1.25")
        }
    }

    /// `value` is a whole number of `step`s (exact `Decimal` arithmetic).
    static func isMultiple(_ value: Decimal, of step: Decimal) -> Bool {
        let quotient = value / step
        return decimalRounded(quotient, scale: 0, .plain) == quotient
    }
}

/// A small, valid catalog document as JSON text, for the loader attacks. Each entry is an ordered
/// list of `(key, raw JSON value)` so one test can drop, replace or add a single field.
struct CatalogDocument {
    typealias Entry = [(key: String, value: String)]

    static let idA = "0A2B4C6D-0000-4000-8000-00000000000A"
    static let idB = "0A2B4C6D-0000-4000-8000-00000000000B"
    static let idC = "0A2B4C6D-0000-4000-8000-00000000000C"

    var entries: [Entry] = [
        Self.entry(id: idA, name: "Alpha Press", short: "ALPHA", alternatives: [idB, idC]),
        Self.entry(id: idB, name: "Bravo Press", short: "BRAVO", alternatives: [idA, idC]),
        Self.entry(id: idC, name: "Charlie Press", short: "CHARLIE", alternatives: [idA, idB])
    ]

    static func entry(id: String, name: String, short: String, alternatives: [String]) -> Entry {
        [
            ("id", "\"\(id)\""),
            ("name", "\"\(name)\""),
            ("shortName", "\"\(short)\""),
            ("equipment", "\"barbell\""),
            ("primaryMuscle", "\"chest\""),
            ("secondaryMuscles", "[\"triceps\"]"),
            ("pattern", "\"horizontalPush\""),
            ("startLoad", "{ \"lb\": 45, \"kg\": 20 }"),
            ("alternatives", "[" + alternatives.map { "\"\($0)\"" }.joined(separator: ", ") + "]"),
            ("aliases", "[]")
        ]
    }

    /// Replaces `key` of entry `index` (appends it when absent); `nil` removes it.
    mutating func set(_ key: String, _ value: String?, at index: Int = 0) {
        let position = entries[index].firstIndex { $0.key == key }
        switch (position, value) {
        case let (.some(position), .some(value)): entries[index][position].value = value
        case let (.some(position), .none): entries[index].remove(at: position)
        case let (.none, .some(value)): entries[index].append((key, value))
        case (.none, .none): break
        }
    }

    var json: String {
        let objects = entries.map { entry in
            "{ " + entry.map { "\"\($0.key)\": \($0.value)" }.joined(separator: ", ") + " }"
        }
        return "{ \"exercises\": [\n" + objects.joined(separator: ",\n") + "\n] }"
    }

    func load() throws -> [Exercise] {
        try ExerciseCatalog.exercises(from: Data(json.utf8))
    }
}
