import Foundation
import LedgerTestSupport
import Testing

/// F11 S9, criteria 1, 2 and 9, read from the sources: a view draws its model and decides nothing, only the
/// two screens hold a scroll view, and the views draw with `LedgerDesign` alone.
///
/// The check reads spellings in code, as `FeatureProgramSourceTests` does: a rule reached through a name of
/// the module's own is for review to find.
@Suite("FeatureProgram view sources", .tags(.feature))
nonisolated struct ProgramViewsSourceTests {
    /// The two files that put a page in a scroll view.
    static let screens = ["Views/ProgramScreen.swift", "Views/ExercisePickerScreen.swift"]

    /// What a view must not reach for: the copy and the presentations (a text or a decision of its own), a
    /// format, a filter or an order of its own, and the clock, the calendar and the locale.
    static let decisions = [
        "ProgramCopy", "ProgramPresentation", "ExercisePickerPresentation", "DayEditorPresentation",
        "ExerciseSearch.", "ProgramEditing", "DayEditing", ".formatted(", "String(format", ".filter(", ".sorted(",
        ".sort(", "Locale", "Calendar", "Date", "@Dependency"
    ]

    /// What scrolls, or is a scroll view to UIKit: a scroll view, and a text field of several lines. (`List` and
    /// `Form` are not spelled here: `HairlineList` reads like the first.)
    static let scrolling = ["ScrollView", "TextEditor", "axis:.vertical"]

    static func isView(_ path: String) -> Bool {
        path.hasPrefix("Views/") && !path.hasSuffix("+Previews.swift")
    }

    /// The view files with their sources, by path.
    static func views() throws -> [(path: String, source: SwiftSource)] {
        let sources = try CopyAudit.sources(ofModule: "FeatureProgram")
        let views = sources.filter { isView($0.key) }.sorted { $0.key < $1.key }
        try #require(views.count >= 13, "the view files were not found: \(views.map(\.key))")
        for path in screens + ["Views/ProgramPage.swift", "Views/ExercisePickerPage.swift"] {
            try #require(sources[path] != nil, "\(path) is not among the module's files")
        }
        return views.map { ($0.key, SwiftSource($0.value)) }
    }

    /// Each use of one of `spellings` in the view files `isRead` accepts, as "file:line: spelling".
    static func uses(of spellings: [String], where isRead: (String) -> Bool = { _ in true }) throws -> [String] {
        try views().filter { isRead($0.path) }.flatMap { path, source in
            spellings.flatMap { spelling in
                FeatureProgramSourceTests.lines(of: spelling, in: source).map { "\(path):\($0): \(spelling)" }
            }
        }
    }

    @Test("No view reaches for the copy, a presentation, a format, a filter, an order, a clock or a locale")
    func views_decideNothing() throws {
        let found = try Self.uses(of: Self.decisions)
        #expect(found.isEmpty, "\(found.prefix(5))")
    }

    @Test("Only the two screens hold a scroll view; no page, and no part of one, holds anything that scrolls")
    func onlyTheScreens_holdAScrollView() throws {
        let found = try Self.uses(of: Self.scrolling) { !Self.screens.contains($0) }
        #expect(found.isEmpty, "\(found.prefix(5))")
        for screen in Self.screens {
            let scrollViews = try Self.uses(of: ["ScrollView"]) { $0 == screen }
            #expect(scrollViews.count == 1, "\(screen) holds \(scrollViews.count) scroll views")
        }
    }

    @Test("Every view imports SwiftUI and LedgerDesign and nothing else")
    func views_importOnlySwiftUIAndTheDesignSystem() throws {
        for (path, source) in try Self.views() {
            let imports = source.code.map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("import ") }
            #expect(Set(imports).isSubset(of: ["import SwiftUI", "import LedgerDesign"]), "\(path): \(imports)")
        }
    }

    @Test("The check finds what is there")
    func check_findsASpelling() {
        let source = SwiftSource("""
        /// A ScrollView is only a word here.
        ScrollView { Page() }
        let line = ProgramCopy.rest
        let shown = rows.filter (\\.isPicked)
        TextField(placeholder, text: $text, axis: .vertical)
        """)
        #expect(FeatureProgramSourceTests.lines(of: "ScrollView", in: source) == [2])
        #expect(FeatureProgramSourceTests.lines(of: "ProgramCopy", in: source) == [3])
        #expect(FeatureProgramSourceTests.lines(of: ".filter(", in: source) == [4])
        #expect(FeatureProgramSourceTests.lines(of: "axis:.vertical", in: source) == [5])
    }
}
