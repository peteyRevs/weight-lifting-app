@testable import FeatureHistory
import Testing

@Suite("FeatureHistory")
struct FeatureHistoryTests {
    @Test("The placeholder module reports its own target name")
    func module_name_matchesTarget() {
        #expect(FeatureHistoryModule.name == "FeatureHistory")
    }
}
