import Foundation
import LedgerTestSupport
import Testing

/// F09 S1 adversarial round 1: the catalog as the build compiles it. The test target's fixture catalog
/// (`Fixtures/Localizable.xcstrings`, in `Bundle.module`) must resolve a plain, a formatted and a counted string on
/// the Mac host and on the simulator, with the digits of the locale the caller passes (standards §7, "Copy file"
/// and "Tiers"). That a catalog is keyed as the compiler keys the code is the gate's check
/// (`scripts/check-string-catalogs.sh`), where the cases that asked it of `CopyAudit` now are.
@Suite("Adversarial F09 S1 · the catalog the build makes")
nonisolated struct CatalogBuildAdversarialTests {
    static let american = Locale(identifier: "en_US")

    static func sets(_ count: Int, _ locale: Locale = american) -> String {
        String(localized: "\(count) fixture sets", bundle: .module, locale: locale)
    }

    @Test("A plain and a formatted string come from the catalog, not from their keys")
    func plainAndFormatted_resolve() {
        let weekday = "Friday"
        #expect(String(localized: "fixture.plain", bundle: .module) == "Resolved from the catalog")
        #expect(String(localized: "fixture.next \(weekday)", bundle: .module) == "Next: Friday")
        #expect(String(localized: "fixture.week \(3) of \(8)", bundle: .module, locale: Self.american) == "Week 3 of 8")
        #expect(
            String(localized: "fixture.absent", bundle: .module) == "fixture.absent",
            "control: a miss gives the key"
        )
    }

    @Test(
        "A counted string takes English's forms: one for 1, other for 0, 2, 21 and a large number",
        arguments: [
            (0, "0 fixture sets"), (1, "1 fixture set"), (2, "2 fixture sets"), (21, "21 fixture sets"),
            (101, "101 fixture sets"), (1_000_000, "1,000,000 fixture sets")
        ]
    )
    func countedString_takesEnglishForms(count: Int, expected: String) {
        #expect(Self.sets(count) == expected)
    }

    @Test(
        "The locale the caller passes groups the digits; the words stay English",
        arguments: [
            ("de_DE", "1.000.000 fixture sets"), ("en_IN", "10,00,000 fixture sets"),
            ("en_GB", "1,000,000 fixture sets")
        ]
    )
    func locale_groupsTheDigits(identifier: String, expected: String) {
        #expect(Self.sets(1_000_000, Locale(identifier: identifier)) == expected)
    }

    @Test("A formatted number follows the locale too, and one below a thousand is the same everywhere")
    func formattedNumber_followsTheLocale() {
        let german = Locale(identifier: "de_DE")
        #expect(String(localized: "fixture.week \(3) of \(1200)", bundle: .module, locale: german) == "Week 3 of 1.200")
        #expect(Self.sets(1, german) == "1 fixture set")
        #expect(Self.sets(21, german) == "21 fixture sets")
    }

    @Test("As Foundation does it: the locale the caller passes also picks the plural rule, over English words")
    func pluralForm_followsTheLocalesLanguage() {
        // Observed on macOS 27.0 and the iOS 27.0 simulator, pinned so that a copy test which injects a locale
        // knows: standards §7 says `locale:` fixes "the digits and their grouping"; it fixes the plural rule too.
        #expect(Self.sets(0, Locale(identifier: "fr_FR")) == "0 fixture set", "French counts 0 as one")
        #expect(Self.sets(21, Locale(identifier: "ru_RU")) == "21 fixture set", "Russian counts 21 as one")
        #expect(Self.sets(1, Locale(identifier: "ja_JP")) == "1 fixture sets", "Japanese has no one")
        #expect(Self.sets(0, Locale(identifier: "en_FR")) == "0 fixture sets", "an English locale in France")
    }

    @Test("Every key of the fixture catalog is in the test bundle's compiled table, and in no other bundle's")
    func fixtureKeys_resolveInTheirBundleOnly() throws {
        let catalog = try StringCatalog(contentsOf: Self.fixtureURL)
        #expect(catalog.keys.count == 4)
        #expect(catalog.unresolvedKeys(in: .module).isEmpty)
        let appKit = try #require(StringCatalog.resourceBundle(ofModule: "LedgerAppKit"))
        #expect(Set(catalog.unresolvedKeys(in: appKit)) == catalog.keys)
        #expect(Set(catalog.unresolvedKeys(in: .main)) == catalog.keys)
    }

    @Test("A module's bundle is found by name; a module without one is nil, and never the test's own bundle")
    func resourceBundle_isTheModules() throws {
        let appKit = try #require(StringCatalog.resourceBundle(ofModule: "LedgerAppKit"))
        #expect(appKit.bundleURL.lastPathComponent == "LedgerKit_LedgerAppKit.bundle")
        #expect(appKit.bundleURL != Bundle.module.bundleURL)
        #expect(StringCatalog.resourceBundle(ofModule: "NoSuchModule") == nil)
        #expect(StringCatalog.resourceBundle(ofModule: "") == nil)
    }

    @Test("Foundation's key for a lookup is what the fixture catalog is keyed by")
    func foundationsKey_isTheCatalogsKey() {
        #expect(LocalizedStringResource("fixture.week \(3) of \(8)").key == "fixture.week %lld of %lld")
        #expect(LocalizedStringResource("\(2) fixture sets").key == "%lld fixture sets")
        #expect(LocalizedStringResource("fixture.next \("Friday")").key == "fixture.next %@")
    }
}

nonisolated extension CatalogBuildAdversarialTests {
    /// `LedgerKit/Tests/LedgerAppKitTests/Fixtures/Localizable.xcstrings`, from this file's place in the repository.
    static let fixtureURL = URL(filePath: #filePath)
        .deletingLastPathComponent() // Adversarial
        .deletingLastPathComponent() // LedgerAppKitTests
        .appending(path: "Fixtures/Localizable.xcstrings")
}
