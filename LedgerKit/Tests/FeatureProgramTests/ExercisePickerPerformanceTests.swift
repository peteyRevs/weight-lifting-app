@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S8 adversarial round 1, by measurement: the exercise library's model over 10,000 stored exercises, a
/// thousand of them picked (twice) and 500 already on the day, takes under 1 s, at the median of 20 runs after one
/// warm-up (0.51-0.53 s on an iPhone 17 simulator, three runs, 2026-11-15). The model's answers are
/// `ExercisePickerModelAdversarialTests.tenThousandExercises_areOneModel`'s. A timing is only meaningful without
/// other suites competing for the CPU (the PR lane's runner once took 2.076 s, PR #109), so this is `.performance`:
/// nightly lane only (testing-strategy §6).
@Suite(
    "Exercise picker · timing",
    .tags(.feature, .performance),
    .enabled(if: TestLane.runsSlowTests, "a .performance test: nightly lane only")
)
struct ExercisePickerPerformanceTests {
    static let model: Duration = .seconds(1)
    static let runs = 20

    @Test("The model over 10,000 exercises, 1,000 of them picked, takes under 1 s")
    func tenThousandExercises_underBudget() {
        var generator = SeededGenerator(seed: 8)
        let exercises = (0 ..< 10000).map { AdvPicker.exercise($0, using: &generator) }
        let picks = exercises.prefix(1000).map(\.id).shuffled(using: &generator)
        let input = ExercisePickerInput(
            exercises: exercises, dayExercises: Set(exercises.suffix(500).map(\.id)), query: "", muscle: nil,
            equipment: nil, picks: picks + picks, locale: Locale(identifier: "en_US")
        )
        var built: ExercisePickerModel?
        let work = { built = ExercisePickerPresentation.make(input) }
        work()
        let clock = ContinuousClock()
        let timings = (0 ..< Self.runs).map { _ in clock.measure(work) }
        #expect(built?.rows.count == 10000)
        let verdict = PerformanceRunner.verdict(timings, budget: Self.model, statistic: .median)
        #expect(verdict.isWithinBudget, "\(verdict)")
        Attachment.record(
            "ExercisePickerPresentation.make over 10,000 exercises: median \(verdict.median)",
            named: "exercise-picker.txt"
        )
    }
}
