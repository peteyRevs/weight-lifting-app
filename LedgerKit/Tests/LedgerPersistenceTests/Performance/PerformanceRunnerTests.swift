import LedgerTestSupport
import Testing

/// `PerformanceRunner` (testing-strategy §2.2, "Budgets and the runner"): the hosted nightly's factor loosens a
/// budget, nothing else can tighten or disable one, and with the variable unset every budget holds as written.
/// Not `.performance`: it times nothing, so it runs in every lane.
@Suite("Performance budgets on a runner", .tags(.persistence))
struct PerformanceRunnerTests {
    @Test("The factor is the variable's number when it is at least 1, and 1 for anything else", arguments: [
        (nil, 1.0), ("2", 2), ("1.5", 1.5), ("1", 1), ("0.5", 1), ("0", 1), ("-2", 1), ("", 1), ("two", 1),
        ("inf", 1), ("nan", 1)
    ] as [(String?, Double)])
    func factor_readsTheVariable(value: String?, factor: Double) {
        #expect(PerformanceRunner.factor(value) == factor)
    }

    @Test("A budget is the reference machine's times this run's factor")
    func budget_isScaledByTheFactor() {
        #expect(PerformanceRunner.budget(.milliseconds(20)) == .milliseconds(20) * PerformanceRunner.factor)
    }
}
