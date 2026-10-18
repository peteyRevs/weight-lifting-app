@testable import FeatureProgram
import Foundation
import LedgerTestSupport
import Testing

/// F11 S13 adversarial round 1: the conventions, by test (criterion 26), and the audit of the sanctioned edit to
/// `ProgramWordsAdversarialTests` (round 1's literal scan). The scans read every file of `FeatureProgram`, the
/// folders included, through `SwiftSource`, which tells code from comments and literals.
@Suite("Adversarial F11 S13 · the stores' conventions, by their sources", .tags(.feature))
nonisolated struct ProgramStoreSourceAdversarialTests {
    /// The files S13 adds.
    static let storeFiles = [
        "ProgramEditSession.swift", "ProgramStore.swift", "ProgramStore+Sources.swift", "ProgramRoot.swift",
        "ProgramCopy+States.swift"
    ]

    static func sources() throws -> [(path: String, source: SwiftSource)] {
        try CopyAudit.sources(ofModule: "FeatureProgram").sorted { $0.key < $1.key }.map { (
            $0.key,
            SwiftSource($0.value)
        ) }
    }

    static func name(_ path: String) -> String {
        String(path.split(separator: "/").last ?? "")
    }

    // MARK: Work no task owns, clocks, formats

    /// Any way of starting a task of its own: `Task {`, `Task(priority:) {`, `Task<…>`, `Task.init`, detached.
    /// A task group's `addTask` and `Task.yield`, `Task.isCancelled`, `Task.checkCancellation` are not.
    static func startsATask(_ code: String) -> Bool {
        code.firstMatch(of: /(^|[^A-Za-z0-9_.])Task\s*(\{|\(|<|\.init\b|\.detached\b)/) != nil
    }

    @Test("No file of the module starts a task of any spelling; the stores keep no timer, sleep or format")
    func noTaskOfItsOwn_noTimer_noFormat() throws {
        let banned = [
            "Timer", "TimelineView", ".formatted(", "DispatchQueue", "Task.sleep", ".sleep(", "Date()", "Date.now",
            "Calendar.current", "Locale.current", "TimeZone.current", "ContinuousClock", "SuspendingClock", "UUID()"
        ]
        var found: [String] = []
        let files = try Self.sources()
        for (path, source) in files {
            for (number, line) in source.code.enumerated() {
                if Self.startsATask(line) {
                    found.append("\(path):\(number + 1) a task")
                }
                if Self.storeFiles.contains(Self.name(path)) {
                    found += banned.filter { line.contains($0) }.map { "\(path):\(number + 1) \($0)" }
                }
            }
        }
        for name in Self.storeFiles {
            #expect(files.contains { Self.name($0.path) == name }, "\(name) is not read")
        }
        #expect(found.isEmpty, "\(found)")
        // The scan has teeth, and finds the spellings the implementer's tripwire does not.
        for spelling in [
            "Task { await x() }", "let t = Task(priority: .high) { await x() }", "Task<Void, Never> { }",
            "_ = Task.init { }", "Task.detached { }", "x = Task{}"
        ] {
            #expect(Self.startsATask(spelling), "\(spelling)")
        }
        for spelling in [
            "group.addTask { }",
            "await Task.yield()",
            "if Task.isCancelled {",
            "try Task.checkCancellation()"
        ] {
            #expect(!Self.startsATask(spelling), "\(spelling)")
        }
    }

    @Test(
        "Audit: the implementer's tripwire takes `Task(priority:) {` and `Task.init {` for a task (fixed)"
    )
    func implementersTripwire_catchesBothSpellings() {
        #expect(FeatureProgramSourceTests.startsATask("let t = Task { }"))
        #expect(FeatureProgramSourceTests.startsATask("let t = Task(priority: .userInitiated) { await x() }"))
        #expect(FeatureProgramSourceTests.startsATask("_ = Task.init { await x() }"))
    }

    // MARK: Literals and lookups

    /// Whether `literal` is a log line's message (the first argument of `logger.log.<level>(`) or the logger's
    /// own category, `.category("program")`; read through the literal that holds it, for one inside an
    /// interpolation. `SwiftSource` reads a callee across the code with its spaces and line breaks removed, so
    /// the statement before can run into it (`.saveFailedlogger.log.error`): the match is on its end.
    static func isForTheDeveloper(_ literal: SwiftStringLiteral, in source: SwiftSource) -> Bool {
        var outer = literal
        while let holder = outer.holder {
            outer = source.literals[holder]
        }
        guard let argument = outer.argument else {
            return false
        }
        if argument.callee.firstMatch(of: /logger\.log\.(debug|info|notice|error|fault|warning)$/) != nil {
            return argument.index == 0 && argument.label.isEmpty
        }
        return argument.callee.hasSuffix(".category") && outer.text == "program" && literal == outer
    }

    @Test(
        "Outside the copy files a literal is \"\", \" · \", a log message or the logger's category; no lookup"
    )
    func literals_onlyInTheCopyFiles_tighterThanTheSanctionedScan() throws {
        var found: [String] = []
        // The module's own folder, as round 1's scan reads it: the views' folders draw `Text(model.…)`.
        let files = try Self.sources().filter { !$0.path.contains("/") && !Self.name($0.path).hasPrefix("ProgramCopy") }
        for (path, source) in files {
            for literal in source.literals where !["", " · "].contains(literal.text) {
                if !Self.isForTheDeveloper(literal, in: source) {
                    found.append("\(path):\(literal.line) \"\(literal.text)\"")
                }
            }
            let lookups = [
                "String(localized",
                "LocalizedStringKey",
                "LocalizedStringResource",
                "NSLocalizedString",
                "Text(",
                "bundle:",
                "AttributedString(localized"
            ]
            for (number, line) in source.code.enumerated() {
                found += lookups.filter { line.contains($0) }.map { "\(path):\(number + 1) \($0)" }
            }
        }
        #expect(found.isEmpty, "\(found.prefix(8))")
    }

    @Test(
        "Audit: the sanctioned exemption lets a lifter's text through on a line that logs; the tighter one does not"
    )
    func sanctionedExemption_isTooWide_tighterOneHolds() {
        let line = #"notice = "Saved"; logger.log.error("kept")"#
        let shipped = line.contains("logger.log.") || line.contains(".category(")
        #expect(shipped, "the shipped scan skips every literal of this line, \"Saved\" included")
        let source = SwiftSource(line)
        let flagged = source.literals.filter { !Self.isForTheDeveloper($0, in: source) }.map(\.text)
        #expect(flagged == ["Saved"])
        let labelled = SwiftSource(#"logger.log.error("x", label: "Program")"#)
        #expect(labelled.literals.filter { !Self.isForTheDeveloper($0, in: labelled) }.map(\.text) == ["Program"])
        let category = SwiftSource(#"injectedLogger.category("program")"#)
        #expect(category.literals.allSatisfy { Self.isForTheDeveloper($0, in: category) })
        let otherCategory = SwiftSource(#"injectedLogger.category("Week")"#)
        #expect(otherCategory.literals.map(\.text) == ["Week"])
        #expect(!otherCategory.literals.allSatisfy { Self.isForTheDeveloper($0, in: otherCategory) })
    }
}
