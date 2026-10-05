import Foundation
import LedgerTestSupport
import Testing

/// `StringCatalog` (LedgerTestSupport): the rules standards §7 sets for a module's catalog, each broken once.
@Suite("StringCatalog")
struct StringCatalogTests {
    @Test("A catalog of plain keys and a counted key that follows the rules has no problems")
    func soundCatalog_hasNoProblems() throws {
        let catalog = try TestCatalog.make([
            "Today": .text("Today"),
            "Week %lld of %lld": .text("Week %lld of %lld"),
            "%lld exercises": .counted(["one": "%lld exercise", "other": "%lld exercises"]),
            "%lld of %@": .counted(["one": "%lld of %@", "other": "%lld of %@"])
        ])
        #expect(catalog.problems == [])
        #expect(catalog.keys == ["Today", "Week %lld of %lld", "%lld exercises", "%lld of %@"])
    }

    @Test("Each broken rule is reported, naming the key", arguments: BrokenRule.all)
    func brokenRule_isReported(_ rule: BrokenRule) throws {
        let catalog = try TestCatalog.make(sourceLanguage: rule.sourceLanguage, [rule.key: rule.entry])
        #expect(catalog.problems == rule.problems)
    }

    @Test("Problems come in key order, so a failure reads the same on every run")
    func problems_areInKeyOrder() throws {
        let catalog = try TestCatalog.make(["b": .empty, "a": .empty, "c": .empty])
        #expect(catalog.problems.map { $0.prefix(3) } == ["\"a\"", "\"b\"", "\"c\""])
    }

    @Test("Format specifiers are read in order, without their positions; a doubled percent sign is text")
    func specifiers_areReadInOrder() {
        #expect(StringCatalog.specifiers(in: "Week %lld of %lld · ~%lld min") == ["%lld", "%lld", "%lld"])
        #expect(StringCatalog.specifiers(in: "%2$@ · %1$lld") == ["%@", "%lld"])
        #expect(StringCatalog.specifiers(in: "100%% of %d, %lf and %@") == ["%d", "%lf", "%@"])
        #expect(StringCatalog.specifiers(in: "No specifier, 50 % off") == [])
    }

    @Test(
        "The specifiers a key may not hold are every one but %lld and %@; a percent sign that formats nothing is text"
    )
    func otherSpecifiers_areEveryOneButWholeNumbersAndTexts() {
        #expect(StringCatalog.otherSpecifiers(in: "Week %lld of %lld · %@ · %1$@ of %2$lld · %lld%% · 100% done") == [])
        #expect(StringCatalog.otherSpecifiers(in: "%lf, %d, %ld, %llu, %f, %s, %i") == [
            "%lf", "%d", "%ld", "%llu", "%f", "%s", "%i"
        ])
        #expect(StringCatalog.otherSpecifiers(in: "%.1f kg · %05.2f · %2$d · %-8s") == ["%.1f", "%05.2f", "%d", "%-8s"])
        #expect(
            StringCatalog.otherSpecifiers(in: "%%lf · %%%lf · %lldx") == ["%lf"],
            "an escaped sign, then a real one"
        )
    }

    @Test("A file that is not a catalog throws")
    func notACatalog_throws() {
        #expect(throws: (any Error).self) {
            try StringCatalog(data: Data("{ \"strings\": 3 }".utf8))
        }
    }

    @Test("A module without a catalog throws")
    func moduleWithoutACatalog_throws() {
        #expect(throws: (any Error).self) {
            try StringCatalog(module: "LedgerDomain")
        }
    }
}

/// One catalog entry that breaks a rule, and what `problems` says about it.
nonisolated struct BrokenRule: Sendable, CustomTestStringConvertible {
    let testDescription: String
    var sourceLanguage = "en"
    let key: String
    let entry: TestCatalog.Entry
    let problems: [String]

    static let wholeNumbersAndTexts = "a key's values are whole numbers (%lld) and texts (%@), "
        + "so format anything else first and pass it as a String"

    static let all: [BrokenRule] = [
        BrokenRule(
            testDescription: "the source language is not English",
            sourceLanguage: "de",
            key: "Today",
            entry: .text("Today"),
            problems: ["the source language is \"de\", not \"en\""]
        ),
        BrokenRule(
            testDescription: "a key with no English text (as Xcode writes an extracted key)",
            key: "Today",
            entry: .empty,
            problems: ["\"Today\" has no English text this check can read (a string unit, or the plural forms)"]
        ),
        BrokenRule(
            testDescription: "a plain key whose English text is not the key",
            key: "today.title",
            entry: .text("Today"),
            problems: ["\"today.title\" has the English text \"Today\": a key is its English text"]
        ),
        BrokenRule(
            testDescription: "a text still marked new, which the build leaves out",
            key: "Today",
            entry: .text("Today", state: "new"),
            problems: ["\"Today\" is not marked translated: a hand-written catalog marks its English text so"]
        ),
        BrokenRule(
            testDescription: "a text marked needs_review, which the build compiles but the rule does not accept",
            key: "Today",
            entry: .text("Today", state: "needs_review"),
            problems: ["\"Today\" is not marked translated: a hand-written catalog marks its English text so"]
        ),
        BrokenRule(
            testDescription: "a text that names the product",
            key: "Ledger tries again",
            entry: .text("Ledger tries again"),
            problems: ["\"Ledger tries again\" names the product, which shipped copy never does"]
        ),
        BrokenRule(
            testDescription: "a counted form that names the product, in any case",
            key: "%lld sets",
            entry: .counted(["one": "%lld set in your ledger", "other": "%lld sets"]),
            problems: ["\"%lld sets\" names the product, which shipped copy never does"]
        ),
        BrokenRule(
            testDescription: "a text that spells the key's letter with a combining mark",
            key: "Caf\u{E9} stop",
            entry: .text("Cafe\u{301} stop"),
            problems: ["\"Caf\u{E9} stop\" has the English text \"Cafe\u{301} stop\": a key is its English text"]
        ),
        BrokenRule(
            testDescription: "a counted key without its one form",
            key: "%lld exercises",
            entry: .counted(["other": "%lld exercises"]),
            problems: ["\"%lld exercises\" needs exactly the forms \"one\" and \"other\""]
        ),
        BrokenRule(
            testDescription: "a counted key with a form English does not have",
            key: "%lld exercises",
            entry: .counted(["one": "%lld exercise", "few": "%lld exercises", "other": "%lld exercises"]),
            problems: ["\"%lld exercises\" needs exactly the forms \"one\" and \"other\""]
        ),
        BrokenRule(
            testDescription: "a counted key that counts two values",
            key: "%lld sets of %lld",
            entry: .counted(["one": "%lld set of %lld", "other": "%lld sets of %lld"]),
            problems: ["\"%lld sets of %lld\" counts 2 values: a counted key holds exactly one %lld"]
        ),
        BrokenRule(
            testDescription: "a counted key whose other form is not the key",
            key: "%lld exercise(s)",
            entry: .counted(["one": "%lld exercise", "other": "%lld exercises"]),
            problems: [
                "\"%lld exercise(s)\" has the \"other\" form \"%lld exercises\": a counted key is its \"other\" form"
            ]
        ),
        BrokenRule(
            testDescription: "a form whose specifier is not the key's",
            key: "%lld exercises",
            entry: .counted(["one": "%@ exercise", "other": "%lld exercises"]),
            problems: ["\"%lld exercises\" has a \"one\" form whose format specifiers are not the key's"]
        ),
        BrokenRule(
            testDescription: "a key that formats a Double",
            key: "%lf lb moved",
            entry: .text("%lf lb moved"),
            problems: ["\"%lf lb moved\" holds %lf: \(BrokenRule.wholeNumbersAndTexts)"]
        ),
        BrokenRule(
            testDescription: "a key with a precision, a 32-bit number and a C string, one of them by position",
            key: "%.1f kg · %2$d sets · %s",
            entry: .text("%.1f kg · %2$d sets · %s"),
            problems: ["\"%.1f kg · %2$d sets · %s\" holds %.1f, %d, %s: \(BrokenRule.wholeNumbersAndTexts)"]
        ),
        BrokenRule(
            testDescription: "a counted form with another specifier, which the key does not have",
            key: "%lld exercises",
            entry: .counted(["one": "%lld exercise of %d", "other": "%lld exercises"]),
            problems: [
                "\"%lld exercises\" holds %d: \(BrokenRule.wholeNumbersAndTexts)",
                "\"%lld exercises\" has a \"one\" form whose format specifiers are not the key's"
            ]
        ),
        BrokenRule(
            testDescription: "a form that drops the count",
            key: "%lld exercises",
            entry: .counted(["one": "One exercise", "other": "%lld exercises"]),
            problems: ["\"%lld exercises\" has a \"one\" form whose format specifiers are not the key's"]
        ),
        BrokenRule(
            testDescription: "a form still marked new",
            key: "%lld exercises",
            entry: .counted(["one": "%lld exercise", "other": "%lld exercises"], state: "new"),
            problems: [
                "\"%lld exercises\" has a \"one\" form that is not marked translated",
                "\"%lld exercises\" has a \"other\" form that is not marked translated"
            ]
        )
    ]
}
