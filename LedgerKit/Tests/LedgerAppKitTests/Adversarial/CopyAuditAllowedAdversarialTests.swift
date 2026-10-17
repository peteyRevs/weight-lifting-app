import Foundation
import LedgerTestSupport
import Testing

/// F09 S1 adversarial round 1: what standards §7 allows outside a copy file must not be a finding (a false alarm
/// teaches seven features to exempt files), and what a file's exemption and the previews rule let through.
@Suite("Adversarial F09 S1 · CopyAudit, what the rule allows")
nonisolated struct CopyAuditAllowedAdversarialTests {
    @Test("What the rule allows outside a copy file is not a finding", arguments: allowed)
    func allowedOutsideTheCopyFile_isNoFinding(_ input: AdversarialInput) throws {
        let findings = try AdversarialModule.findings(screen: input.text)
        #expect(findings.isEmpty, "\(findings) for: \(input.text)")
    }

    @Test(
        "An identifier or a symbol's name chosen by a condition is still an identifier or a symbol's name",
        arguments: allowedByCondition
    )
    func identifierOrSymbolChosenByCondition_isNoFinding(_ input: AdversarialInput) throws {
        let findings = try AdversarialModule.findings(screen: input.text)
        #expect(findings.isEmpty, "\(findings) for: \(input.text)")
    }

    @Test(
        "Only a level call on a logger is a log line: the same call on anything else is a finding",
        arguments: notLogLines
    )
    func levelCallOnSomethingElse_isAFinding(_ input: AdversarialInput) throws {
        let findings = try AdversarialModule.findings(screen: input.text)
        #expect(findings.contains { $0.contains("Screen.swift") }, "no finding for: \(input.text)")
    }

    @Test("An exemption covers its file's literals, by the file's path in the module, and nothing else")
    func exemption_coversItsFileOnly() throws {
        let launch = #"let isUITest = arguments.contains("-LEDGER_UITEST")"#
        let reason: CopyAudit.Exemptions = ["Views/Screen.swift": ["-LEDGER_UITEST"]]
        #expect(try AdversarialModule.findings(screen: launch, exempting: reason).isEmpty)
        let elsewhere = try AdversarialModule.findings(screen: launch, at: "Sheets/Screen.swift", exempting: reason)
        #expect(elsewhere.contains { $0.contains("Sheets/Screen.swift") }, "the other Screen.swift is not exempt")
        #expect(elsewhere.count >= 2, "and the exemption that exempted nothing is a finding: \(elsewhere)")
    }

    @Test("An exemption that exempts nothing is a finding: a missing file, a file with no literal, a copy file")
    func staleExemption_isAFinding() throws {
        let clean = "let count = 1"
        let missing = try AdversarialModule.findings(screen: clean, exempting: ["Gone.swift": ["-LEDGER_UITEST"]])
        #expect(missing.count == 1, "\(missing)")
        let nothing = try AdversarialModule.findings(
            screen: clean,
            exempting: ["Views/Screen.swift": ["-LEDGER_UITEST"]]
        )
        #expect(nothing.count == 1, "\(nothing)")
        let copyFile = try AdversarialModule.findings(
            screen: clean,
            exempting: ["FixtureCopy.swift": ["Start workout"]]
        )
        #expect(!copyFile.isEmpty, "\(copyFile)")
    }

    @Test("An exemption is for literals: a localized lookup in an exempt file is still a finding")
    func exemptFile_lookupIsStillAFinding() throws {
        let screen = """
        let isUITest = arguments.contains("-LEDGER_UITEST")
        func title(_ key: Key) -> String {
            String(localized: key, bundle: .module)
        }
        """
        let findings = try AdversarialModule.findings(
            screen: screen,
            exempting: ["Views/Screen.swift": ["-LEDGER_UITEST"]]
        )
        #expect(findings.contains { $0.contains("Screen.swift") }, "\(findings)")
    }

    @Test("An exemption names literals: a title a lifter reads, in the same file, is still a finding")
    func exemption_namesLiterals_aTitleInTheFileIsStillAFinding() throws {
        let screen = """
        let isUITest = arguments.contains("-LEDGER_UITEST")
        let view = Text("Start workout")
        """
        let findings = try AdversarialModule.findings(
            screen: screen,
            exempting: ["Views/Screen.swift": ["-LEDGER_UITEST"]]
        )
        #expect(findings.count == 1, "\(findings)")
        #expect(findings.first?.hasPrefix("Views/Screen.swift:4:") == true, "\(findings)")
    }

    @Test("Limit of a check that reads literals: a title made from a name has no literal to find")
    func textMadeFromAName_hasNoLiteralToFind() throws {
        let screen = """
        enum Card: String, CaseIterable {
            case today, program
        }

        let titles = Card.allCases.map { Text($0.rawValue.capitalized) }
        """
        #expect(try AdversarialModule.findings(screen: screen).isEmpty, "the limit no longer holds: update the notes")
        let interpolated = #"let other = Text("\(Card.today)")"#
        #expect(
            try !AdversarialModule.findings(screen: interpolated).isEmpty,
            "a literal handed to Text is a finding, with letters or without"
        )
    }

    @Test("A module that is not there, or has no catalog, throws: the audit never passes on nothing")
    func moduleWithoutACatalog_throws() {
        #expect(throws: (any Error).self) { try CopyAudit(module: "NoSuchModule") }
        #expect(throws: (any Error).self) { try CopyAudit(module: "LedgerDomain") }
        #expect(throws: (any Error).self) { try StringCatalog(module: "LedgerDesign") }
    }

    @Test("A `+Previews.swift` file is not read, and a file that only ends in Previews is")
    func previewsFile_isNotRead_othersAre() throws {
        let bare = #"#Preview("Up next") { Text("Start workout") }"#
        let preview = "#if DEBUG\n\(bare)\n#endif"
        #expect(try AdversarialModule.findings(screen: preview, at: "Today+Previews.swift").isEmpty)
        #expect(try AdversarialModule.findings(screen: preview, at: "Views/Today+Previews.swift").isEmpty)
        #expect(try !AdversarialModule.findings(screen: preview, at: "TodayPreviews.swift").isEmpty)
        #expect(
            try !AdversarialModule.findings(screen: bare, at: "Today+Previews.swift").isEmpty,
            "a previews file that is not inside #if DEBUG ships, so it is not left unread"
        )
    }
}

nonisolated extension CopyAuditAllowedAdversarialTests {
    /// Standards §7, "The check": an accessibility identifier, an SF Symbol's name and a log line are not copy; a
    /// literal without a letter is not copy; a comment is not code.
    static let allowed: [AdversarialInput] = [
        AdversarialInput(
            "an accessibility identifier",
            #"let view = Text(title).accessibilityIdentifier("today.title")"#
        ),
        AdversarialInput(
            "an identifier with an index",
            #"let view = Text(title).accessibilityIdentifier("workout.active.setRow.\(index)")"#
        ),
        AdversarialInput(
            "an identifier wrapped",
            "let view = Text(title).accessibilityIdentifier(\n    \"today.title\"\n)"
        ),
        AdversarialInput(
            "an identifier: argument",
            #"let view = PlaceholderScreen(title, identifier: "program.title")"#
        ),
        AdversarialInput(
            "an …Identifier: argument",
            #"let view = Row(title, accessibilityIdentifier: "today.recent.row")"#
        ),
        AdversarialInput("systemImage:", #"let view = Label(title, systemImage: "calendar")"#),
        AdversarialInput("systemName:", #"let view = Image(systemName: "gearshape")"#),
        AdversarialInput("a log line", #"func note() { logger.error("The database could not be opened: \(error)") }"#),
        AdversarialInput(
            "a log line on a logger a value holds",
            #"func note() { environment.logger.log.fault("Seeding failed") }"#
        ),
        AdversarialInput(
            "a log line on self's logger",
            #"func note() { self.logger.info("Launched in \(milliseconds) ms") }"#
        ),
        AdversarialInput(
            "a log line wrapped",
            "func note() {\n    logger.debug(\n        \"Resumed in \\(phase)\"\n    )\n}"
        ),
        AdversarialInput(
            "a log line that mentions a lookup",
            #"func note() { logger.debug("NSLocalizedString(key) localized: x") }"#
        ),
        AdversarialInput("a separator", #"let line = [first, second].joined(separator: " · ")"#),
        AdversarialInput("a separator between interpolations", #"let line = "\(first) · \(second)""#),
        AdversarialInput("a clock format without letters", #"let clock = "\(minutes):\(seconds)""#),
        AdversarialInput("an empty literal", #"let none = """#),
        AdversarialInput("digits", #"let zero = "0""#),
        AdversarialInput("a dash", "let dash = \"\u{2014}\""),
        AdversarialInput("a percent", #"let delta = "+\(percent)%""#),
        AdversarialInput("a multiplication sign", "let times = \"\\(sets) \u{D7} \\(reps)\""),
        AdversarialInput("a multi-line literal without letters", "let rule = \"\"\"\n    ---\n    \"\"\""),
        AdversarialInput("a raw literal without letters", ##"let slash = #"\"#"##),
        AdversarialInput("a comment that holds a literal", "// Text(\"Start workout\")\nlet count = 1"),
        AdversarialInput(
            "a doc comment that holds a lookup",
            "/// `String(localized: \"Start workout\", bundle: .module)`\nlet count = 1"
        ),
        AdversarialInput(
            "a block comment that holds a lookup",
            "/* NSLocalizedString(\"Start workout\") */ let count = 1"
        ),
        AdversarialInput(
            "a nested block comment",
            "/* 1 /* Text(\"Start\") */ LocalizedStringKey(\"x\") */ let count = 1"
        ),
        AdversarialInput("a comment after code", "let count = 1 // \"Start workout\" LocalizedStringKey localized:"),
        AdversarialInput("a comment after a literal holding //", "let slashes = \"//\" // Text(\"Start workout\")"),
        AdversarialInput(
            "sorting by localized order",
            "let rows = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }"
        ),
        AdversarialInput(
            "a localized search",
            "let hits = names.filter { $0.localizedCaseInsensitiveContains(query) }"
        ),
        AdversarialInput(
            "an error's localizedDescription in a log line",
            #"func note() { logger.error("\(error.localizedDescription)") }"#
        )
    ]

    /// The rule names the identifier and the symbol by where they stand. A feature picks one of two by a condition
    /// often (a done and a pending symbol; `today.strip.today` or `.day`): these are still not copy.
    static let allowedByCondition: [AdversarialInput] = [
        AdversarialInput(
            "a symbol by a ternary",
            #"let view = Image(systemName: isDone ? "checkmark.circle" : "circle")"#
        ),
        AdversarialInput(
            "a systemImage by a ternary",
            #"let view = Label(title, systemImage: isLive ? "pause.fill" : "play.fill")"#
        ),
        AdversarialInput(
            "an identifier by a ternary",
            #"let view = Text(title).accessibilityIdentifier(isToday ? "strip.today" : "strip.day")"#
        ),
        AdversarialInput(
            "an identifier with a chosen part",
            #"let view = Text(title).accessibilityIdentifier("strip.\(isToday ? "today" : "day")")"#
        )
    ]

    /// `error(`, `info(` and the like on something that is not a logger show their text to the lifter.
    static let notLogLines: [AdversarialInput] = [
        AdversarialInput("a banner's error", #"let view = banner.error("Couldn't save your set")"#),
        AdversarialInput("a static factory named error", #"let view = EmptyState.error("Couldn't load your history")"#),
        AdversarialInput("a toast's notice", #"func saved() { toast.notice("Saved") }"#),
        AdversarialInput("a free function named error", #"let view = error("Couldn't save your set")"#),
        AdversarialInput("print", #"func note() { print("Start workout") }"#)
    ]
}
