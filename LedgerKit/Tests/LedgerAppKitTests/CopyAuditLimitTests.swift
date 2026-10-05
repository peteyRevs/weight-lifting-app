import LedgerTestSupport
import Testing

/// The known limits of `CopyAudit`, as standards §7 lists them ("Known limits"): what the audit reads past, and
/// review has to find. Each case fails when the audit starts to find it, so that list stays true. Two more limits
/// are pinned in the tester's suites: a regex literal that holds a quote (`CopyAuditAdversarialTests`) and a text
/// made from a name (`CopyAuditAllowedAdversarialTests`).
@Suite("CopyAudit limits")
struct CopyAuditLimitTests {
    private static let stillHolds: Comment = "the limit no longer holds: update standards §7, \"Known limits\""

    @Test("Limit: a literal without a letter is found only where it is handed straight to Text", arguments: [
        #"let view = Label("—", systemImage: "minus")"#,
        "let ratio = \"\\(done)/\\(total)\"\nlet view = Text(ratio)",
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

    @Test("Limit: a Text joined from parts in a copy file is not found; standards §7 forbids it")
    func limit_textJoinedFromParts() throws {
        let timer = #"Text("Resume · \(timerInterval: start ... .distantFuture)", bundle: .module)"#
        let joined = #"Text(String(localized: "Today", bundle: .module)) + Text(verbatim: " · ") + Text(start...)"#
        let copy = CopyAuditTests.copyFile.replacing(timer, with: joined)
        #expect(copy.contains(joined))
        #expect(try CopyAuditTests.findings(copy: copy) == [], Self.stillHolds)
    }

    @Test("Limit: what a key's value is goes unread: an expression, a Double, an optional pass", arguments: [
        ("week: Int", #""Week \(week + 1)""#),
        ("value: Double", #""\(value) lb moved""#),
        ("count: Int?", #""\(count) sets""#),
        ("count: String", #""\(count.uppercased()) sets""#)
    ])
    func limit_valueOfAKey(parameters: String, key: String) throws {
        let member = "static func line(\(parameters), locale: Locale) -> String {\n"
            + "    String(localized: \(key), bundle: .module, locale: locale)\n}"
        #expect(try CopyAuditTests.findings(extra: ["LineCopy.swift": member]) == [], Self.stillHolds)
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
