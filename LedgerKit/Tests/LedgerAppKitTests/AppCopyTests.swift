@testable import LedgerAppKit
import LedgerTestSupport
import Testing

/// F09 S1 criterion 4: every string the shell shows comes from LedgerAppKit's String Catalog, and the catalog and
/// the code agree in both directions (standards §7). The first two tests are the pair every module with copy has.
@Suite("AppCopy")
struct AppCopyTests {
    /// Files of the module whose string literals no lifter sees, and why.
    private static let exemptions = [
        "AppComposition.swift": "launch arguments, the database's file name and the logger's category",
        "AppComposition+Diagnostics.swift": "Debug builds only: the Diagnostics page's labels and keys"
    ]

    @Test("The catalog and the copy file agree in both directions, and no other file holds copy")
    func copy_followsTheStandard() throws {
        let audit = try CopyAudit(module: "LedgerAppKit", exempting: Self.exemptions)
        #expect(audit.findings == [])
    }

    @Test("The bundle the build made resolves every key of the catalog")
    func builtBundle_resolvesEveryKey() throws {
        let bundle = try #require(StringCatalog.resourceBundle(ofModule: "LedgerAppKit"))
        #expect(try StringCatalog(module: "LedgerAppKit").unresolvedKeys(in: bundle) == [])
    }

    @Test("The tabs are titled as product spec §2.1 titles them")
    func tabTitles_areTheSpecs() {
        #expect(AppTab.allCases.map(AppCopy.title(of:)) == ["Today", "Program", "Library", "History"])
    }

    @Test("A pushed screen without its feature is titled by its destination")
    func destinationTitles_nameTheScreen() {
        #expect(AppCopy.title(of: AppDestination.settings) == "Settings")
    }

    @Test("Product decision #29's screen keeps its wording")
    func databaseUnavailable_keepsItsWording() {
        #expect(AppCopy.databaseUnavailableTitle == "Can't open your data right now")
        #expect(
            AppCopy.databaseUnavailableBody
                == "Your workouts are still on this iPhone. Ledger tries again when you come back to it."
        )
    }
}
