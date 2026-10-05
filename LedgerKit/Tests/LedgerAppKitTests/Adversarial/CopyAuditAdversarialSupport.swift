import Foundation
import LedgerTestSupport
import Testing

/// One input of the adversarial audit suites (F09 S1 round 1): what it tries, and the Swift source or catalog text.
nonisolated struct AdversarialInput: Sendable, CustomTestStringConvertible {
    let name: String
    let text: String

    init(_ name: String, _ text: String) {
        self.name = name
        self.text = text
    }

    var testDescription: String {
        name
    }
}

/// A module in memory for `CopyAudit(sources:catalog:exempting:)`: a copy file, a screen and a catalog, each as
/// standards §7 wants it unless the test says otherwise.
nonisolated enum AdversarialModule {
    static let copyPath = "FixtureCopy.swift"
    static let screenPath = "Views/Screen.swift"

    /// A copy file with these members.
    static func copyFile(_ members: String) -> String {
        let body = members.split(separator: "\n", omittingEmptySubsequences: false).map { "    \($0)" }
        return "import Foundation\n\nnonisolated enum FixtureCopy {\n\(body.joined(separator: "\n"))\n}\n"
    }

    /// The copy file every screen test uses: one lookup, of "Start workout".
    static let copy = copyFile(
        """
        static var start: String {
            String(localized: "Start workout", bundle: .module)
        }
        """
    )

    /// A screen file with these declarations.
    static func screen(_ declarations: String) -> String {
        "import SwiftUI\n\n\(declarations)\n"
    }

    /// The findings for a module of `copy` and one screen file with `declarations`.
    static func findings(
        screen declarations: String,
        at path: String = screenPath,
        exempting exemptions: [String: String] = [:]
    ) throws -> [String] {
        let catalog = try AdversarialCatalog.catalog([AdversarialCatalog.plain("Start workout")])
        let sources = [copyPath: copy, path: screen(declarations)]
        return CopyAudit(sources: sources, catalog: catalog, exempting: exemptions).findings
    }

    /// The findings for a module whose one file is a copy file with `members`, over a catalog of `entries`.
    static func findings(copy members: String, catalog entries: [String]) throws -> [String] {
        let catalog = try AdversarialCatalog.catalog(entries)
        return CopyAudit(sources: [copyPath: copyFile(members)], catalog: catalog).findings
    }

    /// The line, counted from 1, of the first line of `screen(declarations)` that holds `needle`.
    static func line(of needle: String, inScreen declarations: String) -> Int? {
        let lines = screen(declarations).split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        return lines.firstIndex { $0.contains(needle) }.map { $0 + 1 }
    }
}

/// A String Catalog written as text, as standards §7 says one is: the `.xcstrings` JSON.
nonisolated enum AdversarialCatalog {
    /// `text` as a JSON string.
    static func quoted(_ text: String) -> String {
        var json = ""
        for character in text {
            switch character {
            case "\"": json += "\\\""
            case "\\": json += "\\\\"
            case "\n": json += "\\n"
            case "\t": json += "\\t"
            default: json.append(character)
            }
        }
        return "\"\(json)\""
    }

    static func unit(_ value: String, state: String? = "translated") -> String {
        let stateField = state.map { "\"state\" : \(quoted($0)), " } ?? ""
        return "{ \"stringUnit\" : { \(stateField)\"value\" : \(quoted(value)) } }"
    }

    /// A plain entry: its English text is the key unless `value` says otherwise.
    static func plain(_ key: String, value: String? = nil, state: String? = "translated") -> String {
        "\(quoted(key)) : { \"localizations\" : { \"en\" : \(unit(value ?? key, state: state)) } }"
    }

    /// A counted entry with these plural forms, in this order.
    static func plural(
        _ key: String,
        _ forms: KeyValuePairs<String, String>,
        state: String? = "translated"
    ) -> String {
        let variations = forms.map { "\(quoted($0.key)) : \(unit($0.value, state: state))" }.joined(separator: ", ")
        let english = "{ \"variations\" : { \"plural\" : { \(variations) } } }"
        return "\(quoted(key)) : { \"localizations\" : { \"en\" : \(english) } }"
    }

    static func json(_ entries: [String], sourceLanguage: String = "en") -> String {
        let strings = entries.joined(separator: ", ")
        return "{ \"sourceLanguage\" : \"\(sourceLanguage)\", \"strings\" : { \(strings) }, \"version\" : \"1.0\" }"
    }

    static func catalog(_ entries: [String], sourceLanguage: String = "en") throws -> StringCatalog {
        try StringCatalog(data: Data(json(entries, sourceLanguage: sourceLanguage).utf8))
    }

    /// The problems the reader finds in a catalog of `entries`.
    static func problems(_ entries: [String], sourceLanguage: String = "en") throws -> [String] {
        try catalog(entries, sourceLanguage: sourceLanguage).problems
    }
}

/// SplitMix64, for the seeded cases of the F09 S1 adversarial suites; a failing seed is in the test's message.
nonisolated struct AdversarialRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(truncatingIfNeeded: seed)
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
