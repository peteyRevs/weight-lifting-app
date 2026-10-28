@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// FeatureSettings' lookups the presentation tests do not reach, and what the catalog holds.
@Suite("SettingsCopy", .tags(.feature))
struct SettingsCopyTests {
    @Test("N5. Each unit has its option and its spoken name", arguments: Units.allCases)
    func units_haveTheirOptionAndSpokenName(_ units: Units) {
        let option = SettingsCopy.unitsOption(units)
        let spoken = SettingsCopy.spokenUnits(units)
        #expect(option == option.uppercased() && option.count == 2)
        #expect(spoken.count > option.count, "a word, not the abbreviation")
    }

    @Test("N6. The About line's words carry their values")
    func about_carriesItsValues() {
        #expect(SettingsCopy.version("1.2.3", locale: Fixtures.locale) == "Version 1.2.3")
        #expect(SettingsCopy.build("45", locale: Fixtures.locale) == "build 45")
        #expect(SettingsCopy.versionUnknown == "Version unknown")
    }

    @Test("The failed save's line, and the Debug row's title")
    func messages_readAsWritten() {
        #expect(SettingsCopy.saveFailed == "Couldn't save that change.")
        #expect(SettingsCopy.diagnostics == "Diagnostics")
    }

    /// That the bundle the build made resolves each key is `ModuleCopyTests`' (LedgerAppKitTests).
    @Test("The catalog is sound and holds the module's 26 keys")
    func catalog_isSound() throws {
        let catalog = try StringCatalog(module: "FeatureSettings")
        #expect(catalog.problems.isEmpty, "\(catalog.problems)")
        #expect(catalog.keys.count == 26)
    }
}
