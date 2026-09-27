import Testing
@testable import WatchFeatureWorkout

@Suite("WatchFeatureWorkout")
struct WatchFeatureWorkoutTests {
    @Test("The placeholder module reports its own target name")
    func module_name_matchesTarget() {
        #expect(WatchFeatureWorkoutModule.name == "WatchFeatureWorkout")
    }
}
