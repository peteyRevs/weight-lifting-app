import Foundation
import LedgerTestSupport
import Testing

/// F11 S5 criteria 9, 10 and 16, read from the sources: the module takes its calendar and locale from the
/// input and from nowhere else; nothing in it but the copy, the models and the route holds a clamp of its own
/// (the brief's Definition of Done: no clamping or coupling logic outside `ProgramEditing`); and its
/// presentations, copy and models never turn a weight into a `Double`.
///
/// The check reads every Swift file of the module, the views and the stores when they come. It reads code,
/// and the code inside a string interpolation; it does not read comments or a literal's own text. It reads
/// spellings, not types: a clock or a clamp reached through a name of the module's own is for review to find.
@Suite("FeatureProgram sources", .tags(.feature))
nonisolated struct FeatureProgramSourceTests {
    /// The spellings that read the device's own clock, calendar, locale or time zone, written without spaces: a
    /// moment made here, a current or self-updating value, a calendar built in place (it takes the device's
    /// zone), a format style or a formatter with the device's defaults.
    static let ambient = [
        "Date()", "Date.init()", "Date.now", "Date(timeIntervalSinceNow", ":.now", "=.now", "(.now",
        "Calendar.current", "Calendar.autoupdatingCurrent", "Calendar(identifier:", "Locale.current",
        "Locale.autoupdatingCurrent", "TimeZone.current", "TimeZone.autoupdatingCurrent", "locale:.current",
        "calendar:.current", "timeZone:.current", "in:.current", ".autoupdatingCurrent", ".dateTime", ".formatted()",
        "DateFormatter(", "NumberFormatter(", "DateComponentsFormatter("
    ]

    /// The spellings of a clamp or of the reps coupling: a least or a greatest of two values, and a write to
    /// the top of a rep range.
    static let clamps = ["min(", "max(", "repsHi=", "repsHi+=", "repsHi-="]

    /// The spellings that name a binary floating-point number, or turn a decimal into one.
    static let inexact = ["Double", "Float", "CGFloat", "TimeInterval", ".doubleValue", ".floatValue"]

    /// The spellings of work no view's task owns, of a clock that ticks by itself, and of a format of its own
    /// (F11 S13 criterion 26; standards §4 and §11). An unstructured `Task {` is found by `startsATask`, so
    /// that a task group's `addTask {` is not taken for one.
    static let unstructured = ["Task.detached", "DispatchQueue", "Timer", "TimelineView", ".formatted("]

    /// Whether `line` starts an unstructured task: `Task {`, `Task(priority:) {`, `Task<…>`, `Task.init {` or
    /// `Task.detached`, and not `addTask {`, `Task.yield()`, `Task.isCancelled` or `Task.checkCancellation()`
    /// (the round 1 tester's rule, F11-S13-3).
    static func startsATask(_ line: String) -> Bool {
        line.firstMatch(of: /(^|[^A-Za-z0-9_.])Task\s*(\{|\(|<|\.init\b|\.detached\b)/) != nil
    }

    /// The edit session, the stores and the roots (F11 S13 and S14).
    static let storeFiles = [
        "ProgramEditSession.swift", "ProgramStore.swift", "ProgramStore+Sources.swift", "ProgramRoot.swift"
    ]

    /// The lines of `source` on which `spelling` stands in code: the file's own, or a string interpolation's.
    /// A comparison (`repsHi ==`) is not the assignment it begins like.
    static func lines(of spelling: String, in source: SwiftSource) -> [Int] {
        let interpolated = source.literals.flatMap { literal in
            literal.interpolations
                .filter { $0.filter { !$0.isWhitespace }.contains(spelling) }
                .map { _ in literal.line }
        }
        let compared = spelling.hasSuffix("=") ? source.lines(ofCode: spelling + "=") : []
        return Set(source.lines(ofCode: spelling) + interpolated).subtracting(compared).sorted()
    }

    /// Each use of one of `spellings` in the module's files that `isRead` accepts, as "file:line: spelling".
    static func uses(of spellings: [String], inFiles isRead: (String) -> Bool = { _ in true }) throws -> [String] {
        let sources = try CopyAudit.sources(ofModule: "FeatureProgram")
        try #require(sources.count >= 7, "FeatureProgram's sources were not found")
        return sources.sorted { $0.key < $1.key }.filter { isRead($0.key) }.flatMap { path, text in
            let source = SwiftSource(text)
            return spellings.flatMap { spelling in
                lines(of: spelling, in: source).map { "\(path):\($0): \(spelling)" }
            }
        }
    }

    /// A file that could hold logic: every file but the copy, the models and the route, by its name. A store,
    /// an edit session, a presentation builder and a view are all read.
    static func canHoldLogic(_ path: String) -> Bool {
        !path.contains("Copy") && !path.contains("Model") && !path.contains("Route")
    }

    /// A file that prints or carries what is drawn: a presentation builder, a copy file or a model.
    static func printsWhatIsDrawn(_ path: String) -> Bool {
        path.contains("Presentation") || path.contains("Copy") || path.contains("Model")
    }

    @Test(
        "No file of FeatureProgram reads the clock, the current calendar, the current locale or the current time zone"
    )
    func sources_neverReadTheClockOrTheCurrentCalendar() throws {
        #expect(try Self.uses(of: Self.ambient) == [])
    }

    @Test("No store and no presentation clamps a value or writes the top of a rep range: that is ProgramEditing's")
    func storesAndPresentations_neverClamp() throws {
        #expect(try Self.uses(of: Self.clamps, inFiles: Self.canHoldLogic) == [])
        let read = try CopyAudit.sources(ofModule: "FeatureProgram").keys.filter(Self.canHoldLogic)
        #expect(read.count >= 5, "the files that hold logic were not found: \(read.sorted())")
        #expect(read.contains("ProgramBuilderAction.swift") && read.contains("ProgramPresentation+Weeks.swift"))
        // The Day editor's files (F11 S6 criterion 9) are read too, from their folder.
        for name in [
            "DayEditorPresentation.swift",
            "DayEditorPresentation+Rows.swift",
            "DayEditorAction.swift",
            "SlotEditorPresentation.swift",
            "SlotEditorPresentation+Fields.swift",
            "SlotEditorPresentation+Preview.swift",
            // The exercise library's (F11 S8 criterion 13).
            "ExercisePickerPresentation.swift",
            "ExercisePickerAction.swift",
            "ExercisePickerInput.swift"
        ] + Self.storeFiles {
            #expect(read.contains { $0.hasSuffix(name) }, "\(name) is not among the files read")
        }
    }

    @Test("No file of FeatureProgram starts a task of its own; the stores and roots keep no timer and format nothing")
    func sources_startNoWorkOfTheirOwn() throws {
        #expect(try Self.uses(of: Self.unstructured, inFiles: Self.storeFiles.contains) == [])
        let sources = try CopyAudit.sources(ofModule: "FeatureProgram")
        let tasks = sources.sorted { $0.key < $1.key }.flatMap { path, text in
            SwiftSource(text).code.enumerated().filter { Self.startsATask($0.element) }
                .map { "\(path):\($0.offset + 1)" }
        }
        #expect(tasks == [])
        for name in Self.storeFiles {
            #expect(sources[name] != nil, "\(name) is not among the files read")
        }
        for spelling in [
            "let task = Task { await work() }", "Task {", "Task(priority: .high) { }", "_ = Task.init { }",
            "Task<Void, Never> { }", "Task.detached { }"
        ] {
            #expect(Self.startsATask(spelling), "\(spelling)")
        }
        for spelling in ["group.addTask { await self.follow() }", "await Task.yield()", "Task.isCancelled"] {
            #expect(!Self.startsATask(spelling), "\(spelling)")
        }
    }

    @Test("The presentations, the copy and the models never name Double: weights stay exact")
    func presentationsCopyAndModels_neverNameDouble() throws {
        #expect(try Self.uses(of: Self.inexact, inFiles: Self.printsWhatIsDrawn) == [])
        let read = try CopyAudit.sources(ofModule: "FeatureProgram").keys.filter(Self.printsWhatIsDrawn)
        #expect(read.count >= 6, "the presentation, copy and model files were not found: \(read.sorted())")
        // The exercise library's files (F11 S8) are read too, the model and the copy among them.
        for name in ["ExercisePickerPresentation.swift", "ExercisePickerModel.swift", "ProgramCopy+Picker.swift"] {
            #expect(read.contains { $0.hasSuffix(name) }, "\(name) is not among the files read")
        }
    }

    @Test("The check reads code and the code of an interpolation, not comments or text, and finds what is there")
    func check_findsASpellingInCodeAndInInterpolations() {
        let source = SwiftSource("""
        /// Never `Date()` or max(a, b) here.
        let now = Date ()
        let zone = TimeZone
            .current
        let text = "Calendar.current, min(a, b) and Date() are only words here"
        let line = "Week \\(min(week, last)) of \\(Date.now.formatted())"
        slot.repsHi = slot.reps + 1
        let isWide = slot.repsHi == slot.reps + 2
        let nearest = weeks.indices.min(by: closer)
        let kilograms = "\\(weight.doubleValue) kg"
        """)
        #expect(Self.lines(of: "Date()", in: source) == [2])
        #expect(Self.lines(of: "TimeZone.current", in: source) == [3])
        #expect(Self.lines(of: "Calendar.current", in: source) == [])
        #expect(Self.lines(of: "Date.now", in: source) == [6])
        #expect(Self.lines(of: "min(", in: source) == [6, 9])
        #expect(Self.lines(of: "max(", in: source) == [])
        #expect(Self.lines(of: "repsHi=", in: source) == [7])
        #expect(Self.lines(of: ".doubleValue", in: source) == [10])
        // Every spelling of the three lists is found when it stands in code.
        for spelling in Self.ambient + Self.clamps + Self.inexact + Self.unstructured {
            #expect(Self.lines(of: spelling, in: SwiftSource("let value = call(\(spelling)")) == [1], "\(spelling)")
        }
    }
}
