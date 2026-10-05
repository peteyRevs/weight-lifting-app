import LedgerTestSupport
import Testing

/// `CopyAudit`, the half about the copy files themselves: they hold nothing but lookups, each one written so that
/// the check can name its key and reading this module's catalog.
extension CopyAuditTests {
    @Test("A string the copy file returns without looking it up is a finding")
    func literalInTheCopyFile_isAFinding() throws {
        let copy = Self.copyFile.replacing(
            "String(localized: \"Today\", bundle: .module)",
            with: "\"Today\""
        )
        #expect(try Self.findings(copy: copy) == [
            "DemoCopy.swift:4: a string literal that is not a lookup: \"Today\"",
            "Localizable.xcstrings: \"Today\" is not looked up by a copy file"
        ])
    }

    @Test("A lookup the check cannot key is a finding", arguments: [
        (#""\(count) exercises""#, #""\(count + 1) exercises""#),
        (#""\(count) exercises""#, #""\(Self.limit) exercises""#),
        ("_ count: Int", "_ count: Double"),
        ("_ count: Int", "_ count: Int?")
    ])
    func unreadableLookup_isAFinding(readable: String, unreadable: String) throws {
        let findings = try Self.findings(copy: Self.copyFile.replacing(readable, with: unreadable))
        #expect(findings.count == 2)
        #expect(findings.first?.hasPrefix("DemoCopy.swift:11: a lookup this check cannot read") == true)
        #expect(findings.last == "Localizable.xcstrings: \"%lld exercises\" is not looked up by a copy file")
    }

    @Test("A lookup that does not read this module's catalog is a finding", arguments: [
        #"String(localized: "Today")"#,
        #"String(localized: "Today", table: "Other", bundle: .module)"#,
        #"String(localized: "Today", bundle: .main)"#
    ])
    func lookupInAnotherBundleOrTable_isAFinding(code: String) throws {
        let copy = Self.copyFile.replacing("String(localized: \"Today\", bundle: .module)", with: code)
        let findings = try Self.findings(copy: copy)
        #expect(findings.contains("DemoCopy.swift: 1 lookup(s) not written `localized: \"…\", bundle: .module`"))
    }

    @Test("An interpolated lookup that leaves out the bundle is a finding too")
    func interpolatedLookupWithoutTheBundle_isAFinding() throws {
        let copy = Self.copyFile.replacing("bundle: .module, locale: locale", with: "locale: locale")
        #expect(try Self.findings(copy: copy) == [
            "DemoCopy.swift: 1 lookup(s) not written `localized: \"…\", bundle: .module`"
        ])
    }

    @Test("A lookup whose key is not a literal, or that uses another API, is a finding", arguments: [
        (
            "String(localized: String.LocalizationValue(stringLiteral: name), bundle: .module)",
            [
                "DemoCopy.swift: 1 lookup(s) whose key is not a string literal",
                "DemoCopy.swift:4: a lookup that is not `String(localized:)`: LocalizationValue"
            ]
        ),
        (
            "NSLocalizedString(name, bundle: .module, comment: comment)",
            ["DemoCopy.swift:4: a lookup that is not `String(localized:)`: NSLocalizedString"]
        ),
        (
            "Bundle.module.localizedString(forKey: name, value: nil, table: nil)",
            ["DemoCopy.swift:4: a lookup that is not `String(localized:)`: localizedString(forKey"]
        ),
        (
            "String(localized: LocalizedStringResource(stringLiteral: name))",
            [
                "DemoCopy.swift: 1 lookup(s) whose key is not a string literal",
                "DemoCopy.swift:4: a lookup that is not `String(localized:)`: LocalizedStringResource"
            ]
        )
    ])
    func lookupTheCheckCannotCompare_isAFinding(code: String, expected: [String]) throws {
        let copy = Self.copyFile.replacing("String(localized: \"Today\", bundle: .module)", with: code)
        let unused = "Localizable.xcstrings: \"Today\" is not looked up by a copy file"
        #expect(try Self.findings(copy: copy) == expected + [unused])
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
