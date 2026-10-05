import LedgerTestSupport
import Testing

/// `CopyAudit` (LedgerTestSupport): the check every module with copy runs (standards §7), on sources and catalogs
/// built in memory, each rule broken once. The module in these tests is a copy file, a view and a catalog.
@Suite("CopyAudit")
struct CopyAuditTests {
    static let copyFile = #"""
    import Foundation

    nonisolated enum DemoCopy {
        static var title: String { String(localized: "Today", bundle: .module) }

        static func week(_ week: Int, of total: Int) -> String {
            String(localized: "Week \(week) of \(total)", bundle: .module, comment: "The block's progress")
        }

        static func exercises(_ count: Int, locale: Locale) -> String {
            String(localized: "\(count) exercises", bundle: .module, locale: locale)
        }

        static func next(
            day: String,
            tag: String
        ) -> String {
            String(
                localized: "Next: \(day) · \(tag), 100% sure",
                bundle: .module
            )
        }
    }
    """#

    static let view = """
    import SwiftUI

    struct DemoScreen: View {
        var body: some View {
            Label(DemoCopy.title, systemImage: "chart.bar")
                .accessibilityIdentifier("demo.title")
        }
    }
    """

    static func catalog() throws -> StringCatalog {
        try TestCatalog.make([
            "Today": .text("Today"),
            "Week %lld of %lld": .text("Week %lld of %lld"),
            "%lld exercises": .counted(["one": "%lld exercise", "other": "%lld exercises"]),
            "Next: %@ · %@, 100%% sure": .text("Next: %@ · %@, 100%% sure")
        ])
    }

    static func findings(
        copy: String = copyFile,
        view: String = view,
        extra: [String: String] = [:],
        catalog: StringCatalog? = nil,
        exempting exemptions: [String: String] = [:]
    ) throws -> [String] {
        let sources = ["DemoCopy.swift": copy, "Views/DemoScreen.swift": view].merging(extra) { $1 }
        return try CopyAudit(sources: sources, catalog: catalog ?? Self.catalog(), exempting: exemptions).findings
    }

    @Test("A module whose catalog and copy file agree, with identifiers and symbols in its view, has no findings")
    func soundModule_hasNoFindings() throws {
        #expect(try Self.findings() == [])
    }

    @Test("A lookup's key is what the compiler derives: %lld for an Int, %@ for a String, a percent sign doubled")
    func lookups_areKeyedAsTheCompilerKeysThem() {
        let lookups = CopyAudit.copyFile(SwiftSource(Self.copyFile)).lookups
        #expect(lookups.map(\.key) == ["Today", "Week %lld of %lld", "%lld exercises", "Next: %@ · %@, 100%% sure"])
        #expect(lookups.map(\.line) == [4, 7, 11, 19])
    }

    // MARK: The catalog and the copy file, in both directions

    @Test("A key the copy file looks up that the catalog lacks is a finding")
    func keyMissingFromTheCatalog_isAFinding() throws {
        let copy = Self.copyFile.replacing("\"Today\"", with: "\"Todya\"")
        #expect(try Self.findings(copy: copy) == [
            "DemoCopy.swift:4: looks up \"Todya\", which the catalog does not hold",
            "Localizable.xcstrings: \"Today\" is not looked up by a copy file"
        ])
    }

    @Test("A catalog key no copy file looks up is a finding")
    func unusedCatalogKey_isAFinding() throws {
        let catalog = try TestCatalog.make([
            "Today": .text("Today"),
            "Week %lld of %lld": .text("Week %lld of %lld"),
            "%lld exercises": .counted(["one": "%lld exercise", "other": "%lld exercises"]),
            "Next: %@ · %@, 100%% sure": .text("Next: %@ · %@, 100%% sure"),
            "Start workout": .text("Start workout")
        ])
        #expect(try Self.findings(catalog: catalog) == [
            "Localizable.xcstrings: \"Start workout\" is not looked up by a copy file"
        ])
    }

    @Test("A key written with another specifier than the compiler's is both missing and unused")
    func keyWithAnotherSpecifier_isAFinding() throws {
        let catalog = try TestCatalog.make([
            "Today": .text("Today"),
            "Week %d of %d": .text("Week %d of %d"),
            "%lld exercises": .counted(["one": "%lld exercise", "other": "%lld exercises"]),
            "Next: %@ · %@, 100%% sure": .text("Next: %@ · %@, 100%% sure")
        ])
        #expect(try Self.findings(catalog: catalog) == [
            "DemoCopy.swift:7: looks up \"Week %lld of %lld\", which the catalog does not hold",
            "Localizable.xcstrings: \"Week %d of %d\" is not looked up by a copy file"
        ])
    }

    @Test("The catalog's own problems are findings")
    func catalogProblems_areFindings() throws {
        let catalog = try TestCatalog.make([
            "Today": .text("Today", state: "new"),
            "Week %lld of %lld": .text("Week %lld of %lld"),
            "%lld exercises": .counted(["other": "%lld exercises"]),
            "Next: %@ · %@, 100%% sure": .text("Next: %@ · %@, 100%% sure")
        ])
        #expect(try Self.findings(catalog: catalog) == [
            "Localizable.xcstrings: \"%lld exercises\" needs exactly the forms \"one\" and \"other\"",
            "Localizable.xcstrings: \"Today\" is not marked translated, so the build leaves it out"
        ])
    }
}
