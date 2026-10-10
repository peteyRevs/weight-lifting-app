import Foundation
import LedgerTestSupport
import Testing

/// F11 S9, criteria 1, 2 and 9, and S10, criteria 1 to 3, 8 and 13, read from the sources: a view draws its
/// model and decides nothing, only the three screens hold a scroll view, the views draw with `LedgerDesign`
/// alone, and the Day editor's stand in `Views/` and tint one thing.
///
/// The check reads spellings in code, as `FeatureProgramSourceTests` does: a rule reached through a name of
/// the module's own is for review to find.
@Suite("FeatureProgram view sources", .tags(.feature))
nonisolated struct ProgramViewsSourceTests {
    /// The three files that put a page in a scroll view.
    static let screens = [
        "Views/ProgramScreen.swift", "Views/ExercisePickerScreen.swift", "Views/DayEditorScreen.swift"
    ]

    /// The Day editor's view files (S10, criterion 3: all in `Views/`).
    static let dayEditorViews = [
        "Views/DayEditorScreen.swift", "Views/DayEditorHeader.swift", "Views/DayEditorPage.swift",
        "Views/ExerciseGroup.swift", "Views/ExerciseRow.swift", "Views/SlotPanel.swift", "Views/SlotDetails.swift",
        "Views/ProgressionChips.swift"
    ]

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
        try #require(views.count >= 21, "the view files were not found: \(views.map(\.key))")
        for path in screens + dayEditorViews + ["Views/ProgramPage.swift", "Views/ExercisePickerPage.swift"] {
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

    @Test("Only the three screens hold a scroll view; no page, and no part of one, holds anything that scrolls")
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

    @Test("The Day editor's views are the eight files of Views/, and its model's folder holds no view")
    func dayEditorViews_standInViews() throws {
        let sources = try CopyAudit.sources(ofModule: "FeatureProgram")
        let inTheModelsFolder = sources.filter { $0.key.hasPrefix("DayEditor/") && $0.value.contains("import SwiftUI") }
        #expect(inTheModelsFolder.keys.sorted() == [])
        let named = sources.keys.filter { path in
            Self.isView(path) && sources[path]
                .map { $0.contains("DayEditorModel") || $0.contains("SlotEditorModel") } == true
        }
        // `WeekSection.swift` holds `ControlPill`, which both screens' controls are drawn with.
        #expect(named.sorted() == (Self.dayEditorViews + ["Views/WeekSection.swift"]).sorted())
    }

    @Test("The Day editor tints one thing, the week's eyebrow, by the model's two flags; no view takes a text apart")
    func dayEditorViews_tintOneThing() throws {
        let accent = try Self.uses(of: ["LedgerColor.accent", "tint:.accent"]) { Self.dayEditorViews.contains($0) }
        #expect(accent.count == 1 && accent.first?.hasPrefix("Views/SlotDetails.swift:") == true, "\(accent)")
        let source = try #require(Self.views().first { $0.path == "Views/SlotDetails.swift" }).source
        let tinted = source.code.filter { $0.contains("LedgerColor.accent") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(tinted == [
            ".foregroundStyle(week.isDeload || week.isHeld ? LedgerColor.accentText : LedgerColor.inkMuted)"
        ])
        let takenApart = try Self.uses(
            of: [".split(", ".components(", ".range(of", ".replacing", ".hasPrefix(", ".hasSuffix("]
        )
        #expect(takenApart.isEmpty, "\(takenApart.prefix(5))")
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
