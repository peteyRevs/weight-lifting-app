import Foundation
import LedgerTestSupport
import Testing

/// F14 S1, N9 and N6, read from the sources: the conventions F12 checks for the Library. No file reads the device's
/// clock, calendar, locale or time zone; no file starts a task of its own; the store and the root keep no timer and
/// format nothing; every lookup is in `SettingsCopy*.swift`; the views draw with SwiftUI and `LedgerDesign` alone and
/// decide nothing; only the screen holds a scroll view; nothing on Settings is orange (C28); and no source writes the
/// product's name or a version (N6): the About line reads them from the app's bundle.
///
/// The check reads code and the code inside a string interpolation; it does not read comments or a literal's own
/// text, except where it reads every literal for N6.
@Suite("FeatureSettings sources", .tags(.feature))
nonisolated struct FeatureSettingsSourceTests {
    /// The spellings that read the device's own clock, calendar, locale or time zone, without spaces.
    static let ambient = [
        "Date()", "Date.init()", "Date.now", "Date(timeIntervalSinceNow", ":.now", "=.now", "(.now",
        "Calendar.current", "Calendar.autoupdatingCurrent", "Calendar(identifier:", "Locale.current",
        "Locale.autoupdatingCurrent", "TimeZone.current", "TimeZone.autoupdatingCurrent", "locale:.current",
        "calendar:.current", "timeZone:.current", "in:.current", ".autoupdatingCurrent", ".dateTime", ".formatted()",
        "DateFormatter(", "NumberFormatter(", "DateComponentsFormatter("
    ]

    /// Work no view's task owns, a clock that ticks by itself, and a format of the store's own.
    static let unstructured = ["Task.detached", "DispatchQueue", "Timer", "TimelineView", ".formatted(", ".format("]

    /// The spellings of a lookup (standards §7).
    static let lookups = ["localized:", "NSLocalizedString", "LocalizedStringKey", "LocalizedStringResource"]

    /// What a view must not reach for: the copy and the presentation (a text or a decision of its own), a format,
    /// a filter or an order of its own, the clock, the calendar and the locale.
    static let decisions = [
        "SettingsCopy", "SettingsPresentation", ".formatted(", "String(format", ".filter(", ".sorted(", ".sort(",
        "Locale", "Calendar", "Date", "@Dependency"
    ]

    static let storeFiles = ["SettingsStore.swift", "SettingsStore+Sources.swift", "SettingsRoot.swift"]

    static func sources() throws -> [String: String] {
        let sources = try CopyAudit.sources(ofModule: "FeatureSettings")
        try #require(sources.count >= 10, "FeatureSettings' sources were not found: \(sources.keys.sorted())")
        return sources
    }

    /// Each use of one of `spellings` in the files `isRead` accepts, as "file:line: spelling".
    static func uses(of spellings: [String], inFiles isRead: (String) -> Bool = { _ in true }) throws -> [String] {
        try sources().sorted { $0.key < $1.key }.filter { isRead($0.key) }.flatMap { path, text in
            let source = SwiftSource(text)
            return spellings.flatMap { spelling in
                lines(of: spelling, in: source).map { "\(path):\($0): \(spelling)" }
            }
        }
    }

    /// The lines of `source` on which `spelling` stands in code: the file's own, or a string interpolation's.
    static func lines(of spelling: String, in source: SwiftSource) -> [Int] {
        let interpolated = source.literals.flatMap { literal in
            literal.interpolations.filter { $0.filter { !$0.isWhitespace }.contains(spelling) }
                .map { _ in literal.line }
        }
        return Set(source.lines(ofCode: spelling) + interpolated).sorted()
    }

    static func isView(_ path: String) -> Bool {
        path.hasPrefix("Views/") && !path.hasSuffix("+Previews.swift")
    }

    @Test("No file reads the clock, the current calendar, the current locale or the current time zone")
    func sources_neverReadTheClockOrTheCurrentCalendar() throws {
        #expect(try Self.uses(of: Self.ambient) == [])
    }

    @Test("No file starts a task of its own; the store and the root keep no timer and format nothing")
    func sources_startNoWorkOfTheirOwn() throws {
        #expect(try Self.uses(of: Self.unstructured, inFiles: Self.storeFiles.contains) == [])
        let sources = try Self.sources()
        for name in Self.storeFiles {
            #expect(sources[name] != nil, "\(name) is not among the files read")
        }
        let tasks = sources.sorted { $0.key < $1.key }.flatMap { path, text in
            SwiftSource(text).code.enumerated()
                .filter { $0.element.firstMatch(of: /(^|[^A-Za-z0-9_.])Task\s*(\{|\(|<|\.init\b|\.detached\b)/) != nil }
                .map { "\(path):\($0.offset + 1)" }
        }
        #expect(tasks == [])
    }

    @Test("N9. Every lookup is in SettingsCopy*.swift")
    func lookups_standInTheCopyFiles() throws {
        let outside = try Self.uses(of: Self.lookups) { !$0.hasPrefix("SettingsCopy") }
        #expect(outside == [])
        #expect(try Self.uses(of: ["localized:"]) { $0.hasPrefix("SettingsCopy") }.count == 27)
    }

    @Test("N9. No view reaches for the copy, the presentation, a format, a filter, an order, a clock or a locale")
    func views_decideNothing() throws {
        let found = try Self.uses(of: Self.decisions, inFiles: Self.isView)
        #expect(found.isEmpty, "\(found.prefix(5))")
    }

    @Test("N9. Every view imports SwiftUI and LedgerDesign and nothing else; only the screen holds a scroll view")
    func views_importOnlySwiftUIAndTheDesignSystem_andOneScrollView() throws {
        let views = try Self.sources().filter { Self.isView($0.key) }
        #expect(views.count >= 4)
        for (path, text) in views {
            let imports = SwiftSource(text).code.map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("import ") }
            #expect(Set(imports).isSubset(of: ["import SwiftUI", "import LedgerDesign"]), "\(path): \(imports)")
        }
        let scrolling = try Self.uses(of: ["ScrollView", "TextEditor", "axis:.vertical"], inFiles: Self.isView)
        #expect(scrolling.map { $0.components(separatedBy: ":").first ?? "" } == ["Views/SettingsScreen.swift"])
    }

    @Test("N9, C28. Nothing on Settings wears the accent")
    func views_wearNoAccent() throws {
        #expect(try Self.uses(of: ["LedgerColor.accent", ".accent", "tint:", "Eyebrow.Tint"]) == [])
    }

    /// N6: the product's name and version come from the bundle. The previews' stand-in About values are set aside:
    /// they are Debug-only data, and never the app's.
    @Test("N6. No source writes the product's name or a version number")
    func sources_writeNoProductNameOrVersion() throws {
        let literals = try Self.sources().filter { !$0.key.hasSuffix("+Previews.swift") }.flatMap { path, text in
            SwiftSource(text).literals.map { (path, $0.text) }
        }
        #expect(literals.count > 20, "the literals were not read")
        let named = literals.filter { $0.1.localizedCaseInsensitiveContains("ledger") }
        #expect(named.isEmpty, "\(named.prefix(3))")
        let versions = literals.filter { $0.1.firstMatch(of: /\d+\.\d+/) != nil }
        #expect(versions.isEmpty, "\(versions.prefix(3))")
    }
}
