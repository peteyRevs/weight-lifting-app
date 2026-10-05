import Foundation
import LedgerTestSupport
import Testing

/// F09 S1 adversarial round 1: `CopyAudit` inside a copy file. Standards §7: "A lookup is always written
/// `String(localized: "…", bundle: .module)`, with `locale:` … and `comment:` … A copy file holds nothing but such
/// lookups, each with a literal key." The catalog of each case holds the keys a right reading of the file gives, so
/// a finding can only be about the lookup's form.
@Suite("Adversarial F09 S1 · CopyAudit inside a copy file")
nonisolated struct CopyFileAdversarialTests {
    typealias Catalog = AdversarialCatalog

    static let start = Catalog.plain("Start workout")

    @Test("A lookup that is not written as the rule writes it is a finding", arguments: wrongLookups)
    func lookupNotWrittenAsTheRule_isAFinding(_ input: AdversarialInput) throws {
        let findings = try AdversarialModule.findings(copy: input.text, catalog: [Self.start])
        #expect(findings.contains { $0.contains("FixtureCopy.swift") }, "no finding for: \(input.text)")
    }

    @Test(
        "An interpolation that is not a bare Int or String parameter of its member is a finding",
        arguments: wrongValues
    )
    func interpolationNotABareParameter_isAFinding(_ input: AdversarialInput) throws {
        let keys = ["Week %lld", "%lld weeks", "%lf lb moved", "%lld sets", "%@ sets", "%@ now", "Week %@"]
        let findings = try AdversarialModule.findings(copy: input.text, catalog: keys.map { Catalog.plain($0) })
        #expect(findings.contains { $0.contains("FixtureCopy.swift") }, "no finding for: \(input.text)")
    }

    @Test("A lookup written as the rule writes it has no finding", arguments: rightLookups)
    func lookupWrittenAsTheRule_hasNoFinding(_ input: AdversarialInput) throws {
        let keys = ["Start workout", "Week %lld of %lld", "Next: %@ · %@", "%lld reps", "%@ sets", "Rest day"]
        let findings = try AdversarialModule.findings(copy: input.text, catalog: keys.map { Catalog.plain($0) })
        let aboutTheFile = findings.filter { !$0.hasPrefix("Localizable.xcstrings") }
        #expect(aboutTheFile.isEmpty, "\(aboutTheFile) for: \(input.text)")
    }

    @Test("A lookup inside another literal's interpolation is held to the same form", arguments: nestedWrongLookups)
    func nestedLookupNotWrittenAsTheRule_isAFinding(_ input: AdversarialInput) throws {
        let right = Self.row(#"String(localized: "Start workout", bundle: .module)"#)
        #expect(try AdversarialModule.findings(copy: right, catalog: [Self.start]).isEmpty, "control: the right form")
        let findings = try AdversarialModule.findings(copy: input.text, catalog: [Self.start])
        #expect(findings.contains { $0.contains("FixtureCopy.swift") }, "no finding for: \(input.text)")
    }

    @Test("A parameter's type decides the specifier: an Int against a %@ key, or a String against %lld, is a finding")
    func parameterType_decidesTheSpecifier() throws {
        let asInt = Self.counted("_ count: Int", #""\(count) sets""#)
        let asString = Self.lookup("_ count: String", #""\(count) sets""#)
        let text = [Catalog.plain("%@ sets")]
        let number = [Catalog.plain("%lld sets")]
        #expect(try AdversarialModule.findings(copy: asInt, catalog: text).count == 2)
        #expect(try AdversarialModule.findings(copy: asString, catalog: number).count == 2)
        #expect(try AdversarialModule.findings(copy: asInt, catalog: number).isEmpty)
        #expect(try AdversarialModule.findings(copy: asString, catalog: text).isEmpty)
    }

    @Test("The rule lets a member return a Text built from looked-up Strings and a live view: that has no finding")
    func textMember_builtFromLookupsAndAView_hasNoFinding() throws {
        let joined = """
        static func resume(_ elapsed: Text) -> Text {
            Text(String(localized: "Resume", bundle: .module)) + Text(verbatim: " · ") + elapsed
        }
        """
        let findings = try AdversarialModule.findings(copy: joined, catalog: [Catalog.plain("Resume")])
        #expect(findings.isEmpty, "\(findings)")
    }

    @Test("A lookup in a comment is not a lookup: its key stays a key no copy file looks up")
    func lookupInAComment_isNotALookup() throws {
        let commented = "// String(localized: \"Start workout\", bundle: .module)\nstatic let count = 1"
        let findings = try AdversarialModule.findings(copy: commented, catalog: [Self.start])
        #expect(findings.count == 1, "\(findings)")
        #expect(findings.first?.hasPrefix("Localizable.xcstrings") == true, "\(findings)")
    }

    @Test("A second copy file is read as one; a file whose name only ends in Copy must hold lookups alone")
    func secondCopyFile_isReadAsOne() throws {
        let catalog = try Catalog.catalog([Self.start, Catalog.plain("Rest day")])
        let rest = #"static var rest: String { String(localized: "Rest day", bundle: .module) }"#
        let split = [
            AdversarialModule.copyPath: AdversarialModule.copy,
            "Copy/FixtureCopy+Rest.swift": "extension FixtureCopy {\n    \(rest)\n}\n"
        ]
        #expect(CopyAudit(sources: split, catalog: catalog).findings.isEmpty)
        let view = "import SwiftUI\n\nstruct HardCopy: View {\n    var body: some View { Text(\"Rest day\") }\n}\n"
        let sneaky = [AdversarialModule.copyPath: AdversarialModule.copy, "HardCopy.swift": view]
        #expect(CopyAudit(sources: sneaky, catalog: catalog).findings.contains { $0.contains("HardCopy.swift") })
    }

    @Test("Shipped copy never contains the product name (standards §7, product decisions, Naming): a finding")
    func productNameInTheCatalog_isAFinding() throws {
        let key = "Ledger tries again when you come back to it."
        let findings = try AdversarialModule.findings(
            copy: Self.lookup("", "\"\(key)\""),
            catalog: [Catalog.plain(key)]
        )
        #expect(!findings.isEmpty, "the audit passed copy that names the product")
    }

    @Test("A key the source spells with a composed letter and the catalog with a combining mark is not the same key")
    func composedAndDecomposedKeys_areNotTheSameKey() throws {
        let composed = "Caf\u{E9} stop"
        let decomposed = "Cafe\u{301} stop"
        #expect(!(composed as NSString).isEqual(to: decomposed), "control: a strings table tells the two apart")
        let member = Self.lookup("", "\"\(composed)\"")
        let findings = try AdversarialModule.findings(copy: member, catalog: [Catalog.plain(decomposed)])
        #expect(!findings.isEmpty, "the lookup misses its entry at run time, and the audit says they agree")
    }
}

nonisolated extension CopyFileAdversarialTests {
    /// `static func line(<parameters>) -> String { <body> }`, as a copy file writes a member.
    static func member(_ parameters: String, _ body: String, returning type: String = "String") -> String {
        "static func line(\(parameters)) -> \(type) {\n    \(body)\n}"
    }

    /// A member whose body is the rule's lookup of `literal` (a literal as written, quotes included).
    static func lookup(_ parameters: String, _ literal: String, _ more: String = "") -> String {
        member(parameters, "String(localized: \(literal), bundle: .module\(more))")
    }

    /// `lookup` for a key that formats a number: the member takes the locale and hands it on (standards §7).
    static func counted(_ parameters: String, _ literal: String, _ more: String = "") -> String {
        lookup("\(parameters), locale: Locale", literal, ", locale: locale\(more)")
    }

    /// A member that joins `first`, an expression, to a value with " · " (standards §7: "Two counts are two keys,
    /// joined with \" · \"").
    static func row(_ first: String, parameters: String = "_ reps: String") -> String {
        member(parameters, "\"\\(\(first)) · \\(reps)\"")
    }

    static let wrongLookups: [AdversarialInput] = [
        AdversarialInput("no bundle", member("", #"String(localized: "Start workout")"#)),
        AdversarialInput("the main bundle", member("", #"String(localized: "Start workout", bundle: .main)"#)),
        AdversarialInput(
            "another table",
            member("_ table: String", #"String(localized: "Start workout", table: table, bundle: .module)"#)
        ),
        AdversarialInput(
            "a default value",
            member("", "String(localized: \"Start workout\", defaultValue: \"\u{2014}\", bundle: .module)")
        ),
        AdversarialInput(
            "a key handed in",
            member("_ key: String.LocalizationValue", "String(localized: key, bundle: .module)")
        ),
        AdversarialInput(
            "a key from a raw value",
            member("_ tab: Tab", "String(localized: String.LocalizationValue(tab.rawValue), bundle: .module)")
        ),
        AdversarialInput(
            "NSLocalizedString",
            member("", #"NSLocalizedString("Start workout", bundle: .module, comment: "")"#)
        ),
        AdversarialInput(
            "Bundle.localizedString",
            member("", #"Bundle.module.localizedString(forKey: "Start workout", value: nil, table: nil)"#)
        ),
        AdversarialInput(
            "a Text's own lookup",
            member("", #"Text("Start workout", bundle: .module)"#, returning: "Text")
        ),
        AdversarialInput(
            "a LocalizedStringResource",
            member(
                "",
                #"LocalizedStringResource("Start workout", bundle: .main)"#,
                returning: "LocalizedStringResource"
            )
        ),
        AdversarialInput("a literal returned as it is", member("", #""Start workout""#)),
        AdversarialInput(
            "a constant beside the lookups",
            lookup("", #""Start workout""#) + "\nstatic let joiner = \"and\""
        ),
        AdversarialInput(
            "a multi-line key",
            member("", "String(localized: \"\"\"\n        Start workout\n        \"\"\", bundle: .module)")
        )
    ]

    /// Two lookups joined in the copy file, one of them not written as the rule writes it.
    static let nestedWrongLookups: [AdversarialInput] = [
        AdversarialInput("no bundle", row(#"String(localized: "Start workout")"#)),
        AdversarialInput("the main bundle", row(#"String(localized: "Start workout", bundle: .main)"#)),
        AdversarialInput(
            "a key handed in",
            row("String(localized: key, bundle: .module)", parameters: "_ key: Key, _ reps: String")
                + "\nstatic var start: String { String(localized: \"Start workout\", bundle: .module) }"
        )
    ]

    static let wrongValues: [AdversarialInput] = [
        AdversarialInput("an expression", lookup("_ week: Int", #""Week \(week + 1)""#)),
        AdversarialInput(
            "a property, not a parameter",
            "static let total = 8\n" + lookup("", #""\(total) weeks""#)
        ),
        AdversarialInput(
            "another member's parameter",
            "static func week(_ week: Int) -> String {\n    String(localized: \"Week \\(week)\", bundle: .module)\n}\n"
                + "static var weeks: String {\n    String(localized: \"\\(week) weeks\", bundle: .module)\n}"
        ),
        AdversarialInput("a Double", lookup("_ value: Double", #""\(value) lb moved""#)),
        AdversarialInput("an optional Int", lookup("_ count: Int?", #""\(count) sets""#)),
        AdversarialInput("an Int64", lookup("_ count: Int64", #""\(count) sets""#)),
        AdversarialInput("a Substring", lookup("_ count: Substring", #""\(count) sets""#)),
        AdversarialInput("a formatted value", lookup("_ count: Int", #""\(count, format: .number) sets""#)),
        AdversarialInput("a method call", lookup("_ count: String", #""\(count.uppercased()) sets""#)),
        AdversarialInput(
            "a lookup inside the key",
            lookup("", #""\(String(localized: "Start workout", bundle: .module)) now""#)
        ),
        AdversarialInput(
            "a parameter of a type the check does not know",
            lookup("_ week: some BinaryInteger", #""Week \(week)""#)
        )
    ]

    static let rightLookups: [AdversarialInput] = [
        AdversarialInput(
            "on one line",
            #"static var start: String { String(localized: "Start workout", bundle: .module) }"#
        ),
        AdversarialInput("with a comment", lookup("", #""Start workout""#, #", comment: "The up-next card's button""#)),
        AdversarialInput("with a locale", counted("_ count: Int", #""\(count) reps""#)),
        AdversarialInput(
            "with a locale and a comment",
            counted("_ count: Int", #""\(count) reps""#, #", comment: "A set's reps""#)
        ),
        AdversarialInput(
            "wrapped over lines",
            member("", "String(\n        localized: \"Start workout\",\n        bundle: .module\n    )")
        ),
        AdversarialInput(
            "two Int parameters with labels",
            counted("_ week: Int, of total: Int", #""Week \(week) of \(total)""#)
        ),
        AdversarialInput(
            "two String parameters, one with a default",
            lookup(#"_ weekday: String, tag: String = """#, #""Next: \(weekday) · \(tag)""#)
        ),
        AdversarialInput(
            "parameters wrapped over lines",
            counted("\n    _ week: Int,\n    of total: Int", #""Week \(week) of \(total)""#)
        ),
        AdversarialInput(
            "one lookup per case",
            member(
                "_ isRest: Bool",
                "switch isRest {\n    case true: String(localized: \"Rest day\", bundle: .module)\n"
                    + "    case false: String(localized: \"Start workout\", bundle: .module)\n    }"
            )
        ),
        AdversarialInput(
            "one name, two types, two members",
            counted("_ count: Int", #""\(count) reps""#) + "\n\n"
                + lookup("_ count: String", #""\(count) sets""#).replacingOccurrences(of: "line(", with: "sets(")
        ),
        AdversarialInput(
            "a doc comment that quotes a lookup",
            "/// Like `String(localized: \"Today\")` or \"Up next\".\n" + lookup("", #""Start workout""#)
        )
    ]
}
