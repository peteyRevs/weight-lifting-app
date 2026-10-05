import LedgerTestSupport
import Testing

/// `CopyAudit` (LedgerTestSupport): the source half of standards §7's check, on sources and catalogs built in
/// memory, each rule broken once. That a catalog's keys are the code's keys is not tested here: the gate's
/// `scripts/check-string-catalogs.sh` compares them with the compiler's (`scripts/tests/adversarial/`).
@Suite("CopyAudit")
struct CopyAuditTests {
    static let copyFile = #"""
    import SwiftUI

    nonisolated enum DemoCopy {
        static var title: String { String(localized: "Today", bundle: .module) }

        static func week(_ week: Int, of total: Int, locale: Locale) -> String {
            String(localized: "Week \(week) of \(total)", bundle: .module, locale: locale, comment: "The block")
        }

        static func resume(since start: Date) -> Text {
            Text("Resume · \(timerInterval: start ... .distantFuture)", bundle: .module)
        }

        static func next(
            day: String,
            locale: Locale
        ) -> String {
            String(
                localized: "Next: \(day), 100% sure",
                bundle: .module,
                locale: locale
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

    static func findings(
        copy: String = copyFile,
        view: String = view,
        extra: [String: String] = [:],
        catalog: StringCatalog? = nil,
        exempting exemptions: CopyAudit.Exemptions = [:]
    ) throws -> [String] {
        let sources = ["DemoCopy.swift": copy, "Views/DemoScreen.swift": view].merging(extra) { $1 }
        let keys = try TestCatalog.plain("Today", "Week %lld of %lld", "Resume · %@", "Next: %@, 100%% sure")
        return CopyAudit(sources: sources, catalog: catalog ?? keys, exempting: exemptions).findings
    }

    @Test("A module with both lookup forms in its copy file and identifiers and symbols in its view has no findings")
    func soundModule_hasNoFindings() throws {
        #expect(try Self.findings() == [])
    }

    @Test("The audit derives no key: a catalog with other keys than the code's is the gate's to find, not its own")
    func keys_areNotComparedHere() throws {
        #expect(try Self.findings(catalog: TestCatalog.plain("Start workout")) == [])
    }

    @Test("The catalog's own problems are findings")
    func catalogProblems_areFindings() throws {
        let catalog = try TestCatalog.make([
            "Today": .text("Today", state: "new"),
            "%lld exercises": .counted(["other": "%lld exercises"])
        ])
        #expect(try Self.findings(catalog: catalog) == [
            "Localizable.xcstrings: \"%lld exercises\" needs exactly the forms \"one\" and \"other\"",
            "Localizable.xcstrings: \"Today\" is not marked translated: "
                + "a hand-written catalog marks its English text so"
        ])
    }

    // MARK: Copy outside the copy file

    @Test("A string literal a lifter could see, outside the copy file, is a finding", arguments: StrayLiteral.all)
    func strayLiteral_isAFinding(_ stray: StrayLiteral) throws {
        let screen = Self.view.replacing("DemoCopy.title", with: stray.code)
        #expect(try Self.findings(view: screen) == ["Views/DemoScreen.swift:5: \(stray.finding)"])
    }

    @Test("A localized lookup outside the copy file is a finding, however it is spelled or wrapped", arguments: [
        ("String(localized: title)", "localized:"),
        ("NSLocalizedString(title, comment: comment)", "NSLocalizedString"),
        ("LocalizedStringKey(title)", "LocalizedStringKey"),
        ("bundle.localizedString(\n    forKey: title,\n    value: nil,\n    table: nil\n)", "localizedString(forKey"),
        ("bundle.localizedAttributedString(forKey: title, value: nil, table: nil)", "localizedAttributedString(forKey"),
        (#""\(NSLocalizedString(title, comment: comment)) · ""#, "NSLocalizedString")
    ])
    func strayLookup_isAFinding(code: String, spelling: String) throws {
        let screen = Self.view.replacing("DemoCopy.title", with: code)
        #expect(try Self.findings(view: screen) == [
            "Views/DemoScreen.swift:5: a localized lookup outside the copy files: \(spelling)"
        ])
    }

    @Test("A literal in an argument no lifter sees is not copy, whatever picks it", arguments: [
        #".accessibilityIdentifier("today.recent.row.\(index)")"#,
        #".accessibilityIdentifier(isToday ? "strip.today" : "strip.day")"#,
        #".accessibilityIdentifier("strip.\(isToday ? "today" : "day")")"#,
        #"PlaceholderScreen(title, identifier: "program.title")"#,
        #"Row(title, titleIdentifier: "demo.row")"#,
        #"Image(systemName: isDone ? "checkmark.circle" : "circle")"#,
        #"Label(title, systemImage: ["play.fill", "pause.fill"][state])"#,
        #"LedgerLogger(category: "today")"#,
        #"logger.log.error("Today failed for \(workout?.name ?? "none")")"#,
        #"Logger.persistence.notice("Seeded the catalog")"#,
        "launchLogger.log.debug(\n    \"Launch: \\(String(describing: event), privacy: .public)\"\n)",
        #"Text(parts.joined(separator: " · "))"#,
        #"let clock = "\(minutes):\(seconds)""#
    ])
    func literalNoLifterSees_isNotAFinding(code: String) throws {
        #expect(try Self.findings(extra: ["Other.swift": code]) == [])
    }

    @Test("A name that only reads like an allowed label, or like a logger's call, allows nothing", arguments: [
        #"let view = Text(isStock ? systemName : "Custom exercise")"#,
        "func label(_ field: Field) -> String {\n    switch field { case .identifier: \"Barcode\" }\n}",
        #"state = .error("Can't show today")"#,
        #"let view = Row(title) { log("Tapped") }.accessibilityIdentifier(id)"#
    ])
    func lookalike_isAFinding(code: String) throws {
        let findings = try Self.findings(extra: ["Other.swift": code])
        #expect(findings.count == 1, "\(findings)")
        #expect(findings.first?.contains("a string literal outside the copy files") == true, "\(findings)")
    }

    @Test("A comment that quotes copy is not copy")
    func comment_isNotAFinding() throws {
        let code = """
        /// Shows "Start workout" until the workout is live.
        // Text("Resume")
        let ready = true
        """
        #expect(try Self.findings(extra: ["Other.swift": code]) == [])
    }

    @Test("A module without a catalog may hold no copy file, and its other files are audited as any are")
    func moduleWithoutACatalog_holdsNoCopy() {
        let sources = ["DemoCopy.swift": Self.copyFile, "Views/DemoScreen.swift": #"let view = Text("Today")"#]
        #expect(CopyAudit(sources: sources, catalog: nil).findings == [
            "DemoCopy.swift: is a copy file in a module that has no catalog",
            "Views/DemoScreen.swift:1: a literal handed to Text outside the copy files: \"Today\""
        ])
        #expect(CopyAudit(sources: ["Views/DemoScreen.swift": Self.view], catalog: nil).findings == [])
    }
}

/// A way to show a literal outside the copy file, in place of `DemoCopy.title` on line 5 of the demo view.
nonisolated struct StrayLiteral: Sendable, CustomTestStringConvertible {
    let code: String
    let finding: String

    var testDescription: String {
        code
    }

    static let all: [StrayLiteral] = [
        StrayLiteral(code: #""Start workout""#, finding: "a string literal outside the copy files: \"Start workout\""),
        StrayLiteral(code: #"String("Week \(week)")"#, finding: "a string literal outside the copy files: \"Week \""),
        StrayLiteral(
            code: #"isLive ? "Resume" : DemoCopy.title"#,
            finding: "a string literal outside the copy files: \"Resume\""
        ),
        StrayLiteral(
            code: #"DemoCopy.title + " \(isDone ? "done" : DemoCopy.title)""#,
            finding: "a string literal outside the copy files: \"done\""
        ),
        StrayLiteral(
            code: #"Text("\(done)/\(total)").body"#,
            finding: "a literal handed to Text outside the copy files: \"/\""
        ),
        StrayLiteral(code: #"Text("—").body"#, finding: "a literal handed to Text outside the copy files: \"—\"")
    ]
}
