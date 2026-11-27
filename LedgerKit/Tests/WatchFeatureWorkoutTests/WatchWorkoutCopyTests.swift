import LedgerTestSupport
import Testing
@testable import WatchFeatureWorkout

/// F18 S0: the wording of the watch workout's copy, and the bundle the watch build made answers every key of its
/// catalog. `ModuleCopyTests` audits this module's sources from the iOS plan, but its bundle embeds no watch
/// module's resources, so this suite, in the PR-Watch plan, asks the watch's own; the gate compares the catalog
/// with the keys the watch build extracted.
@Suite("WatchWorkoutCopy")
struct WatchWorkoutCopyTests {
    @Test("The connection line is F17 criterion 12's, word for word")
    func connectionLine_isTheCriterions() {
        #expect(WatchWorkoutCopy.iPhoneNotConnected == "iPhone not connected — logging continues")
    }

    @Test("The bundle the watch build made resolves every key of WatchFeatureWorkout's catalog")
    func builtBundle_resolvesEveryKey() throws {
        let catalog = try StringCatalog(module: "WatchFeatureWorkout")
        let bundle = try #require(StringCatalog.resourceBundle(ofModule: "WatchFeatureWorkout"))
        #expect(catalog.keys.count == 64)
        #expect(catalog.unresolvedKeys(in: bundle) == [])
    }
}
