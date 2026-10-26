import Foundation
import LedgerTestSupport
import Testing

/// F12 S1, N5, read from the sources: the conventions F11's brief set for a feature (its store conventions, and
/// `FeatureProgramSourceTests`): no file reads the device's clock, calendar, locale or time zone; no file starts a
/// task of its own; the store and the root keep no timer and format nothing; the presentation, copy and models
/// never turn a weight into a `Double`; every lookup is in `LibraryCopy*.swift`; the views draw with SwiftUI and
/// `LedgerDesign` alone and decide nothing; only the screen holds a scroll view; and nothing on the Library is
/// orange (N6).
///
/// The check reads code and the code inside a string interpolation; it does not read comments or a literal's own
/// text. It reads spellings, not types: what is reached through a name of the module's own is for review to find.
@Suite("FeatureLibrary sources", .tags(.feature))
nonisolated struct FeatureLibrarySourceTests {
    /// The spellings that read the device's own clock, calendar, locale or time zone, without spaces.
    static let ambient = [
        "Date()", "Date.init()", "Date.now", "Date(timeIntervalSinceNow", ":.now", "=.now", "(.now",
        "Calendar.current", "Calendar.autoupdatingCurrent", "Calendar(identifier:", "Locale.current",
        "Locale.autoupdatingCurrent", "TimeZone.current", "TimeZone.autoupdatingCurrent", "locale:.current",
        "calendar:.current", "timeZone:.current", "in:.current", ".autoupdatingCurrent", ".dateTime", ".formatted()",
        "DateFormatter(", "NumberFormatter(", "DateComponentsFormatter("
    ]

    /// Work no view's task owns, a clock that ticks by itself, and a format of the store's own.
    static let unstructured = ["Task.detached", "DispatchQueue", "Timer", "TimelineView", ".formatted("]

    static let inexact = ["Double", "Float", "CGFloat", "TimeInterval", ".doubleValue", ".floatValue"]

    /// The spellings of a lookup (standards §7).
    static let lookups = ["localized:", "NSLocalizedString", "LocalizedStringKey", "LocalizedStringResource"]

    /// What a view must not reach for: the copy and the presentation (a text or a decision of its own), a
    /// format, a filter or an order of its own, the clock, the calendar and the locale.
    static let decisions = [
        "LibraryCopy", "LibraryPresentation", "ExerciseSearch.", ".formatted(", "String(format", ".filter(",
        ".sorted(", ".sort(", "Locale", "Calendar", "Date", "@Dependency"
    ]

    static let storeFiles = [
        "LibraryStore.swift", "LibraryStore+Sources.swift", "LibraryRoot.swift", "ExerciseHistoryStore.swift",
        "ExerciseHistoryRoot.swift"
    ]

    static func sources() throws -> [String: String] {
        let sources = try CopyAudit.sources(ofModule: "FeatureLibrary")
        try #require(sources.count >= 10, "FeatureLibrary's sources were not found: \(sources.keys.sorted())")
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

    @Test("The presentation, the copy and the models never name Double: weights stay exact")
    func presentationCopyAndModels_neverNameDouble() throws {
        let printsWhatIsDrawn = { (path: String) in
            path.contains("Presentation") || path.contains("Copy") || path.contains("Model") || path.contains("Input")
        }
        #expect(try Self.uses(of: Self.inexact, inFiles: printsWhatIsDrawn) == [])
    }

    @Test("Every lookup is in LibraryCopy*.swift")
    func lookups_standInTheCopyFiles() throws {
        let outside = try Self.uses(of: Self.lookups) { !$0.hasPrefix("LibraryCopy") }
        #expect(outside == [])
        #expect(try Self.uses(of: ["localized:"]) { $0.hasPrefix("LibraryCopy") }.count > 30)
    }

    @Test("No view reaches for the copy, the presentation, a format, a filter, an order, a clock or a locale")
    func views_decideNothing() throws {
        let found = try Self.uses(of: Self.decisions, inFiles: Self.isView)
        #expect(found.isEmpty, "\(found.prefix(5))")
    }

    /// F12 S2: the chart's descriptor also imports Accessibility, in that one file (ruling R2); each screen holds
    /// its scroll view.
    @Test("Every view imports SwiftUI and LedgerDesign and nothing else; only the screens hold a scroll view")
    func views_importOnlySwiftUIAndTheDesignSystem_andOneScrollView() throws {
        let views = try Self.sources().filter { Self.isView($0.key) }
        #expect(views.count >= 3)
        for (path, text) in views {
            let imports = SwiftSource(text).code.map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("import ") }
            let allowed: Set = path == "Views/E1RMChartDescriptor.swift"
                ? ["import Accessibility", "import SwiftUI"] : ["import SwiftUI", "import LedgerDesign"]
            #expect(Set(imports).isSubset(of: allowed), "\(path): \(imports)")
        }
        let scrolling = try Self.uses(of: ["ScrollView", "TextEditor", "axis:.vertical"], inFiles: Self.isView)
        #expect(scrolling.map { $0.components(separatedBy: ":").first ?? "" } == [
            "Views/ExerciseHistoryScreen.swift", "Views/LibraryScreen.swift"
        ])
    }

    /// F12 S2: an exercise's history wears it on the estimate, the change and the last bar (Pete's question 3, A):
    /// the chart spells it, and the stats pass `isValueAccented`. `ExerciseHistoryOrangeAuditTests` count it.
    @Test("N6. Nothing on the Library wears the accent; of the history, only the chart spells it")
    func views_wearNoAccent() throws {
        let spelled = try Self.uses(of: ["LedgerColor.accent", ".accent", "tint:"])
        #expect(Set(spelled.map { $0.components(separatedBy: ":").first ?? "" }) == ["Views/E1RMChart.swift"])
    }
}
