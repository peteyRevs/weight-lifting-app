import Foundation

/// A module's hand-written String Catalog, read from the source tree (as `PreviewScan` reads sources), with the
/// rules standards §7 sets for one: English is the source language; every key carries its English text, marked
/// translated (the build leaves out a key with no text and a text still marked `new`); a plain key's text is the
/// key itself; a counted key has the forms `one` and `other`, counts one value, and its `other` form is the key;
/// a key's values are whole numbers and texts (`%lld`, `%@`); no text names the product.
///
/// `CopyAudit` reports these rules' violations with the rest, and `ModuleCopyTests` asks `unresolvedKeys(in:)` of
/// the bundle the build made. What a decoded catalog cannot show (its layout, the order of its keys, a key
/// written twice) is the gate's to check: `scripts/check-string-catalogs.sh` compares the file with what Xcode's
/// own tool would write.
public struct StringCatalog: Sendable {
    /// A key's English localization.
    public enum English: Hashable, Sendable {
        /// One text, and its state (`translated`, `new`, `needs_review`).
        case text(String, state: String?)
        /// A text per plural category (`one`, `other`), each with its state.
        case plural([String: Form])
        /// No English localization, or one this reader does not know (a device variation, a substitution).
        case unreadable
    }

    public struct Form: Hashable, Sendable {
        public let value: String
        public let state: String?
    }

    /// The product's codename, which shipped copy never contains (`docs/product-decisions.md`, Naming).
    public static let productName = "Ledger"

    public let sourceLanguage: String
    public let strings: [String: English]

    public var keys: Set<String> {
        Set(strings.keys)
    }

    /// `LedgerKit/Sources/<module>/Resources/Localizable.xcstrings`.
    public init(module: String) throws {
        let resources = PreviewScan.sourcesDirectory.appending(path: "\(module)/Resources", directoryHint: .isDirectory)
        try self.init(contentsOf: resources.appending(path: "Localizable.xcstrings"))
    }

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    public init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        sourceLanguage = file.sourceLanguage
        strings = file.strings.mapValues { item in
            guard let english = item.localizations?["en"] else {
                return .unreadable
            }
            if let unit = english.stringUnit, english.variations == nil {
                return .text(unit.value, state: unit.state)
            }
            if let plural = english.variations?.plural, english.stringUnit == nil {
                return .plural(plural.mapValues { Form(value: $0.stringUnit.value, state: $0.stringUnit.state) })
            }
            return .unreadable
        }
    }

    /// Every way the catalog breaks the rules above, one sentence each, in key order; empty for a sound catalog.
    public var problems: [String] {
        let header = sourceLanguage == "en" ? [] : ["the source language is \"\(sourceLanguage)\", not \"en\""]
        return header + strings.keys.sorted().flatMap { key in
            problems(of: key).map { "\"\(key)\" \($0)" }
        }
    }

    private func problems(of key: String) -> [String] {
        switch strings[key] {
        case let .text(value, state):
            var found = Self.namesTheProduct([key, value]) ? ["names the product, which shipped copy never does"] : []
            found += Self.valueProblems(in: [key, value])
            if !CopyAuditRules.isSameText(value, key) {
                found.append("has the English text \"\(value)\": a key is its English text")
            }
            if state != "translated" {
                found.append("is not marked translated: a hand-written catalog marks its English text so")
            }
            return found
        case let .plural(forms):
            return pluralProblems(of: key, forms)
        case .unreadable, nil:
            return ["has no English text this check can read (a string unit, or the plural forms)"]
        }
    }

    private func pluralProblems(of key: String, _ forms: [String: Form]) -> [String] {
        let names = Self.namesTheProduct([key] + forms.values.map(\.value))
        var found = names ? ["names the product, which shipped copy never does"] : []
        found += Self.valueProblems(in: [key] + forms.sorted { $0.key < $1.key }.map(\.value.value))
        if Set(forms.keys) != ["one", "other"] {
            found.append("needs exactly the forms \"one\" and \"other\"")
        }
        let counted = Self.specifiers(in: key).count { $0 == "%lld" }
        if counted != 1 {
            found.append("counts \(counted) values: a counted key holds exactly one %lld")
        }
        if let other = forms["other"], !CopyAuditRules.isSameText(other.value, key) {
            found.append("has the \"other\" form \"\(other.value)\": a counted key is its \"other\" form")
        }
        for (category, form) in forms.sorted(by: { $0.key < $1.key }) {
            if Self.specifiers(in: form.value) != Self.specifiers(in: key) {
                found.append("has a \"\(category)\" form whose format specifiers are not the key's")
            }
            if form.state != "translated" {
                found.append("has a \"\(category)\" form that is not marked translated")
            }
        }
        return found
    }

    /// A key's values are whole numbers and texts (standards §7): one problem when a key or a text holds a
    /// specifier other than `%lld` and `%@`.
    private static func valueProblems(in texts: [String]) -> [String] {
        var others: [String] = []
        for specifier in texts.flatMap(otherSpecifiers(in:)) where !others.contains(specifier) {
            others.append(specifier)
        }
        guard !others.isEmpty else {
            return []
        }
        return [
            "holds \(others.joined(separator: ", ")): a key's values are whole numbers (%lld) and texts (%@), "
                + "so format anything else first and pass it as a String"
        ]
    }

    private static func namesTheProduct(_ texts: [String]) -> Bool {
        texts.contains { $0.range(of: productName, options: .caseInsensitive) != nil }
    }

    /// The keys `bundle` cannot resolve: its compiled tables lack them. All of them when the build copied the
    /// catalog instead of compiling it, as SwiftPM's deprecated `native` build system does.
    public func unresolvedKeys(in bundle: Bundle) -> [String] {
        let missing = "\u{1}unresolved"
        return strings.keys.sorted().filter {
            bundle.localizedString(forKey: $0, value: missing, table: nil) == missing
        }
    }

    /// The resource bundle the build made for `module` (`LedgerKit_<module>.bundle`), found beside the test
    /// bundle that links this helper; nil when the module has no resources or the bundle was not embedded. A test
    /// asks for a module's bundle here instead of `Bundle.module`, which inside a test target that has resources
    /// of its own is the test target's bundle.
    public static func resourceBundle(ofModule module: String) -> Bundle? {
        let name = "LedgerKit_\(module).bundle"
        let hosts = [Bundle(for: BundleAnchor.self), .main] + Bundle.allBundles + Bundle.allFrameworks
        return hosts.lazy
            .flatMap { [$0.resourceURL, $0.bundleURL] }
            .compactMap { $0?.appending(path: name) }
            .compactMap { Bundle(url: $0) }
            .first
    }

    /// The format specifiers of a key or a value, in order: `%lld`, `%@`, and so on, a position (`%1$lld`) left
    /// out. An escaped percent sign (`%%`) is text.
    public static func specifiers(in format: String) -> [String] {
        format.matches(of: /%(?:%|(?:\d+\$)?(lld|ld|d|llu|lu|u|lf|f|@))/).compactMap { match in
            match.output.1.map { "%\($0)" }
        }
    }

    /// The format specifiers of a key or a text that are neither `%lld` nor `%@`, in order, as written but for a
    /// position: `%lf`, `%d`, `%.1f`, `%s`. An escaped percent sign (`%%`) is text, and so is one that formats
    /// nothing ("100% done").
    public static func otherSpecifiers(in format: String) -> [String] {
        let specifier = /%(?:%|(?:\d+\$)?([-+#0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|L|z|t|j)?[diouxXeEfFgGaAcCsSpn@]))/
        return format.matches(of: specifier)
            .compactMap { match in match.output.1.map { "%\($0)" } }
            .filter { $0 != "%lld" && $0 != "%@" }
    }
}

/// Lives in the test bundle that links `LedgerTestSupport`, which is where the build puts the resource bundles.
private final class BundleAnchor {}

/// The parts of the `.xcstrings` format (JSON) that the rules read.
private struct File: Decodable {
    struct Item: Decodable {
        let localizations: [String: Localization]?
    }

    struct Localization: Decodable {
        let stringUnit: Unit?
        let variations: Variations?
    }

    struct Variations: Decodable {
        let plural: [String: Variation]?
    }

    struct Variation: Decodable {
        let stringUnit: Unit
    }

    struct Unit: Decodable {
        let state: String?
        let value: String
    }

    let sourceLanguage: String
    let strings: [String: Item]
}
