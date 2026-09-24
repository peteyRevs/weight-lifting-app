@testable import FeatureToday
import Testing

@Suite("FeatureToday")
struct FeatureTodayTests {
    @Test("The placeholder module reports its own target name")
    func module_name_matchesTarget() {
        #expect(FeatureTodayModule.name == "FeatureToday")
    }
}
