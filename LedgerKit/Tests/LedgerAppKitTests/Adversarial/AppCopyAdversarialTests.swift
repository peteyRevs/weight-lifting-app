import Foundation
@testable import LedgerAppKit
import LedgerTestSupport
import Testing

/// F09 S1 adversarial round 1, criterion 4: every string the shell shows comes from `LedgerAppKit`'s catalog, the
/// two strings of the can't-open-your-data screen word for word as criterion 4 gives them (`main`'s, a526874, but
/// for the second sentence, which no longer names the product), and the bundle the build made resolves every key,
/// on the Mac host and on the simulator.
@Suite("Adversarial F09 S1 · the shell's copy")
nonisolated struct AppCopyAdversarialTests {
    /// `git show a526874:LedgerKit/Sources/LedgerAppKit/AppRoot.swift`, `DatabaseUnavailableView`; the body's second
    /// sentence as criterion 4 was revised after round 1 ("The app tries again", where `main` names the product).
    static let databaseTitle = "Can't open your data right now"
    static let databaseBody = "Your workouts are still on this iPhone. The app tries again when you come back to it."
    /// The prototype's tab labels (`design/prototype/LedgerTabs.dc.html`), the pushed placeholder, and the two above.
    /// Sanctioned edit (F12 S1): "Exercise history", the pushed history's placeholder until F12 S2 draws it.
    static let shellStrings = [
        "Today", "Program", "Library", "History", "Settings", databaseTitle, databaseBody, "Exercise history"
    ]

    @Test("Each tab's title is the prototype's label", arguments: zip(AppTab.allCases, shellStrings.prefix(4)))
    func tabTitle_isThePrototypesLabel(tab: AppTab, label: String) {
        #expect(AppCopy.title(of: tab) == label)
    }

    @Test("The pushed Settings placeholder is titled Settings")
    func settingsTitle_isSettings() {
        #expect(AppCopy.settingsTitle == "Settings")
    }

    @Test("The can't-open-your-data screen says, word for word, what criterion 4 says (product decision #29)")
    func databaseUnavailable_isWordForWordTheCriterions() {
        #expect(AppCopy.databaseUnavailableTitle == Self.databaseTitle)
        #expect(AppCopy.databaseUnavailableBody == Self.databaseBody)
    }

    @Test("The catalog holds the shell's seven strings and nothing else, each sound")
    func catalog_holdsTheShellsStringsOnly() throws {
        let catalog = try StringCatalog(module: "LedgerAppKit")
        #expect(catalog.keys == Set(Self.shellStrings))
        #expect(catalog.problems.isEmpty, "\(catalog.problems)")
    }

    @Test("The bundle the build made holds each string in a compiled table", arguments: shellStrings)
    func builtBundle_holdsEachString(key: String) throws {
        let bundle = try #require(StringCatalog.resourceBundle(ofModule: "LedgerAppKit"))
        let missing = "\u{2}adversarial-missing"
        #expect(bundle.localizedString(forKey: key, value: missing, table: nil) == key)
        #expect(bundle.localizedString(forKey: key + "?", value: missing, table: nil) == missing, "control: a miss")
    }

    @Test("The helper agrees with the bundle: no key unresolved, English among its localizations")
    func builtBundle_resolvesEveryKey() throws {
        let bundle = try #require(StringCatalog.resourceBundle(ofModule: "LedgerAppKit"))
        #expect(try StringCatalog(module: "LedgerAppKit").unresolvedKeys(in: bundle).isEmpty)
        #expect(bundle.localizations.contains("en"), "\(bundle.localizations)")
    }

    @Test("Shipped copy never names the product (product decisions, Naming; standards §7, Not copy)")
    func catalog_neverNamesTheProduct() throws {
        let catalog = try StringCatalog(module: "LedgerAppKit")
        let naming = catalog.keys.filter { $0.localizedCaseInsensitiveContains("Ledger") }
        #expect(naming.isEmpty, "the product's codename is in shipped copy: \(naming)")
    }

    @Test("No view of the module draws a literal: a scan of its sources that does not use the audit")
    func sources_drawNoLiteral() throws {
        let views = "Text|Label|Button|Tab|Section|Toggle|Picker|TextField|Link|Menu|ProgressView|EmptyState"
        let modifiers = "navigationTitle|accessibilityLabel|accessibilityHint|accessibilityValue|alert|help"
        let drawn = try Regex("(\\b(\(views))|\\.(\(modifiers)))\\(\\s*(verbatim:\\s*)?#*\"[^\"]*\\p{L}")
        var hits: [String] = []
        for file in try Self.sources() where !file.lastPathComponent.hasSuffix("+Previews.swift") {
            let lines = try String(contentsOf: file, encoding: .utf8).split(whereSeparator: \.isNewline)
            for line in lines where !line.drop(while: \.isWhitespace).hasPrefix("//") {
                if line.contains(drawn) {
                    hits.append("\(file.lastPathComponent): \(line)")
                }
            }
        }
        #expect(hits.isEmpty, "\(hits)")
    }

    @Test("Only the copy file looks strings up, and it looks up exactly the catalog's keys")
    func onlyTheCopyFile_looksStringsUp() throws {
        let lookup = /String\(\s*localized: "((?:[^"\\]|\\.)*)",\s*bundle: \.module/
        var keys: [String] = []
        for file in try Self.sources() where !file.lastPathComponent.hasSuffix("+Previews.swift") {
            let text = try String(contentsOf: file, encoding: .utf8)
            let found = text.matches(of: lookup).map { String($0.output.1) }
            if file.lastPathComponent == "AppCopy.swift" {
                keys += found
            } else {
                #expect(found.isEmpty, "\(file.lastPathComponent) looks up \(found)")
                #expect(!text.contains("localized:"), "\(file.lastPathComponent)")
            }
        }
        #expect(keys.map { $0.replacingOccurrences(of: "\\'", with: "'") }.sorted() == Self.shellStrings.sorted())
    }

    @Test("The audit of the module, with no file exempt, names only files whose literals no lifter sees")
    func moduleAudit_withoutExemptions_namesOnlyPlumbing() throws {
        let findings = try CopyAudit(module: "LedgerAppKit").findings
        let shell = ["AppTabs.swift", "MainRoot.swift", "PlaceholderScreen.swift", "Routes.swift", "AppRoot.swift"]
        let inTheShell = findings.filter { finding in shell.contains { finding.hasPrefix($0) } }
        #expect(inTheShell.isEmpty, "\(inTheShell)")
        #expect(
            !findings.contains { $0.hasPrefix("AppCopy.swift") || $0.hasPrefix("Localizable.xcstrings") },
            "\(findings)"
        )
    }

    static func sources() throws -> [URL] {
        let module = PreviewScan.sourcesDirectory.appending(path: "LedgerAppKit", directoryHint: .isDirectory)
        let files = FileManager.default.enumerator(at: module, includingPropertiesForKeys: nil)?.allObjects as? [URL]
        return try #require(files).filter { $0.pathExtension == "swift" }
    }
}
