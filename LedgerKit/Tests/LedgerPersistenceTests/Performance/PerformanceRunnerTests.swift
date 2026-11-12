import LedgerTestSupport
import Testing

/// `PerformanceRunner` (testing-strategy §2.2, "Budgets and the runner"): with no runner factor each test holds its
/// own statistic to its budget; with the hosted nightly's factor every test holds its median to the budget times the
/// factor; nothing can tighten or disable a budget. Not `.performance`: it times nothing, so it runs in every lane.
@Suite("Performance budgets on a runner", .tags(.persistence))
struct PerformanceRunnerTests {
    /// Twenty runs of 1 to 20 ms, shuffled: the median (the 11th fastest) is 11 ms, the 95th percentile (the 19th
    /// fastest) 19 ms.
    static let runs: [Duration] = [7, 19, 3, 12, 20, 1, 15, 9, 18, 4, 11, 6, 14, 2, 17, 8, 13, 5, 16, 10]
        .map { .milliseconds($0) }

    @Test("The factor is the variable's number when it is at least 1, and 1 for anything else", arguments: [
        (nil, 1.0), ("2", 2), ("1.5", 1.5), ("1", 1), ("0.5", 1), ("0", 1), ("-2", 1), ("", 1), ("two", 1),
        ("inf", 1), ("nan", 1)
    ] as [(String?, Double)])
    func factor_readsTheVariable(value: String?, factor: Double) {
        #expect(PerformanceRunner.factor(value) == factor)
    }

    @Test("Without a factor a 95th-percentile test holds its p95 to the budget as written")
    func noFactor_percentile95() {
        let verdict = PerformanceRunner.verdict(
            Self.runs,
            budget: .milliseconds(19),
            statistic: .percentile95,
            factor: 1
        )
        #expect(verdict.statistic == .percentile95)
        #expect(verdict.value == .milliseconds(19) && verdict.budget == .milliseconds(19))
        #expect(!verdict.isWithinBudget) // 19 is not under 19, although the median (11) is
        #expect(PerformanceRunner.verdict(Self.runs, budget: .milliseconds(20), statistic: .percentile95, factor: 1)
            .isWithinBudget)
    }

    @Test("Without a factor a median test holds its median to the budget as written")
    func noFactor_median() {
        let verdict = PerformanceRunner.verdict(Self.runs, budget: .milliseconds(11), statistic: .median, factor: 1)
        #expect(verdict.statistic == .median && verdict.value == .milliseconds(11) && !verdict.isWithinBudget)
    }

    @Test("With a factor every test holds its median to the budget times the factor", arguments: [
        PerformanceRunner.Statistic.percentile95, .median
    ])
    func factor_swapsToTheMedian(statistic: PerformanceRunner.Statistic) {
        // historyList on the runner (run 43170933804): p95 3.7 times its budget, median within twice it.
        let passes = PerformanceRunner.verdict(Self.runs, budget: .milliseconds(6), statistic: statistic, factor: 2)
        #expect(passes.statistic == .median && passes.value == .milliseconds(11))
        #expect(passes.budget == .milliseconds(12) && passes.isWithinBudget)
        let fails = PerformanceRunner.verdict(Self.runs, budget: .milliseconds(5), statistic: statistic, factor: 2)
        #expect(!fails.isWithinBudget) // 11 against 10
    }

    @Test("A verdict reports both statistics and the runs, whichever it holds")
    func verdict_reportsBoth() {
        let verdict = PerformanceRunner.verdict(
            Self.runs,
            budget: .milliseconds(6),
            statistic: .percentile95,
            factor: 2
        )
        #expect(verdict.median == .milliseconds(11) && verdict.percentile95 == .milliseconds(19))
        #expect(verdict.runs == Self.runs)
        #expect(verdict.description.hasPrefix("median \(Duration.milliseconds(11)) against "))
        #expect(verdict.description.contains("p95 \(Duration.milliseconds(19))"))
    }

    @Test("Five runs: the median is the third fastest, the p95 the fourth")
    func fiveRuns() {
        let five: [Duration] = [5, 1, 4, 2, 3].map { .milliseconds($0) }
        let verdict = PerformanceRunner.verdict(five, budget: .milliseconds(10), statistic: .median, factor: 1)
        #expect(verdict.median == .milliseconds(3) && verdict.percentile95 == .milliseconds(4))
    }

    @Test("This run's verdict uses this run's factor")
    func verdict_usesTheFactor() {
        let verdict = PerformanceRunner.verdict(Self.runs, budget: .milliseconds(20))
        #expect(verdict.budget == .milliseconds(20) * PerformanceRunner.factor)
        #expect(verdict.statistic == (PerformanceRunner.factor > 1 ? .median : .percentile95))
    }
}
