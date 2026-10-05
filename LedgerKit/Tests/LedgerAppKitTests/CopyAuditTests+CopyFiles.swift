import LedgerTestSupport
import Testing

/// `CopyAudit`, the half about the copy files themselves: they hold nothing but the two lookup forms of standards
/// §7, each reading this module's catalog, none inside another literal, and with `locale:` when the key carries a
/// value.
extension CopyAuditTests {
    private static let title = #"String(localized: "Today", bundle: .module)"#

    /// The findings when the demo copy file's plain lookup is written as `code`.
    private static func findings(title code: String) throws -> [String] {
        try findings(copy: copyFile.replacing(title, with: code))
    }

    @Test("A string the copy file returns without looking it up is a finding")
    func literalInTheCopyFile_isAFinding() throws {
        #expect(try Self.findings(title: #""Today""#) == [
            "DemoCopy.swift:4: a string literal that is not a lookup: \"Today\""
        ])
    }

    @Test("A lookup that does not read this module's catalog is a finding", arguments: [
        #"String(localized: "Today")"#,
        #"String(localized: "Today", table: nil, bundle: .module)"#,
        #"String(localized: "Today", bundle: .main)"#,
        "String(localized: \"Today\", defaultValue: \"\u{2014}\", bundle: .module)"
    ])
    func lookupInAnotherBundleOrTable_isAFinding(code: String) throws {
        #expect(try Self.findings(title: code) == [
            "DemoCopy.swift:4: a lookup not written `String(localized: \"…\", bundle: .module)`"
        ])
    }

    @Test("A lookup whose key carries a value passes `locale:`: without it, a finding")
    func lookupWithAValueAndNoLocale_isAFinding() throws {
        let copy = Self.copyFile.replacing(
            "bundle: .module, locale: locale, comment:",
            with: "bundle: .module, comment:"
        )
        #expect(try Self.findings(copy: copy) == [
            "DemoCopy.swift:7: a lookup whose key carries a value and that passes no `locale:`"
        ])
    }

    @Test("A lookup is never written inside another literal's interpolation", arguments: [
        #""\(String(localized: "Today", bundle: .module)) · \(reps)""#,
        #""\(String(localized: "Today")) · \(reps)""#,
        #""\(String(localized: key, bundle: .module)) · \(reps)""#,
        #"String(localized: "\(String(localized: "Today", bundle: .module)) now", bundle: .module, locale: locale)"#
    ])
    func lookupInsideAnInterpolation_isAFinding(code: String) throws {
        #expect(try Self.findings(title: code) == [
            "DemoCopy.swift:4: a lookup inside another literal's interpolation: write the join as two statements"
        ])
    }

    @Test("A lookup whose key is not a literal, or that uses another API, is a finding", arguments: [
        (
            "String(localized: String.LocalizationValue(stringLiteral: name), bundle: .module)",
            [
                "DemoCopy.swift:4: a lookup that is not `String(localized: \"…\"`, its key a literal",
                "DemoCopy.swift:4: a lookup that is not `String(localized:)`: LocalizationValue"
            ]
        ),
        (
            "NSLocalizedString(name, bundle: .module, comment: note)",
            ["DemoCopy.swift:4: a lookup that is not `String(localized:)`: NSLocalizedString"]
        ),
        (
            "Bundle.module.localizedString(\n    forKey: name,\n    value: nil,\n    table: nil\n)",
            ["DemoCopy.swift:4: a lookup that is not `String(localized:)`: localizedString(forKey"]
        ),
        (
            "String(AttributedString(localized: \"\\(name)\", bundle: .module).characters)",
            ["DemoCopy.swift:4: a lookup that is not `String(localized: \"…\"`, its key a literal"]
        ),
        (
            "String(localized: \"\"\"\n            Today\n            \"\"\", bundle: .module)",
            ["DemoCopy.swift:4: a lookup whose key is not a one-line literal"]
        )
    ])
    func lookupInAnotherForm_isAFinding(code: String, expected: [String]) throws {
        #expect(try Self.findings(title: code) == expected)
    }

    @Test("A Text's own lookup is allowed only around a live timer, reading this module's catalog", arguments: [
        #"Text("Resume", bundle: .module)"#,
        #"Text("Resume · \(elapsed)", bundle: .module)"#,
        #"Text("Resume · \(timerInterval: start ... .distantFuture)")"#
    ])
    func textLookupThatIsNotTheTimerForm_isAFinding(code: String) throws {
        let timer = #"Text("Resume · \(timerInterval: start ... .distantFuture)", bundle: .module)"#
        #expect(try Self.findings(copy: Self.copyFile.replacing(timer, with: code)) == [
            "DemoCopy.swift:11: a Text's own lookup that is not `Text(\"… \\(timerInterval: …)\", bundle: .module)`"
        ])
    }

    @Test("A `comment:` is skipped only on a lookup: the same label on another call is a literal like any other")
    func commentOnAnotherCall_isAFinding() throws {
        #expect(try Self.findings(title: #"Wrapper(comment: "Start workout").text"#) == [
            "DemoCopy.swift:4: a string literal that is not a lookup: \"Start workout\""
        ])
    }

    @Test("A file is a copy file by its name", arguments: [
        ("AppCopy.swift", true),
        ("TodayCopy+Cards.swift", true),
        ("Views/TodayCopy.swift", true),
        ("Copy.swift", false),
        ("TodayCopyTests.swift", false),
        ("CopyButton.swift", false),
        ("TodayCopy+.swift", false)
    ])
    func copyFile_isNamedCopy(path: String, isCopyFile: Bool) {
        #expect(CopyAudit.isCopyFile(path) == isCopyFile)
    }
}
