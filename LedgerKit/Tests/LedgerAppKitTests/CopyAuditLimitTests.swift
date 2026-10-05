import LedgerTestSupport
import Testing

/// The known limits of `CopyAudit`, as standards §7 lists them ("Known limits"): what the audit reads past, and
/// review has to find. Each case fails when the audit starts to find it, so that list stays true. Two more limits
/// are pinned in the tester's suites: a regex literal that holds a quote (`CopyAuditAdversarialTests`), a text
/// made from a name (`CopyAuditAllowedAdversarialTests`) and a locale written into a copy member
/// (`CopyAuditCloseOutAdversarialTests`).
@Suite("CopyAudit limits")
struct CopyAuditLimitTests {
    private static let stillHolds: Comment = "the limit no longer holds: update standards §7, \"Known limits\""

    /// The first is no lookup, so nothing finds it. The other two are lookups: in a module with a catalog the
    /// gate's catalog step fails them as lookups outside the copy file (`string-catalogs.adv.sh`, SC78), and in a
    /// module without one nothing does.
    @Test("Limit: the audit finds a literal without a letter only where it is handed straight to Text", arguments: [
        "let ratio = \"\\(done)/\\(total)\"\nlet view = Text(ratio)",
        #"let view = Label("—", systemImage: "minus")"#,
        #"let view = list.navigationTitle("\(count)")"#
    ])
    func limit_literalWithoutALetter(code: String) throws {
        #expect(try CopyAuditTests.findings(extra: ["Other.swift": code]) == [], Self.stillHolds)
    }

    @Test("Limit: the audit reads names, not types: any call that reads like an allowed one is allowed", arguments: [
        #"toastLogger.error("Can't save your workout")"#,
        #"let chip = Chip(category: "Push day")"#,
        #"let banner = Banner(identifier: "Start workout")"#,
        #"let row = Row(subtitleIdentifier: "Last time")"#
    ])
    func limit_callThatReadsLikeAnAllowedOne(code: String) throws {
        #expect(try CopyAuditTests.findings(extra: ["Other.swift": code]) == [], Self.stillHolds)
    }

    @Test("Limit: what a key's value is goes unread: an expression and an optional pass", arguments: [
        ("week: Int", #""Week \(week + 1)""#),
        ("count: Int?", #""\(count) sets""#),
        ("count: String", #""\(count.uppercased()) sets""#)
    ])
    func limit_valueOfAKey(parameters: String, key: String) throws {
        let member = "static func line(\(parameters), locale: Locale) -> String {\n"
            + "    String(localized: \(key), bundle: .module, locale: locale)\n}"
        #expect(try CopyAuditTests.findings(extra: ["LineCopy.swift": member]) == [], Self.stillHolds)
    }

    @Test("Limit: parentheses that do not balance in the text keep later literals inside that argument", arguments: [
        "#if os(iOS)\nlet row = Row(identifier:\n#else\nlet row = Cell(identifier:\n#endif\n    id)\n"
            + "let start = \"Start workout\"",
        "let pattern = /\\(identifier: /\nlet start = \"Start workout\""
    ])
    func limit_parenthesesThatDoNotBalance(code: String) throws {
        #expect(try CopyAuditTests.findings(extra: ["Other.swift": code]) == [], Self.stillHolds)
    }

    @Test("Limit: an exemption is a text, so it covers every literal of its file that reads so")
    func limit_exemptionCoversEveryLiteralThatReadsSo() throws {
        let launch = """
        let isUITest = arguments.contains("-LEDGER_UITEST")
        let label = Label("-LEDGER_UITEST", systemImage: "flag")
        """
        let findings = try CopyAuditTests.findings(
            extra: ["Launch.swift": launch],
            exempting: ["Launch.swift": ["-LEDGER_UITEST"]]
        )
        #expect(findings == [], Self.stillHolds)
    }

    @Test("Limit: code in a copy file that holds no literal is not read: a key is not checked against its values")
    func limit_copyFileCodeWithoutALiteral() throws {
        let title = #"String(localized: "Today", bundle: .module)"#
        let copy = CopyAuditTests.copyFile.replacing(title, with: "\(title).uppercased() + suffix")
        #expect(try CopyAuditTests.findings(copy: copy) == [], Self.stillHolds)
    }
}
