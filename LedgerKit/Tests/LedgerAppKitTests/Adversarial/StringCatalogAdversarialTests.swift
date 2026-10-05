import Foundation
import LedgerTestSupport
import Testing

/// F09 S1 adversarial round 1: `StringCatalog`, the reader of a hand-written catalog. Standards §7, "Catalog", is the
/// specification: English source; every key spells out its English text, marked translated; a plain key's text is
/// the key; a counted key has `one` and `other`, counts exactly one value and its `other` form is the key; the file
/// is in the layout Xcode writes, keys in order.
@Suite("Adversarial F09 S1 · StringCatalog")
nonisolated struct StringCatalogAdversarialTests {
    typealias Catalog = AdversarialCatalog

    @Test("A catalog that follows the rules has no problem", arguments: sound)
    func soundCatalog_hasNoProblem(_ input: AdversarialInput) throws {
        let catalog = try StringCatalog(data: Data(input.text.utf8))
        #expect(catalog.problems.isEmpty, "\(catalog.problems)")
        #expect(catalog.sourceLanguage == "en")
    }

    @Test("A catalog that breaks a rule has a problem", arguments: unsound)
    func unsoundCatalog_hasAProblem(_ input: AdversarialInput) throws {
        let catalog = try StringCatalog(data: Data(input.text.utf8))
        #expect(!catalog.problems.isEmpty, "no problem for: \(input.text)")
    }

    @Test(
        "A counted key's forms take the arguments the key takes: another specifier in `one` is a problem",
        arguments: forms
    )
    func pluralFormWithOtherSpecifiers_isAProblem(_ input: AdversarialInput) throws {
        let catalog = try StringCatalog(data: Data(input.text.utf8))
        #expect(!catalog.problems.isEmpty, "no problem for: \(input.text)")
    }

    @Test("Text that is not a catalog throws: it neither crashes nor reads as an empty catalog", arguments: malformed)
    func malformedText_throws(_ input: AdversarialInput) {
        #expect(throws: (any Error).self) {
            try StringCatalog(data: Data(input.text.utf8))
        }
    }

    @Test("A key written twice is read as the build's compiler reads it: its first entry, the second unseen")
    func duplicateKey_isReadAsTheCompilerReadsIt() throws {
        let good = Catalog.plain("Today")
        let bad = Catalog.plain("Today", state: "new")
        // `xcrun xcstringstool compile` (Xcode 27.0) puts "Today" in the table for [good, bad] and leaves it out
        // for [bad, good]: the reader agrees with the bundle. Neither says the key is there twice.
        #expect(try Catalog.problems([good, bad]).isEmpty)
        #expect(try !Catalog.problems([bad, good]).isEmpty)
    }

    @Test("Two keys that differ in case, or in a space, are two keys")
    func keysDifferingInCaseOrSpace_areTwoKeys() throws {
        let entries = ["Today", "today", "Today ", " Today"].map { Catalog.plain($0) }
        let catalog = try Catalog.catalog(entries)
        #expect(catalog.keys == ["Today", "today", "Today ", " Today"])
        #expect(catalog.problems.isEmpty, "\(catalog.problems)")
    }

    @Test("Specifiers are read in order, a position left out, and an escaped percent sign is text")
    func specifiers_readInOrder() {
        #expect(StringCatalog.specifiers(in: "Week %lld of %lld") == ["%lld", "%lld"])
        #expect(StringCatalog.specifiers(in: "%lld of %lld sets · %@ lb moved") == ["%lld", "%lld", "%@"])
        #expect(StringCatalog.specifiers(in: "%2$@ then %1$lld") == ["%@", "%lld"])
        #expect(StringCatalog.specifiers(in: "100%% done").isEmpty)
        #expect(StringCatalog.specifiers(in: "%lld%% of %@") == ["%lld", "%@"])
        #expect(StringCatalog.specifiers(in: "%%lld").isEmpty)
        #expect(StringCatalog.specifiers(in: "%%%lld") == ["%lld"])
        #expect(StringCatalog.specifiers(in: "").isEmpty)
        #expect(StringCatalog.specifiers(in: "Start workout").isEmpty)
        #expect(StringCatalog.specifiers(in: "+%@%").count == 1)
    }

    @Test("The reader's view of a counted key: its forms by category, each with its state")
    func countedKey_isReadByCategory() throws {
        let entry = Catalog.plural("%lld sets", ["one": "%lld set", "other": "%lld sets"])
        let catalog = try Catalog.catalog([entry, Catalog.plain("Today")])
        guard case let .plural(forms)? = catalog.strings["%lld sets"] else {
            Issue.record("not read as a plural: \(String(describing: catalog.strings["%lld sets"]))")
            return
        }
        #expect(forms.keys.sorted() == ["one", "other"])
        #expect(forms["one"]?.value == "%lld set")
        #expect(forms["other"]?.value == "%lld sets")
        #expect(forms.values.allSatisfy { $0.state == "translated" })
        #expect(catalog.strings["Today"] == .text("Today", state: "translated"))
    }
}

nonisolated extension StringCatalogAdversarialTests {
    static func german(_ key: String, _ value: String) -> String {
        "\(Catalog.quoted(key)) : { \"localizations\" : { \"de\" : \(Catalog.unit(value)) } }"
    }

    static let sound: [AdversarialInput] = [
        AdversarialInput("no keys", Catalog.json([])),
        AdversarialInput("a plain key", Catalog.json([Catalog.plain("Start workout")])),
        AdversarialInput(
            "a key with a comment and Xcode's extraction state",
            Catalog.json([
                "\"Today\" : { \"comment\" : \"Tab title\", \"extractionState\" : \"manual\", "
                    + "\"localizations\" : { \"en\" : \(Catalog.unit("Today")) } }"
            ])
        ),
        AdversarialInput("a formatted key", Catalog.json([Catalog.plain("Week %lld of %lld")])),
        AdversarialInput("a key with an escaped percent sign", Catalog.json([Catalog.plain("%lld%% of the block")])),
        AdversarialInput("a key with a quote and an apostrophe", Catalog.json([Catalog.plain("Can't open \"%@\"")])),
        AdversarialInput("a key with a line break", Catalog.json([Catalog.plain("Line one\nLine two")])),
        AdversarialInput(
            "a counted key",
            Catalog.json([Catalog.plural("%lld sets", ["one": "%lld set", "other": "%lld sets"])])
        ),
        AdversarialInput(
            "a counted key with a text beside its count",
            Catalog.json([Catalog.plural("%lld sets of %@", ["one": "%lld set of %@", "other": "%lld sets of %@"])])
        ),
        AdversarialInput(
            "a second language beside English",
            Catalog.json([
                "\"Today\" : { \"localizations\" : { \"de\" : \(Catalog.unit("Heute")), "
                    + "\"en\" : \(Catalog.unit("Today")) } }"
            ])
        )
    ]

    static let unsound: [AdversarialInput] = [
        AdversarialInput("a key with nothing", Catalog.json(["\"Start workout\" : { }"])),
        AdversarialInput(
            "a key with no localization",
            Catalog.json(["\"Start workout\" : { \"localizations\" : { } }"])
        ),
        AdversarialInput("a key with German only", Catalog.json([german("Start workout", "Training starten")])),
        AdversarialInput("state new", Catalog.json([Catalog.plain("Start workout", state: "new")])),
        AdversarialInput("state needs_review", Catalog.json([Catalog.plain("Start workout", state: "needs_review")])),
        AdversarialInput("state stale", Catalog.json([Catalog.plain("Start workout", state: "stale")])),
        AdversarialInput("no state", Catalog.json([Catalog.plain("Start workout", state: nil)])),
        AdversarialInput("a text that is not the key", Catalog.json([Catalog.plain("today.title", value: "Today")])),
        AdversarialInput("a text with a trailing space", Catalog.json([Catalog.plain("Today", value: "Today ")])),
        AdversarialInput(
            "a text in another case",
            Catalog.json([Catalog.plain("Start workout", value: "Start Workout")])
        ),
        AdversarialInput("an empty text", Catalog.json([Catalog.plain("Today", value: "")])),
        AdversarialInput("another source language", Catalog.json([Catalog.plain("Today")], sourceLanguage: "de")),
        AdversarialInput("a plural without one", Catalog.json([Catalog.plural("%lld sets", ["other": "%lld sets"])])),
        AdversarialInput("a plural without other", Catalog.json([Catalog.plural("%lld sets", ["one": "%lld set"])])),
        AdversarialInput(
            "a plural whose other form is not the key",
            Catalog.json([Catalog.plural("sets.count", ["one": "%lld set", "other": "%lld sets"])])
        ),
        AdversarialInput(
            "a plural left new",
            Catalog.json([Catalog.plural("%lld sets", ["one": "%lld set", "other": "%lld sets"], state: "new")])
        ),
        AdversarialInput(
            "a plural with two counts",
            Catalog.json([
                Catalog.plural(
                    "%lld of %lld sets",
                    ["one": "%lld of %lld set", "other": "%lld of %lld sets"]
                )
            ])
        ),
        AdversarialInput(
            "a plural that counts nothing",
            Catalog.json([Catalog.plural("Some sets", ["one": "A set", "other": "Some sets"])])
        ),
        AdversarialInput(
            "a plural that counts a text",
            Catalog.json([Catalog.plural("%@ sets", ["one": "%@ set", "other": "%@ sets"])])
        ),
        AdversarialInput(
            "a variation by device",
            Catalog.json([
                "\"Today\" : { \"localizations\" : { \"en\" : { \"variations\" : { \"device\" : { "
                    + "\"iphone\" : \(Catalog.unit("Today")), \"other\" : \(Catalog.unit("Today")) } } } } }"
            ])
        )
    ]

    /// `one` is the only English text that is not the key, so the only place a specifier can go wrong: a `%@`
    /// where the caller passes an `Int` reads the number as an object.
    static let forms: [AdversarialInput] = [
        AdversarialInput(
            "one reads the count as a text",
            Catalog.json([Catalog.plural("%lld sets", ["one": "%@ set", "other": "%lld sets"])])
        ),
        AdversarialInput(
            "one drops the count before a text",
            Catalog.json([Catalog.plural("%lld sets of %@", ["one": "One set of %@", "other": "%lld sets of %@"])])
        ),
        AdversarialInput(
            "one takes an argument more",
            Catalog.json([Catalog.plural("%lld sets", ["one": "%lld set of %@", "other": "%lld sets"])])
        )
    ]

    static let malformed: [AdversarialInput] = [
        AdversarialInput("nothing", ""),
        AdversarialInput("prose", "not a catalog"),
        AdversarialInput("an array", "[]"),
        AdversarialInput("an empty object", "{}"),
        AdversarialInput("no strings", "{ \"sourceLanguage\" : \"en\", \"version\" : \"1.0\" }"),
        AdversarialInput(
            "strings as an array",
            "{ \"sourceLanguage\" : \"en\", \"strings\" : [], \"version\" : \"1.0\" }"
        ),
        AdversarialInput("a file cut short", String(Catalog.json([Catalog.plain("Today")]).dropLast(12)))
    ]
}
