@testable import FeatureLibrary
import Testing

@Suite("FeatureLibrary")
struct FeatureLibraryTests {
    @Test("The placeholder module reports its own target name")
    func module_name_matchesTarget() {
        #expect(FeatureLibraryModule.name == "FeatureLibrary")
    }
}
