@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S8 adversarial round 2, criterion 14: `Locale.forCountedText`, the one place every counted text of
/// the module is looked up through. Locales with scripts, numbering systems, keywords and no known language;
/// the sources, read for a counted lookup that goes round it; and what it keeps of the lifter's locale.
@Suite("Adversarial F11 S8 · counted texts", .tags(.feature))
nonisolated struct ProgramCountedTextAdversarialTests {
    static let locales = [
        "", "und", "zz", "xx_YY", "en_US", "en_IN", "en_US_POSIX", "de_DE", "de_CH", "fr_FR", "fr_CA", "es_ES",
        "pl_PL", "ru_RU", "ja_JP", "ja_JP@calendar=japanese", "zh_Hant_TW", "zh_Hans_CN", "ko_KR", "sr_Latn_RS",
        "ar_EG", "ar_AE", "ar_SA", "fa_IR", "hi_IN", "hi_IN@numbers=deva", "ne_NP", "my_MM", "he_IL",
        "th_TH@calendar=buddhist;numbers=thai", "en_US@numbers=arab", "en@rg=dezzzz", "de_DE@currency=USD", "cy_GB",
        "ga_IE", "sl_SI", "lt_LT"
    ]

    @Test(
        "Under any locale a counted text takes English's form, with the count in the locale's own digits",
        arguments: locales
    )
    func countedText_anyLocale_isEnglishWithTheLocalesDigits(identifier: String) {
        let locale = Locale(identifier: identifier)
        for count in [1, 2, 3, 5, 11, 21, 101, 999] {
            let digits = count.formatted(.number.locale(locale))
            let noun = count == 1 ? "exercise" : "exercises"
            #expect(ProgramCopy.addExercises(count, locale: locale) == "Add \(digits) \(noun)", "\(count)")
            #expect(ProgramCopy.sets(count, locale: locale) == "\(digits) \(count == 1 ? "set" : "sets")", "\(count)")
        }
        let zero = 0.formatted(.number.locale(locale))
        #expect(ProgramCopy.days(0, locale: locale) == "\(zero) days")
        #expect(ProgramCopy.weeks(0, locale: locale) == "\(zero) weeks")
    }

    @Test(
        "The locale a counted text is looked up with is English with the lifter's region, digits and keywords",
        arguments: locales
    )
    func forCountedText_anyLocale_keepsRegionDigitsAndKeywords(identifier: String) {
        let locale = Locale(identifier: identifier)
        let counted = locale.forCountedText
        #expect(counted.language.languageCode?.identifier == "en", "\(counted.identifier)")
        #expect(counted.region == locale.region, "\(counted.identifier)")
        #expect(counted.numberingSystem == locale.numberingSystem, "\(counted.identifier)")
        #expect(counted.calendar.identifier == locale.calendar.identifier, "\(counted.identifier)")
        // Applied twice it is the same locale; en_US_POSIX alone comes back spelled another way, and is let be.
        let isSettled = counted.forCountedText == counted || identifier == "en_US_POSIX"
        #expect(isSettled, "applied twice it is another locale: \(counted.identifier)")
        #expect(Locale(identifier: identifier).forCountedText == counted, "the same locale in, another out")
    }

    @Test("A region's grouping is kept: India's lakhs, Germany's points, Switzerland's apostrophes, Arabic digits")
    func grouping_ofTheRegion_isKept() {
        let cases = [
            ("en_IN", "12,34,567"), ("hi_IN", "12,34,567"), ("de_DE", "1.234.567"), ("de_CH", "1'234'567"),
            ("ar_EG", "١٬٢٣٤٬٥٦٧"), ("fa_IR", "۱٬۲۳۴٬۵۶۷"), ("fr_FR", "1\u{202F}234\u{202F}567")
        ]
        for (identifier, written) in cases {
            let locale = Locale(identifier: identifier)
            #expect(1_234_567.formatted(.number.locale(locale)) == written, "\(identifier): the tester's premise")
            #expect(ProgramCopy.setsAWeek(1_234_567, locale: locale) == "\(written) sets a week", "\(identifier)")
        }
    }

    // MARK: - The sources

    static func copyFiles() throws -> [(name: String, text: String)] {
        let folder = ExercisePickerWordsAdversarialTests.folder("Sources/FeatureProgram")
        let found = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects ?? []
        return try found.compactMap { $0 as? URL }
            .filter { $0.lastPathComponent.hasPrefix("ProgramCopy") && $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
            .map { try ($0.lastPathComponent, String(contentsOf: $0, encoding: .utf8)) }
    }

    /// A key or a lookup's literal with every value replaced by one mark, so that the two can be compared.
    static func shape(_ text: String) -> String {
        text.replacingOccurrences(of: #"\\\([A-Za-z.]+\)|%lld|%@"#, with: "§", options: .regularExpression)
    }

    @Test("Every lookup of a key the catalog counts goes through forCountedText, and no other lookup does")
    func countedLookups_allGoThroughTheOnePlace() throws {
        let catalog = try Data(contentsOf: ExercisePickerWordsAdversarialTests.folder(
            "Sources/FeatureProgram/Resources/Localizable.xcstrings"
        ))
        let parsed = try #require(JSONSerialization.jsonObject(with: catalog) as? [String: Any])
        let strings = try #require(parsed["strings"] as? [String: Any])
        let counted = try Set(strings.filter { entry in
            try String(data: JSONSerialization.data(withJSONObject: entry.value), encoding: .utf8)?
                .contains("\"plural\"") == true
        }.keys.map(Self.shape))
        var wrong: [String] = []
        var seen: Set<String> = []
        var lookups = 0
        for file in try Self.copyFiles() {
            for statement in file.text.components(separatedBy: "localized: \"").dropFirst() {
                lookups += 1
                let literal = Self.shape(String(statement.prefix { $0 != "\"" }))
                let call = String(statement.prefix { $0 != "}" })
                let isCounted = counted.contains(literal)
                seen.formUnion(isCounted ? [literal] : [])
                if isCounted != call.contains("locale: locale.forCountedText") {
                    wrong.append("\(file.name): «\(literal)» counted \(isCounted)")
                }
            }
        }
        #expect(counted.count == 11, "the catalog counts \(counted.count) keys")
        #expect(seen == counted, "counted keys never looked up: \(counted.subtracting(seen).sorted())")
        #expect(lookups >= 100, "the scan read \(lookups) lookups")
        #expect(wrong.isEmpty, "\(wrong.prefix(5))")
    }

    @Test("The one place reads its locale and the module's catalog, and nothing of the device")
    func forCountedText_readsNothingAmbient() throws {
        let file = try #require(Self.copyFiles().first { $0.name == "ProgramCopy.swift" })
        // Chore of 2026-10-12, item 1: the one place is now the Domain's `forCountedText(in:)`, which every
        // feature's member of this name hands its own catalog; its body is read there.
        let shared = try String(
            contentsOf: ExercisePickerWordsAdversarialTests.folder("Sources/LedgerDomain/Units/CountedText.swift"),
            encoding: .utf8
        )
        let body = try #require(
            shared.components(separatedBy: "func forCountedText(in catalog: Bundle) -> Locale {").last
        )
        #expect(shared.components(separatedBy: "func forCountedText(in catalog: Bundle) -> Locale {").count == 2)
        #expect(file.text.contains("forCountedText(in: .module)"), "the module's member hands it another catalog")
        let code = body.split(separator: "\n").map { line in
            line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? String(line)
        }.joined(separator: "\n")
        let banned = [
            ".current", "autoupdating", "preferredLanguages", "UserDefaults", "ProcessInfo", "Bundle.main",
            ".preferredLocalizations\n", ".preferredLocalizations.", "NSLocale"
        ]
        #expect(!banned.contains(where: code.contains))
        #expect(code.contains("forPreferences: [identifier(.bcp47)]"), "the preferences are not this locale alone")
        #expect(file.text.components(separatedBy: "forCountedText: Locale").count == 2, "one place")
    }
}
