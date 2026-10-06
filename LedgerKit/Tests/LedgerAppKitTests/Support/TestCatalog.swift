import Foundation
import LedgerTestSupport

/// String Catalogs built in memory, in the `.xcstrings` format, for the tests of `StringCatalog` and `CopyAudit`.
nonisolated enum TestCatalog {
    /// One key's entry.
    enum Entry: Sendable {
        /// One English text.
        case text(String, state: String = "translated")
        /// An English text per plural category.
        case counted([String: String], state: String = "translated")
        /// As Xcode writes a key it extracted from code and nobody translated: no localization at all.
        case empty

        fileprivate var json: [String: Any] {
            switch self {
            case let .text(value, state):
                ["localizations": ["en": ["stringUnit": ["state": state, "value": value]]]]
            case let .counted(forms, state):
                ["localizations": ["en": ["variations": ["plural": forms.mapValues {
                    ["stringUnit": ["state": state, "value": $0]]
                }]]]]
            case .empty:
                [:]
            }
        }
    }

    static func make(sourceLanguage: String = "en", _ strings: [String: Entry]) throws -> StringCatalog {
        let file: [String: Any] = [
            "sourceLanguage": sourceLanguage,
            "strings": strings.mapValues(\.json),
            "version": "1.0"
        ]
        return try StringCatalog(data: JSONSerialization.data(withJSONObject: file))
    }

    /// A sound catalog of plain keys: each key is its own English text.
    static func plain(_ keys: String...) throws -> StringCatalog {
        try make(Dictionary(uniqueKeysWithValues: keys.map { ($0, Entry.text($0)) }))
    }
}
