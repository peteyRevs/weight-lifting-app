import LedgerTestSupport
@testable import LedgerWatchAppKit
import Testing

/// F18 S0: the wording of the watch shell's copy, and the bundle the watch build made answers every key of its
/// catalog. `ModuleCopyTests` audits this module's sources from the iOS plan, but its bundle embeds no watch
/// module's resources, so this suite, in the PR-Watch plan, asks the watch's own; the gate compares the catalog
/// with the keys the watch build extracted.
@Suite("WatchAppCopy")
struct WatchAppCopyTests {
    @Test("Product decision #29's screen reads as the iPhone's does, and names no product")
    func texts_readAsTheIPhonesDo() {
        #expect(WatchAppCopy.databaseUnavailableTitle == "Can't open your data right now")
        #expect(
            WatchAppCopy.databaseUnavailableBody
                == "Your workouts are still on this watch. The app tries again when you come back to it."
        )
    }

    @Test("The bundle the watch build made resolves every key of LedgerWatchAppKit's catalog")
    func builtBundle_resolvesEveryKey() throws {
        let catalog = try StringCatalog(module: "LedgerWatchAppKit")
        let bundle = try #require(StringCatalog.resourceBundle(ofModule: "LedgerWatchAppKit"))
        #expect(catalog.keys.count == 2)
        #expect(catalog.unresolvedKeys(in: bundle) == [])
    }
}
