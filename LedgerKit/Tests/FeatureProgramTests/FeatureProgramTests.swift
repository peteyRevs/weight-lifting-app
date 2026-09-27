@testable import FeatureProgram
import Testing

@Suite("FeatureProgram")
struct FeatureProgramTests {
    @Test("The placeholder module reports its own target name")
    func module_name_matchesTarget() {
        #expect(FeatureProgramModule.name == "FeatureProgram")
    }
}
