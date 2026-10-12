import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// `Locale.forCountedText(in:)`: the locale a counted text of a catalog is looked up with (chore of
/// 2026-10-12, item 1; F11 S8 criterion 14 and F10 S5 criterion 11 wrote it once per feature). The catalogs
/// here are folders made under the temporary directory, each with one `.lproj` per language it holds.
@Suite("CountedText", .tags(.domain))
struct CountedTextTests {
    /// A bundle that holds `languages` and nothing else; removed when the test ends.
    final class Catalog {
        let bundle: Bundle
        private let folder: URL

        init(_ languages: [String]) throws {
            folder = FileManager.default.temporaryDirectory
                .appending(path: "CountedTextTests-\(UUID().uuidString).bundle", directoryHint: .isDirectory)
            for language in languages {
                let project = folder.appending(path: "\(language).lproj", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
                try Data("\"k\" = \"v\";".utf8).write(to: project.appending(path: "Localizable.strings"))
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            bundle = try #require(Bundle(url: folder))
        }

        deinit {
            try? FileManager.default.removeItem(at: folder) // a temporary folder: left to the system if this fails
        }
    }

    static let locales = [
        "", "und", "zz", "xx_YY", "en_US", "en_IN", "de_DE", "de_CH", "fr_FR", "fr_CA", "es_ES", "pl_PL", "ru_RU",
        "ja_JP", "ja_JP@calendar=japanese", "zh_Hant_TW", "zh_Hans_CN", "ko_KR", "sr_Latn_RS", "ar_EG", "ar_SA",
        "fa_IR", "hi_IN", "hi_IN@numbers=deva", "he_IL", "th_TH@calendar=buddhist;numbers=thai", "en_US@numbers=arab"
    ]

    @Test(
        "With an English catalog the locale is English with the lifter's region, digits and calendar",
        arguments: locales
    )
    func englishCatalog_anyLocale_keepsRegionDigitsAndCalendar(identifier: String) throws {
        let catalog = try Catalog(["en"])
        let locale = Locale(identifier: identifier)
        let counted = locale.forCountedText(in: catalog.bundle)
        #expect(counted.language.languageCode?.identifier == "en", "\(counted.identifier)")
        #expect(counted.region == locale.region, "\(counted.identifier)")
        #expect(counted.numberingSystem == locale.numberingSystem, "\(counted.identifier)")
        #expect(counted.calendar.identifier == locale.calendar.identifier, "\(counted.identifier)")
        #expect(counted.forCountedText(in: catalog.bundle) == counted, "applied twice it is another locale")
        #expect(locale.forCountedText(in: catalog.bundle) == counted, "the same locale in, another out")
    }

    @Test("Of the languages a catalog holds it takes the one that fits the locale, and English when none does")
    func catalogWithSeveralLanguages_takesTheOneThatFits() throws {
        let catalog = try Catalog(["en", "fr", "ja"])
        let rows = [
            ("fr_FR", "fr", "FR"), ("fr_CA", "fr", "CA"), ("ja_JP", "ja", "JP"), ("en_GB", "en", "GB"),
            ("ru_RU", "en", "RU"), ("de_CH", "en", "CH")
        ]
        for (identifier, language, region) in rows {
            let counted = Locale(identifier: identifier).forCountedText(in: catalog.bundle)
            #expect(counted.language.languageCode?.identifier == language, "\(identifier): \(counted.identifier)")
            #expect(counted.region?.identifier == region, "\(identifier): \(counted.identifier)")
        }
    }

    @Test("The digits and the grouping of a number are still the lifter's")
    func numbers_areStillTheLifters() throws {
        let catalog = try Catalog(["en"])
        let rows = [
            ("en_IN", "12,34,567"), ("de_DE", "1.234.567"), ("de_CH", "1'234'567"), ("ar_EG", "١٬٢٣٤٬٥٦٧"),
            ("fa_IR", "۱٬۲۳۴٬۵۶۷"), ("hi_IN@numbers=deva", "१२,३४,५६७")
        ]
        for (identifier, written) in rows {
            let counted = Locale(identifier: identifier).forCountedText(in: catalog.bundle)
            #expect(1_234_567.formatted(.number.locale(counted)) == written, "\(identifier)")
        }
    }

    @Test("A catalog that holds no language is taken as English, as Foundation takes it; one language is that one")
    func catalogWithoutALanguage_isTakenAsEnglish() throws {
        let empty = try Catalog([])
        #expect(empty.bundle.localizations.isEmpty, "the test's premise")
        let counted = Locale(identifier: "ja_JP").forCountedText(in: empty.bundle)
        #expect(counted.language.languageCode?.identifier == "en")
        #expect(counted.region?.identifier == "JP")
        // A catalog in one other language answers in it, whatever the lifter's: there is no other text.
        let french = try Catalog(["fr"])
        #expect(Locale(identifier: "ja_JP").forCountedText(in: french.bundle).language.languageCode?.identifier == "fr")
    }
}
