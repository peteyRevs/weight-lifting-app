@testable import FeatureOnboarding
import Testing

@Suite("FeatureOnboarding")
struct FeatureOnboardingTests {
    @Test("The placeholder module reports its own target name")
    func module_name_matchesTarget() {
        #expect(FeatureOnboardingModule.name == "FeatureOnboarding")
    }
}
