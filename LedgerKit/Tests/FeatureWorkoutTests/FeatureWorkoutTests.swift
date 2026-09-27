@testable import FeatureWorkout
import Testing

@Suite("FeatureWorkout")
struct FeatureWorkoutTests {
    @Test("The placeholder module reports its own target name")
    func module_name_matchesTarget() {
        #expect(FeatureWorkoutModule.name == "FeatureWorkout")
    }
}
