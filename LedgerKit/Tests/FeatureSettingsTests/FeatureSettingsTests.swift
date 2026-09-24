@testable import FeatureSettings
import Testing

@Suite("FeatureSettings")
struct FeatureSettingsTests {
    @Test("The placeholder module reports its own target name")
    func module_name_matchesTarget() {
        #expect(FeatureSettingsModule.name == "FeatureSettings")
    }
}
