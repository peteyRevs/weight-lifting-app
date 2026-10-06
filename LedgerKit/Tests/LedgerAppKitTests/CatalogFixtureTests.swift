import Foundation
import LedgerTestSupport
import Testing

/// Proof that a hand-written String Catalog in a package target is compiled by the build and read through
/// `Bundle.module` (F09 S1; standards §7), for the three kinds of string a module's copy has. The shell's own copy
/// has no formatted or counted string, so these come from `Fixtures/Localizable.xcstrings`, which this test target
/// owns. The fixture's plain and formatted keys differ from their English text on purpose: a lookup that missed
/// the catalog would return the key, and these tests would see it.
///
/// `Bundle.module` here is this test target's own bundle, so the file does not import LedgerAppKit.
@Suite("String Catalog fixture")
struct CatalogFixtureTests {
    private static let english = Locale(identifier: "en_US")
    private static let fixture = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Fixtures/Localizable.xcstrings")

    @Test("A plain string resolves to the catalog's text")
    func plainString_resolvesFromTheBundle() {
        #expect(String(localized: "fixture.plain", bundle: .module) == "Resolved from the catalog")
    }

    @Test("A formatted string takes its numbers and its text in order")
    func formattedString_takesItsArguments() {
        let week = 3
        let total = 8
        let day = "Friday"
        #expect(
            String(localized: "fixture.week \(week) of \(total)", bundle: .module, locale: Self.english)
                == "Week 3 of 8"
        )
        #expect(String(localized: "fixture.next \(day)", bundle: .module) == "Next: Friday")
    }

    @Test(
        "A counted string picks its form by the count",
        arguments: [(0, "0 fixture sets"), (1, "1 fixture set"), (2, "2 fixture sets"), (21, "21 fixture sets")]
    )
    func countedString_picksOneOrOther(count: Int, expected: String) {
        #expect(String(localized: "\(count) fixture sets", bundle: .module, locale: Self.english) == expected)
    }

    @Test("The locale a lookup is given groups its numbers")
    func countedString_groupsDigitsByTheLocale() {
        let count = 1234
        let german = Locale(identifier: "de_DE")
        #expect(String(localized: "\(count) fixture sets", bundle: .module, locale: Self.english) ==
            "1,234 fixture sets")
        #expect(String(localized: "\(count) fixture sets", bundle: .module, locale: german) == "1.234 fixture sets")
    }

    @Test("The bundle the build made resolves every key of the fixture")
    func builtBundle_resolvesEveryKey() throws {
        let catalog = try StringCatalog(contentsOf: Self.fixture)
        #expect(catalog.keys == ["%lld fixture sets", "fixture.next %@", "fixture.plain", "fixture.week %lld of %lld"])
        #expect(catalog.unresolvedKeys(in: .module) == [])
    }
}
