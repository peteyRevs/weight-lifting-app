import LedgerTestSupport
import Testing

/// `CopyAudit`, the half about files that are not copy files: a literal a lifter could see or a lookup there is a
/// finding; identifiers, symbol names and log lines are not; an exemption has to exempt something.
extension CopyAuditTests {
    // MARK: Copy outside the copy file

    @Test("A string literal a lifter could see, outside the copy file, is a finding", arguments: StrayLiteral.all)
    func strayLiteral_isAFinding(_ stray: StrayLiteral) throws {
        let screen = Self.view.replacing("DemoCopy.title", with: stray.code)
        #expect(try Self.findings(view: screen) == ["Views/DemoScreen.swift:5: \(stray.finding)"])
    }

    @Test("A localized lookup outside the copy file is a finding, however it is spelled", arguments: [
        ("String(localized: title)", "localized:"),
        ("NSLocalizedString(title, comment: comment)", "NSLocalizedString"),
        ("LocalizedStringKey(title)", "LocalizedStringKey"),
        ("String(localized: LocalizedStringResource(stringLiteral: title))", "LocalizedStringResource"),
        ("bundle.localizedString(forKey: title, value: nil, table: nil)", "localizedString(forKey"),
        (#""\(NSLocalizedString(title, comment: comment)) · ""#, "NSLocalizedString")
    ])
    func strayLookup_isAFinding(code: String, spelling: String) throws {
        let screen = Self.view.replacing("DemoCopy.title", with: code)
        let findings = try Self.findings(view: screen)
        #expect(findings.contains("Views/DemoScreen.swift:5: a localized lookup outside the copy files: \(spelling)"))
        #expect(findings.allSatisfy { $0.contains("a localized lookup outside the copy files") })
    }

    @Test("An identifier, an SF Symbol's name and a log line are not copy", arguments: [
        #".accessibilityIdentifier("today.recent.row.\(index)")"#,
        #"PlaceholderScreen(title, identifier: "program.title")"#,
        #"Row(title, titleIdentifier: "demo.row")"#,
        #"Image(systemName: "gearshape")"#,
        #"logger.log.error("Today failed to load: \(error, privacy: .public)")"#,
        #"Logger.persistence.notice("Seeded the catalog")"#,
        #"launchLogger.log.debug("Launch: \(String(describing: event), privacy: .public)")"#,
        #"Text(parts.joined(separator: " · "))"#
    ])
    func literalNoLifterSees_isNotAFinding(code: String) throws {
        #expect(try Self.findings(extra: ["Other.swift": code]) == [])
    }

    @Test("A text that only looks like a log line is still a finding")
    func enumCaseNamedLikeALogLevel_isAFinding() throws {
        #expect(try Self.findings(extra: ["Other.swift": #"state = .error("Can't show today")"#]) == [
            "Other.swift:1: a string literal outside the copy files: \"Can't show today\""
        ])
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

    @Test("A previews file is not read")
    func previewsFile_isNotRead() throws {
        let previews = #"#Preview("Tabs") { Text("Only in Xcode's canvas") }"#
        #expect(try Self.findings(extra: ["Demo+Previews.swift": previews]) == [])
    }

    // MARK: Exemptions

    @Test("An exempt file may hold literals, but not lookups")
    func exemptFile_mayHoldLiteralsOnly() throws {
        let launch = #"""
        let isUITest = arguments.contains("-LEDGER_UITEST")
        let title = String(localized: "Today", bundle: .module)
        """#
        #expect(try Self.findings(extra: ["Launch.swift": launch], exempting: ["Launch.swift": "launch arguments"]) == [
            "Launch.swift:2: a localized lookup outside the copy files: localized:"
        ])
    }

    @Test("An exemption that exempts nothing is a finding, so the list cannot go stale", arguments: [
        ("Views/DemoScreen.swift", "Views/DemoScreen.swift: is exempt, but holds no string literal to exempt"),
        ("Gone.swift", "Gone.swift: is exempt, but is not a file this check reads"),
        ("DemoCopy.swift", "DemoCopy.swift: is exempt, but is not a file this check reads")
    ])
    func staleExemption_isAFinding(path: String, finding: String) throws {
        #expect(try Self.findings(exempting: [path: "no reason"]) == [finding])
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
        StrayLiteral(
            code: #""Start workout""#,
            finding: "a string literal outside the copy files: \"Start workout\""
        ),
        StrayLiteral(
            code: #"String("Week \(week)")"#,
            finding: "a string literal outside the copy files: \"Week \""
        ),
        StrayLiteral(
            code: #"isLive ? "Resume" : DemoCopy.title"#,
            finding: "a string literal outside the copy files: \"Resume\""
        ),
        StrayLiteral(
            code: #"DemoCopy.title + " \(isDone ? "done" : DemoCopy.title)""#,
            finding: "a string literal outside the copy files: \"done\""
        )
    ]
}
