@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// Today's counted texts under any locale (chore of 2026-10-12, item 1). A lookup takes its words from the
/// catalog and its plural form from its locale's language, so with the lifter's own locale an English text
/// took another language's form: "1 exercises" in Japanese, which has no singular, "21 exercise" in Russian.
/// Each counted text is now looked up through `Locale.forCountedText`, as the Program's and the workout's
/// are: the form is the catalog's language's, the digits and their grouping the lifter's.
@Suite("Today's counted texts", .tags(.feature))
nonisolated struct TodayCountedTextTests {
    /// The locales of the Program tester's test of the same rule (`ProgramCountedTextAdversarialTests`):
    /// scripts, numbering systems, keywords, and no known language.
    static let locales = [
        "", "und", "zz", "xx_YY", "en_US", "en_IN", "en_US_POSIX", "de_DE", "de_CH", "fr_FR", "fr_CA", "es_ES",
        "pl_PL", "ru_RU", "ja_JP", "ja_JP@calendar=japanese", "zh_Hant_TW", "zh_Hans_CN", "ko_KR", "sr_Latn_RS",
        "ar_EG", "ar_AE", "ar_SA", "fa_IR", "hi_IN", "hi_IN@numbers=deva", "ne_NP", "my_MM", "he_IL",
        "th_TH@calendar=buddhist;numbers=thai", "en_US@numbers=arab", "en@rg=dezzzz", "de_DE@currency=USD", "cy_GB",
        "ga_IE", "sl_SI", "lt_LT"
    ]

    /// None, one, and the numbers other languages count in a form of their own: two (a dual), three and five
    /// (few, many), eleven and twenty-one (Russian's one is by the last digit), and two larger ones.
    static let counts = [0, 1, 2, 3, 5, 11, 21, 101, 999]

    @Test(
        "Under any locale each counted text of Today takes English's form, with the count in the locale's own digits",
        arguments: locales
    )
    func countedTexts_anyLocale_areEnglishWithTheLocalesDigits(identifier: String) {
        let locale = Locale(identifier: identifier)
        for count in Self.counts {
            let digits = count.formatted(.number.locale(locale))
            let isOne = count == 1
            #expect(
                TodayCopy.exercises(count, locale: locale) == "\(digits) \(isOne ? "exercise" : "exercises")",
                "\(count)"
            )
            #expect(
                TodayCopy.sets(done: "3", of: count, locale: locale) == "3 of \(digits) \(isOne ? "set" : "sets")",
                "\(count)"
            )
            #expect(
                TodayCopy.sessionsSummary(done: "3", planned: count, locale: locale)
                    == "3 of \(digits) \(isOne ? "session" : "sessions") this week",
                "\(count)"
            )
            #expect(
                TodayCopy.blockCompleteBody(weeks: count, locale: locale)
                    == "\(digits) \(isOne ? "week" : "weeks") done. Start the next block from Program.",
                "\(count)"
            )
            // "min" is the same word for one and for several; the two are counted keys all the same.
            #expect(TodayCopy.estimate(minutes: count, locale: locale) == "~\(digits) min", "\(count)")
            #expect(TodayCopy.duration(minutes: count, locale: locale) == "\(digits) min", "\(count)")
        }
    }

    @Test("A region's grouping is kept in a counted text: India's lakhs, Germany's points, Arabic digits")
    func grouping_ofTheRegion_isKept() {
        let cases = [
            ("en_IN", "12,34,567"), ("hi_IN", "12,34,567"), ("de_DE", "1.234.567"), ("de_CH", "1'234'567"),
            ("ar_EG", "١٬٢٣٤٬٥٦٧"), ("fa_IR", "۱٬۲۳۴٬۵۶۷"), ("fr_FR", "1\u{202F}234\u{202F}567")
        ]
        for (identifier, written) in cases {
            let locale = Locale(identifier: identifier)
            #expect(1_234_567.formatted(.number.locale(locale)) == written, "\(identifier): the test's premise")
            #expect(TodayCopy.exercises(1_234_567, locale: locale) == "\(written) exercises", "\(identifier)")
            #expect(TodayCopy.duration(minutes: 1_234_567, locale: locale) == "\(written) min", "\(identifier)")
        }
    }

    // MARK: - The sources

    /// A key or a lookup's literal with every value replaced by one mark, so that the two can be compared.
    static func shape(_ text: String) -> String {
        text.replacingOccurrences(of: #"\\\([A-Za-z.]+\)|%lld|%@"#, with: "§", options: .regularExpression)
    }

    @Test("Every lookup of a key the catalog counts goes through forCountedText, and no other lookup does")
    func countedLookups_allGoThroughTheOnePlace() throws {
        let catalog = try StringCatalog(module: "FeatureToday")
        let counted = Set(catalog.strings.compactMap { key, english -> String? in
            if case .plural = english {
                return Self.shape(key)
            }
            return nil
        })
        let copyFiles = try CopyAudit.sources(ofModule: "FeatureToday")
            .filter { $0.key.contains("TodayCopy") }
            .sorted { $0.key < $1.key }
        var wrong: [String] = []
        var seen: Set<String> = []
        var lookups = 0
        for (path, text) in copyFiles {
            // Each piece runs from one lookup's key to the next lookup, so it holds one call and no other.
            for statement in text.components(separatedBy: "localized: \"").dropFirst() {
                lookups += 1
                let literal = Self.shape(String(statement.prefix { $0 != "\"" }))
                let call = String(statement.prefix { $0 != "}" })
                let isCounted = counted.contains(literal)
                seen.formUnion(isCounted ? [literal] : [])
                if isCounted != call.contains("locale: locale.forCountedText") {
                    wrong.append("\(path): «\(literal)» counted \(isCounted)")
                }
            }
        }
        #expect(counted.count == 6, "the catalog counts \(counted.count) keys")
        #expect(seen == counted, "counted keys never looked up: \(counted.subtracting(seen).sorted())")
        #expect(lookups >= 55, "the scan read \(lookups) lookups")
        #expect(wrong.isEmpty, "\(wrong.prefix(6))")
    }
}
