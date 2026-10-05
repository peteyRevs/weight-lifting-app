import Foundation
import LedgerTestSupport
import Testing

/// F09 S1 close-out (G2 round 2): the rewritten `CopyAudit` against standards §7 as fix round 1 left it, with inputs
/// round 1 did not use, for the findings the rewrite set out to close: F9-S1-2, -3, -5, -6, -7 and -10, and the rule
/// that no English text names the product.
@Suite("Adversarial F09 S1 close-out · CopyAudit")
nonisolated struct CopyAuditCloseOutAdversarialTests {
    typealias Catalog = AdversarialCatalog
    typealias Copy = CopyFileAdversarialTests

    static let start = Catalog.plain("Start workout")

    @Test(
        "F9-S1-2: a lookup inside an interpolation is a finding, however deep and whatever holds it",
        arguments: nested
    )
    func nestedLookup_isAFinding(_ input: AdversarialInput) throws {
        let findings = try AdversarialModule.findings(copy: input.text, catalog: [Self.start])
        #expect(findings.contains { $0.contains("FixtureCopy.swift") }, "no finding for: \(input.text)")
    }

    @Test("F9-S1-3: a key that carries a value, a number or a text, takes a locale", arguments: withoutLocale)
    func valueWithoutALocale_isAFinding(_ input: AdversarialInput) throws {
        let keys = ["%lld sets", "Next: %@"].map { Catalog.plain($0) }
        let withLocale = Copy.counted("_ day: String", #""Next: \(day)""#)
        #expect(try AdversarialModule.findings(copy: withLocale, catalog: keys).isEmpty, "control: with a locale")
        let findings = try AdversarialModule.findings(copy: input.text, catalog: keys)
        #expect(findings.contains { $0.contains("FixtureCopy.swift") }, "no finding for: \(input.text)")
    }

    /// Standards §7: "The caller passes the injected `@Dependency(\.locale)`", because a lookup that takes its
    /// locale from the device is one "a test cannot fix". A member that writes `locale: .current` is that lookup
    /// with the argument filled in. The audit reads no further than `locale:`, and "Known limits" does not say so.
    @Test("Limit, not in standards §7: a locale written into the member, not handed in, passes", arguments: [
        ".current", "Locale.current", ".autoupdatingCurrent"
    ])
    func limit_localeWrittenIntoTheMember(locale: String) throws {
        let member = Copy.member(
            "_ count: Int",
            "String(localized: \"\\(count) sets\", bundle: .module, locale: \(locale))"
        )
        let findings = try AdversarialModule.findings(copy: member, catalog: [Catalog.plain("%lld sets")])
        #expect(findings.isEmpty, "the limit no longer holds: update the findings and standards §7")
    }

    @Test("F9-S1-5: an allowed label covers every literal of its argument's expression", arguments: covered)
    func literalUnderAnAllowedLabel_isNoFinding(_ input: AdversarialInput) throws {
        let findings = try AdversarialModule.findings(screen: input.text)
        #expect(findings.isEmpty, "\(findings) for: \(input.text)")
    }

    @Test(
        "F9-S1-6: a name that only reads like a label, or a label that has ended, covers nothing",
        arguments: lookalikes
    )
    func literalAfterALookalike_isAFinding(_ input: AdversarialInput) throws {
        let findings = try AdversarialModule.findings(screen: input.text)
        #expect(findings.contains { $0.contains("Screen.swift") }, "no finding for: \(input.text)")
    }

    @Test(
        "F9-S1-7: a lookup outside the copy files is a finding however it is wrapped, a letterless Text too",
        arguments: lookups
    )
    func lookupOutsideTheCopyFiles_isAFinding(_ input: AdversarialInput) throws {
        let findings = try AdversarialModule.findings(screen: input.text)
        #expect(findings.contains { $0.contains("Screen.swift") }, "no finding for: \(input.text)")
    }

    @Test("F9-S1-10: an exemption never covers a literal handed to Text, though it reads the same")
    func exemption_neverCoversALiteralHandedToText() throws {
        let screen = "let isUITest = arguments.contains(\"-LEDGER_UITEST\")\nlet view = Text(\"-LEDGER_UITEST\")"
        let findings = try AdversarialModule.findings(
            screen: screen,
            exempting: ["Views/Screen.swift": ["-LEDGER_UITEST"]]
        )
        #expect(findings.count == 1, "\(findings)")
        #expect(findings.first?.hasPrefix("Views/Screen.swift:4:") == true, "\(findings)")
    }

    @Test(
        "F9-S1-10: a file exempted as Debug-only goes unread only when all of it is inside #if DEBUG",
        arguments: shipped
    )
    func debugOnlyFileThatShips_isAFinding(_ input: AdversarialInput) throws {
        let exemptions = CopyAudit.Exemptions(debugOnly: ["Views/Screen.swift"])
        let whole = "#if DEBUG\n    #if os(iOS)\n        let view = Text(\"Start workout\")\n    #else\n"
            + "        let view = Text(\"Rest day\")\n    #endif\n#endif"
        #expect(try AdversarialModule.findings(screen: whole, exempting: exemptions).isEmpty, "control: all inside")
        let findings = try AdversarialModule.findings(screen: input.text, exempting: exemptions)
        #expect(findings.contains { $0.contains("Screen.swift") }, "no finding for: \(input.text)")
    }

    @Test("The product's name in a key or in any English form is a problem, in any case; in a comment it is not")
    func productName_isAProblemInEveryEnglishText() throws {
        #expect(try !Catalog.problems([Catalog.plain("Open the ledger")]).isEmpty)
        #expect(try !Catalog.problems([Catalog.plain("LEDGER tries again")]).isEmpty)
        let counted = Catalog.plural("%lld sets", ["one": "%lld Ledger set", "other": "%lld sets"])
        #expect(try !Catalog.problems([counted]).isEmpty)
        let commented = "\"Today\" : { \"comment\" : \"The tab Ledger opens on\", "
            + "\"localizations\" : { \"en\" : \(Catalog.unit("Today")) } }"
        #expect(try Catalog.problems([commented]).isEmpty, "a translator's comment is not shipped copy")
        #expect(try Catalog.problems([Catalog.plain("Knowledge base")]).isEmpty, "a word that only starts like it")
    }
}

nonisolated extension CopyAuditCloseOutAdversarialTests {
    static let lookup = #"String(localized: "Start workout", bundle: .module)"#

    static let nested: [AdversarialInput] = [
        AdversarialInput(
            "two interpolations deep",
            Copy.member("_ reps: String", "\"\\(\"\\(\(lookup))\") · \\(reps)\"")
        ),
        AdversarialInput("inside a call in the interpolation", Copy.row("pad(\(lookup))")),
        AdversarialInput(
            "in a multi-line literal",
            Copy.member("_ reps: String", "\"\"\"\n        \\(\(lookup)) · \\(reps)\n        \"\"\"")
        ),
        AdversarialInput(
            "inside the timer form",
            Copy.member(
                "_ start: Date",
                "Text(\"\\(\(lookup)) · \\(timerInterval: start ... .distantFuture)\", bundle: .module)",
                returning: "Text"
            )
        )
    ]

    static let withoutLocale: [AdversarialInput] = [
        AdversarialInput("a text", Copy.lookup("_ day: String", #""Next: \(day)""#)),
        AdversarialInput(
            "a number, with a comment",
            Copy.lookup("_ count: Int", #""\(count) sets""#, #", comment: "A count""#)
        ),
        AdversarialInput(
            "a number, wrapped over lines",
            Copy.member(
                "_ count: Int",
                "String(\n        localized: \"\\(count) sets\",\n        bundle: .module\n    )"
            )
        )
    ]

    static let covered: [AdversarialInput] = [
        AdversarialInput("a symbol or a fallback", #"let view = Image(systemName: symbol ?? "circle")"#),
        AdversarialInput(
            "a symbol picked from a list",
            #"let view = Image(systemName: ["circle", "checkmark.circle"][state])"#
        ),
        AdversarialInput(
            "a symbol by two conditions",
            #"let view = Label(title, systemImage: isRest ? "bed.double" : isDone ? "checkmark.circle" : "circle")"#
        ),
        AdversarialInput(
            "a symbol by a condition, wrapped",
            "let view = Label(\n    title,\n    systemImage: isLive\n"
                + "        ? \"pause.fill\"\n        : \"play.fill\"\n)"
        ),
        AdversarialInput(
            "an identifier by a condition, at the end of a chain",
            #"let view = Text(title).padding().accessibilityIdentifier(isToday ? "strip.today" : "strip.day")"#
        ),
        AdversarialInput(
            "an identifier with a chosen part, under a label",
            #"let row = Row(title, accessibilityIdentifier: "today.recent.row.\(isFirst ? "first" : "rest")")"#
        ),
        AdversarialInput(
            "a log line with a chosen part",
            #"func note() { logger.error("Seeding failed: \(isRetry ? "again" : "at first")") }"#
        ),
        AdversarialInput(
            "a logger's category",
            #"let logger = LedgerLogger(category: isWatch ? "watch.launch" : "launch")"#
        )
    ]

    static let lookalikes: [AdversarialInput] = [
        AdversarialInput("an arm named systemImage", #"let view = Text(isStock ? systemImage : "Custom exercise")"#),
        AdversarialInput(
            "an arm named identifier, under another label",
            #"let row = Row(title: hasCode ? identifier : "No barcode")"#
        ),
        AdversarialInput("an arm named category", #"let view = Text(isPush ? category : "Push day")"#),
        AdversarialInput("a dictionary's key named identifier", #"let names = [identifier: "Barcode"]"#),
        AdversarialInput("an arm in parentheses", #"let name = (hasCode ? identifier : "No barcode")"#),
        AdversarialInput(
            "cases named systemName and category",
            "func label(_ field: Field) -> String {\n    switch field {\n    case .systemName: \"Symbol\"\n"
                + "    case .category: \"Push day\"\n    }\n}"
        ),
        AdversarialInput("the argument after an identifier", #"let row = Row(identifier: id, title: "Start workout")"#),
        AdversarialInput(
            "an unlabelled argument after an identifier",
            #"let row = Row(identifier: id, "Start workout")"#
        ),
        AdversarialInput(
            "a modifier after a symbol",
            #"let view = Image(systemName: name).accessibilityLabel("Settings")"#
        ),
        AdversarialInput(
            "a closure after a symbol",
            #"let view = Button(action: start) { Label("Start", systemImage: "play.fill") }"#
        ),
        AdversarialInput(
            "the second argument of a level call",
            #"func note() { logger.error("\(code)", "Couldn't save") }"#
        )
    ]

    static let lookups: [AdversarialInput] = [
        AdversarialInput(
            "localizedString(forKey:) wrapped after the bundle and after the parenthesis",
            "func title(_ key: String) -> String {\n    Bundle.module\n        .localizedString(\n"
                + "            forKey: key,\n"
                + "            value: nil,\n            table: nil\n        )\n}"
        ),
        AdversarialInput(
            "localizedAttributedString(forKey:) wrapped",
            "func title(_ key: String) -> NSAttributedString {\n    Bundle.module.localizedAttributedString(\n"
                + "        forKey: key,\n        value: nil,\n        table: nil\n    )\n}"
        ),
        AdversarialInput(
            "a comment between the parenthesis and forKey:",
            "func title(_ key: String) -> String {\n    Bundle.module.localizedString( // the key\n"
                + "        forKey: key, value: nil, table: nil)\n}"
        ),
        AdversarialInput(
            "localized and its colon on two lines",
            "func title(_ key: Key) -> String {\n    String(\n        localized\n        : key\n    )\n}"
        ),
        AdversarialInput(
            ".init(localized:)",
            "func title(_ key: Key) -> String {\n    .init(localized: key, bundle: .module)\n}"
        ),
        AdversarialInput(
            "a lookup inside a log line's interpolation",
            #"func note(_ key: String) { logger.debug("\(NSLocalizedString(key, comment: ""))") }"#
        ),
        AdversarialInput("a number handed to Text", #"let view = Text("\(count)")"#),
        AdversarialInput("a ratio handed to SwiftUI.Text", #"let view = SwiftUI.Text("\(done)/\(total)")"#),
        AdversarialInput("a number handed to Text, wrapped", "let view = Text(\n    \"\\(count)\"\n)")
    ]

    /// Each ships a title in a file the module exempts as Debug-only.
    static let shipped: [AdversarialInput] = [
        AdversarialInput(
            "an #else",
            "#if DEBUG\n    let view = Text(\"Preview\")\n#else\n    let view = Text(\"Start workout\")\n#endif"
        ),
        AdversarialInput("an #elseif", "#if DEBUG\n#elseif os(iOS)\n    let view = Text(\"Start workout\")\n#endif"),
        AdversarialInput(
            "a wider condition",
            "#if DEBUG || targetEnvironment(simulator)\n    let view = Text(\"Start workout\")\n#endif"
        ),
        AdversarialInput("the opposite condition", "#if !DEBUG\n    let view = Text(\"Start workout\")\n#endif"),
        AdversarialInput(
            "code after the #endif",
            "#if DEBUG\n    let preview = 1\n#endif\nlet view = Text(\"Start workout\")"
        ),
        AdversarialInput(
            "code between two regions",
            "#if DEBUG\n    let first = 1\n#endif\nlet view = Text(\"Start workout\")\n"
                + "#if DEBUG\n    let second = 2\n#endif"
        ),
        AdversarialInput(
            "code before the #if",
            "let view = Text(\"Start workout\")\n#if DEBUG\n    let preview = 1\n#endif"
        ),
        AdversarialInput("no #if at all", "let view = Text(\"Start workout\")")
    ]
}
