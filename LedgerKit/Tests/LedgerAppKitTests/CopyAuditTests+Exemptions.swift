import LedgerTestSupport
import Testing

/// `CopyAudit`, what a module may set aside: literals no lifter sees, named one by one, and files of Debug builds
/// only, which the audit leaves unread once it has checked that they are.
extension CopyAuditTests {
    @Test("An exemption names a file's literals: those pass, any other literal of the file is a finding")
    func exemption_namesLiterals() throws {
        let launch = """
        let isUITest = arguments.contains("-LEDGER_UITEST")
        var failure = "Can't show today right now"
        """
        #expect(try Self.findings(extra: ["Launch.swift": launch], exempting: ["Launch.swift": ["-LEDGER_UITEST"]]) == [
            "Launch.swift:2: a string literal outside the copy files: \"Can't show today right now\""
        ])
    }

    @Test("An exemption does not cover a lookup, nor a literal handed to Text")
    func exemption_coversNoLookupAndNoText() throws {
        let screen = "let title = String(localized: key)\nlet view = Text(\"Today\")"
        #expect(try Self.findings(extra: ["Launch.swift": screen], exempting: ["Launch.swift": ["Today"]]) == [
            "Launch.swift: is exempt for \"Today\", which it does not hold",
            "Launch.swift:1: a localized lookup outside the copy files: localized:",
            "Launch.swift:2: a literal handed to Text outside the copy files: \"Today\""
        ])
    }

    @Test("An exemption that exempts nothing is a finding, so the list cannot go stale", arguments: [
        ("Views/DemoScreen.swift", "Views/DemoScreen.swift: is exempt for \"-x\", which it does not hold"),
        ("Gone.swift", "Gone.swift: is exempt, but is not a file this check reads"),
        ("DemoCopy.swift", "DemoCopy.swift: is exempt, but is not a file this check reads")
    ])
    func staleExemption_isAFinding(path: String, finding: String) throws {
        #expect(try Self.findings(exempting: [path: ["-x"]]) == [finding])
    }

    @Test("A previews file and a file exempted as Debug-only go unread when they are wholly inside #if DEBUG")
    func debugOnlyFile_isUnread_whenItIsDebugOnly() throws {
        let debug = """
        import SwiftUI

        #if DEBUG
            import LedgerDesign

            #Preview("Tabs") { Text("Only in Xcode") }
        #endif
        """
        let exempt = CopyAudit.Exemptions(debugOnly: ["Diagnostics.swift"])
        #expect(try Self
            .findings(extra: ["Demo+Previews.swift": debug, "Diagnostics.swift": debug], exempting: exempt) == [])
    }

    @Test("A file left unread that is not wholly inside #if DEBUG is a finding", arguments: [
        "#Preview(\"Tabs\") { Text(\"Shipped\") }",
        "#if DEBUG\n#Preview(\"Tabs\") { Text(\"x\") }\n#else\nlet title = \"Shipped\"\n#endif",
        "#if DEBUG\n#Preview(\"Tabs\") { Text(\"x\") }\n#endif\nlet title = \"Shipped\"",
        "#if DEBUG\n#endif\n#if DEBUG\n#endif\nlet title = \"Shipped\"\n#if DEBUG\n#endif"
    ])
    func unreadFile_notDebugOnly_isAFinding(source: String) throws {
        let finding = "is not wholly inside `#if DEBUG`, so it cannot go unread"
        let exempt = CopyAudit.Exemptions(debugOnly: ["Diagnostics.swift"])
        #expect(try Self.findings(extra: ["Demo+Previews.swift": source]) == ["Demo+Previews.swift: \(finding)"])
        #expect(try Self.findings(extra: ["Diagnostics.swift": source], exempting: exempt) == [
            "Diagnostics.swift: \(finding)"
        ])
    }

    @Test("A Debug-only exemption for a file the module does not have is a finding")
    func staleDebugOnlyExemption_isAFinding() throws {
        #expect(try Self.findings(exempting: CopyAudit.Exemptions(debugOnly: ["Gone.swift"])) == [
            "Gone.swift: is exempt, but is not a file this check reads"
        ])
    }

    @Test("A module whose folder is not there throws: the audit never passes on nothing")
    func missingModule_throws() {
        #expect(throws: (any Error).self) { try CopyAudit(module: "NoSuchModule") }
        #expect(throws: (any Error).self) { try CopyAudit(moduleWithoutCatalog: "NoSuchModule") }
        #expect(throws: (any Error).self) { try CopyAudit.sources(ofModule: "LedgerAppKit/NoSuchFolder") }
    }
}
