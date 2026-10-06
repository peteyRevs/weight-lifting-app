import Foundation
import LedgerTestSupport
import Testing

/// F09 S1 adversarial round 1: `CopyAudit` as the tool seven features will copy. Standards §7 is the specification:
/// what the rule forbids must be a finding, and what it allows must not be. The inputs are modules in memory
/// (`AdversarialModule`): a sound copy file and catalog, and one screen file that holds the thing under test.
@Suite("Adversarial F09 S1 · CopyAudit outside the copy files")
nonisolated struct CopyAuditAdversarialTests {
    @Test("Control: a screen that is handed its strings has no finding")
    func screen_handedItsStrings_hasNoFinding() throws {
        let screen = """
        struct Screen: View {
            let title: String

            var body: some View {
                Label(title, systemImage: "calendar").accessibilityIdentifier("today.title")
            }
        }
        """
        #expect(try AdversarialModule.findings(screen: screen).isEmpty)
    }

    @Test("A literal a lifter could read, outside the copy file, is a finding", arguments: forbiddenLiterals)
    func literalOutsideTheCopyFile_isAFinding(_ input: AdversarialInput) throws {
        let findings = try AdversarialModule.findings(screen: input.text)
        #expect(findings.contains { $0.contains("Screen.swift") }, "no finding for: \(input.text)")
    }

    @Test(
        "A literal is still found after code that could put the reader out of step, on its own line",
        arguments: lexerTraps
    )
    func literalAfterALexerTrap_isAFinding(_ input: AdversarialInput) throws {
        let findings = try AdversarialModule.findings(screen: input.text)
        let line = try #require(AdversarialModule.line(of: "Start workout", inScreen: input.text))
        #expect(findings.contains { $0.contains("Screen.swift:\(line):") }, "\(findings) for: \(input.text)")
    }

    @Test("A localized lookup outside the copy file is a finding, whatever its key", arguments: strayLookups)
    func lookupOutsideTheCopyFile_isAFinding(_ input: AdversarialInput) throws {
        let findings = try AdversarialModule.findings(screen: input.text)
        #expect(findings.contains { $0.contains("Screen.swift") }, "no finding for: \(input.text)")
    }

    @Test(
        "A literal after a name that only reads like an identifier's or a symbol's label is a finding",
        arguments: afterALookalikeLabel
    )
    func literalAfterALookalikeLabel_isAFinding(_ input: AdversarialInput) throws {
        let findings = try AdversarialModule.findings(screen: input.text)
        #expect(findings.contains { $0.contains("Screen.swift") }, "no finding for: \(input.text)")
    }

    @Test("Limit, stated in SwiftSource's comment and not in standards §7: a regex literal that holds a quote")
    func regexLiteralHoldingAQuote_hidesTheLiteralAfterIt() throws {
        let hidden = #"let view = row(/"/, "Start workout")"#
        #expect(try AdversarialModule.findings(screen: hidden).isEmpty, "the limit no longer holds: update the notes")
        let noisy = #"let view = row(matching: /"/, title: "Start workout")"#
        #expect(try !AdversarialModule.findings(screen: noisy).isEmpty, "with a letter between, something is found")
        // A regex that holds `/*` opens a comment that never closes: nothing after it in the file is read.
        let blind = "let slashes = /\\/*/\nlet view = Text(\"Start workout\")\nlet other = Text(\"Rest day\")"
        #expect(try AdversarialModule.findings(screen: blind).isEmpty, "the limit no longer holds: update the notes")
    }

    @Test("A finding names the file by its path in the module, and the literal's line")
    func finding_namesPathAndLine() throws {
        let screen = "let first = 1\n/* two\n   lines */\nlet view = Text(\"Start workout\")"
        let findings = try AdversarialModule.findings(screen: screen)
        #expect(findings.count == 1)
        #expect(findings.first?.hasPrefix("Views/Screen.swift:6:") == true, "\(findings)")
    }
}

nonisolated extension CopyAuditAdversarialTests {
    /// What standards §7 forbids outside a copy file: "no string literal in `Text(...)`, in a component's arguments
    /// or anywhere else a lifter could read it", strict by default (any literal with a letter in it).
    static let forbiddenLiterals: [AdversarialInput] = [
        AdversarialInput("Text", #"let view = Text("Start workout")"#),
        AdversarialInput("Label's title", #"let view = Label("Start workout", systemImage: "play.fill")"#),
        AdversarialInput("Button", #"let view = Button("Start workout") {}"#),
        AdversarialInput("navigationTitle", #"let view = Text(title).navigationTitle("Start workout")"#),
        AdversarialInput(
            "accessibilityLabel",
            #"let view = Image(systemName: "gearshape").accessibilityLabel("Settings")"#
        ),
        AdversarialInput("accessibilityHint", #"let view = Text(title).accessibilityHint("Opens the workout")"#),
        AdversarialInput("accessibilityValue", #"let view = Text(title).accessibilityValue("Done")"#),
        AdversarialInput("Text(verbatim:)", #"let view = Text(verbatim: "Start workout")"#),
        AdversarialInput("a multi-line literal", "let title = \"\"\"\n    Start workout\n    \"\"\""),
        AdversarialInput("a raw literal", ##"let view = Text(#"Start workout"#)"##),
        AdversarialInput("a raw literal with two pounds", ###"let view = Text(##"Start workout"##)"###),
        AdversarialInput("a raw multi-line literal", "let title = #\"\"\"\n    Start workout\n    \"\"\"#"),
        AdversarialInput("concatenation", #"let view = Text("Start" + " " + "workout")"#),
        AdversarialInput("text around an interpolation", #"let view = Text("Week \(week)")"#),
        AdversarialInput("a literal inside an interpolation", #"let view = Text("\(isDone ? "Done" : "Pending")")"#),
        AdversarialInput(
            "a literal two interpolations deep",
            #"let view = Text("\(count) \("\(isOne ? "set" : "sets")")")"#
        ),
        AdversarialInput("a file's constant", "private let title = \"Start workout\"\nlet view = Text(title)"),
        AdversarialInput("a static constant", "enum Titles {\n    static let start = \"Start workout\"\n}"),
        AdversarialInput("a default argument", #"func row(title: String = "Start workout") {}"#),
        AdversarialInput("an enum's raw value", "enum Card: String {\n    case upNext = \"Up next\"\n}"),
        AdversarialInput("a list of titles", #"let titles = ["Today", "Program", "Library", "History"]"#),
        AdversarialInput("one letter", #"let suffix = Text("k")"#),
        AdversarialInput("letters outside ASCII", #"let view = Text("Übung")"#),
        AdversarialInput("Cyrillic letters", #"let view = Text("Старт")"#),
        AdversarialInput("Han characters", #"let view = Text("開始")"#),
        AdversarialInput("letters written as escapes", #"let view = Text("\u{53}\u{74}\u{61}\u{72}\u{74}")"#),
        AdversarialInput("a wrapped argument", "let view = Text(\n    \"Start workout\"\n)"),
        AdversarialInput("a title before an identifier", #"let view = Text("Start").accessibilityIdentifier("a.b")"#),
        AdversarialInput("a region under #if DEBUG", "#if DEBUG\n    let view = Text(\"Start workout\")\n#endif"),
        AdversarialInput("the #else of #if DEBUG", "#if DEBUG\n#else\n    let view = Text(\"Start workout\")\n#endif"),
        AdversarialInput("a tab's title", #"let tab = Tab("Today", systemImage: "chart.bar.fill") { root }"#),
        AdversarialInput(
            "an alert's title",
            #"let view = Text(title).alert("Delete workout?", isPresented: $shown) {}"#
        ),
        AdversarialInput("String(format:)", #"let line = String(format: "%d sets", count)"#),
        AdversarialInput("AttributedString", #"let line = AttributedString("Start workout")"#),
        AdversarialInput(
            "a symbol's label",
            #"let view = Image(systemName: "gearshape", variableValue: 1).help("Settings")"#
        ),
        AdversarialInput("an image by asset name", #"let view = Image("Start workout")"#)
    ]

    /// Each ends with `Text("Start workout")` on a line of its own, after something a reader of text could misread.
    static let lexerTraps: [AdversarialInput] = [
        AdversarialInput("a literal holding //", "let slashes = \"//\"\nlet view = Text(\"Start workout\")"),
        AdversarialInput("// in a literal on the same line", #"let pair = ("//", Text("Start workout"))"#),
        AdversarialInput("/* in a literal on the same line", #"let pair = ("/*", Text("Start workout"))"#),
        AdversarialInput("a line comment with one quote", "// 6\" plates\nlet view = Text(\"Start workout\")"),
        AdversarialInput("a block comment with one quote", "/* 6\" */ let view = Text(\"Start workout\")"),
        AdversarialInput("a nested block comment", "/* 1 /* 2 */ \" */ let view = Text(\"Start workout\")"),
        AdversarialInput("an escaped quote", #"let pair = ("\"", Text("Start workout"))"#),
        AdversarialInput("an escaped backslash", #"let pair = ("\\", Text("Start workout"))"#),
        AdversarialInput("a quote as a scalar", #"let pair = ("\u{22}", Text("Start workout"))"#),
        AdversarialInput("a raw literal ending in a backslash", ##"let pair = (#"\"#, Text("Start workout"))"##),
        AdversarialInput("a raw literal holding a quote", ##"let pair = (#"1"2"#, Text("Start workout"))"##),
        AdversarialInput("a raw literal holding \\(", ##"let pair = (#"\("#, Text("Start workout"))"##),
        AdversarialInput("a raw interpolation", ##"let pair = (#"\#(count)"#, Text("Start workout"))"##),
        AdversarialInput(
            "a multi-line literal holding quotes",
            "let block = \"\"\"\n    1 \" 2 \"\" 3\n    \"\"\"\nlet view = Text(\"Start workout\")"
        ),
        AdversarialInput(
            "a multi-line literal with an escaped triple quote",
            "let block = \"\"\"\n    \\\"\"\"\n    \"\"\"\nlet view = Text(\"Start workout\")"
        ),
        AdversarialInput(
            "a multi-line literal with a joined line",
            "let block = \"\"\"\n    1 \\\n    2\n    \"\"\"\nlet view = Text(\"Start workout\")"
        ),
        AdversarialInput(
            "a parenthesis in an interpolation's literal",
            #"let pair = ("\(f(")"))", Text("Start workout"))"#
        ),
        AdversarialInput(
            "a closure in an interpolation",
            #"let pair = ("\(rows.map { "\($0)" }.count)", Text("Start workout"))"#
        ),
        AdversarialInput("a key path", #"let pair = (\Row.count, Text("Start workout"))"#),
        AdversarialInput("a division", "let half = total / 2\nlet view = Text(\"Start workout\") // 1 / 2"),
        AdversarialInput("CRLF line ends", "// 6\" plates\r\nlet view = Text(\"Start workout\")\r\n"),
        AdversarialInput("a curly quote", "let quote = \"\u{201C}\"\nlet view = Text(\"Start workout\")")
    ]

    /// The check knows an identifier or a symbol by the text before the quote. A value or a case that carries the
    /// same name puts that text there too.
    static let afterALookalikeLabel: [AdversarialInput] = [
        AdversarialInput(
            "a ternary whose first arm is named systemName",
            #"let view = Text(isStock ? systemName : "Custom exercise")"#
        ),
        AdversarialInput(
            "a ternary whose first arm is named identifier",
            #"let view = Text(hasCode ? identifier : "No barcode")"#
        ),
        AdversarialInput(
            "a case named identifier",
            "func label(_ field: Field) -> String {\n    switch field {\n    case .identifier: \"Barcode\"\n    }\n}"
        )
    ]

    /// Lookups whose literals have no letter (or that have no literal), so only the lookup itself can be found.
    /// Standards §7: "Views, stores, presentation builders and `LedgerDesign` components hold neither a user-facing
    /// literal nor a localized lookup."
    static let strayLookups: [AdversarialInput] = [
        AdversarialInput(
            "String(localized:) of a key handed in",
            "func title(_ key: Key) -> String {\n    String(localized: key, bundle: .module)\n}"
        ),
        AdversarialInput(
            "String(localized:) of a letterless key",
            #"let line = String(localized: "\(count)", bundle: .module)"#
        ),
        AdversarialInput(
            "String(localized:) wrapped over lines",
            "func title(_ key: Key) -> String {\n    String(\n        localized: key,\n"
                + "        bundle: .module\n    )\n}"
        ),
        AdversarialInput(
            "String.init(localized:)",
            "func title(_ key: Key) -> String {\n    String.init(localized: key)\n}"
        ),
        AdversarialInput(
            "AttributedString(localized:)",
            "func title(_ key: Key) -> AttributedString {\n    AttributedString(localized: key, bundle: .module)\n}"
        ),
        AdversarialInput(
            "a LocalizedStringKey parameter",
            "func row(_ title: LocalizedStringKey) -> Text {\n    Text(title, bundle: .module)\n}"
        ),
        AdversarialInput(
            "a LocalizedStringResource parameter",
            "func row(_ title: LocalizedStringResource) -> Text {\n    Text(title)\n}"
        ),
        AdversarialInput(
            "String.LocalizationValue",
            "func value(_ text: String) -> String.LocalizationValue {\n    .init(text)\n}"
        ),
        AdversarialInput(
            "NSLocalizedString of a key handed in",
            "func title(_ key: String) -> String {\n    NSLocalizedString(key, bundle: .module, comment: \"\")\n}"
        ),
        AdversarialInput(
            "Bundle.localizedString(forKey:)",
            "func title(_ key: String) -> String {\n"
                + "    Bundle.module.localizedString(forKey: key, value: nil, table: nil)\n}"
        ),
        AdversarialInput(
            "Bundle.localizedAttributedString(forKey:)",
            "func title(_ key: String) -> NSAttributedString {\n"
                + "    Bundle.module.localizedAttributedString(forKey: key, value: nil, table: nil)\n}"
        ),
        AdversarialInput(
            "Bundle.localizedString(forKey:) as the formatter wraps it",
            "func title(_ key: String) -> String {\n    Bundle.module.localizedString(\n        forKey: key,\n"
                + "        value: nil,\n        table: nil\n    )\n}"
        ),
        AdversarialInput(
            "a lookup inside an interpolation",
            #"func line(_ key: Key) -> String { "\(String(localized: key, bundle: .module)) · \(count)" }"#
        ),
        AdversarialInput(
            "a lookup under #if DEBUG",
            "#if DEBUG\n    func title(_ key: Key) -> String { String(localized: key) }\n#endif"
        )
    ]
}
