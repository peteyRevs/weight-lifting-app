#if DEBUG
    import Foundation
    import Testing // the one support file that records an issue: the runner's tail warning, below

    /// The one place a timing test's verdict is reached (testing-strategy §2.2, "Budgets and the runner"). A
    /// budget belongs to the reference machine, a simulator on a developer Mac; a shared CI runner's virtual
    /// machine is not it. Read from `LEDGER_PERFORMANCE_RUNNER_FACTOR`: unset, as on a developer Mac, in the
    /// local nightly and in `swift test`, each test's own statistic (its 95th percentile, or its median) must be
    /// under its budget, as written. Only the hosted nightly sets it (as `TEST_RUNNER_` plus its name, which
    /// `xcodebuild` hands to the test runner without the prefix); there the median of the runs must be under the
    /// budget times the factor, because a 95th percentile of 20 runs on a shared machine measures its neighbours.
    /// Every verdict still reports both statistics, and on the runner a 95th percentile over the scaled budget is
    /// recorded as a warning, which fails nothing: the tails stay visible.
    public enum PerformanceRunner {
        /// The statistic a test holds to its budget on the reference machine.
        public enum Statistic: String, Sendable {
            case median
            case percentile95 = "p95"
        }

        /// One test's verdict: `statistic`'s value against `budget` (already times the factor).
        public struct Verdict: Sendable, CustomStringConvertible {
            public let statistic: Statistic
            public let value: Duration
            public let budget: Duration
            public let factor: Double
            public let median: Duration
            public let percentile95: Duration
            public let runs: [Duration]

            /// Whether the value is under the budget.
            public var isWithinBudget: Bool {
                value < budget
            }

            /// On the runner, whether the 95th percentile, which the verdict does not hold, is over the budget.
            public var tailExceedsBudget: Bool {
                factor > 1 && percentile95 >= budget
            }

            public var description: String {
                "\(statistic.rawValue) \(value) against \(budget) (factor \(factor)); "
                    + "median \(median), p95 \(percentile95); runs \(runs)"
            }
        }

        /// The factor of this machine: 1 unless the variable holds a finite number of at least 1 (a factor never
        /// tightens a budget).
        public static let factor: Double = factor(
            ProcessInfo.processInfo.environment["LEDGER_PERFORMANCE_RUNNER_FACTOR"]
        )

        /// The factor `value` asks for, as `factor` reads its variable.
        public static func factor(_ value: String?) -> Double {
            guard let parsed = value.flatMap(Double.init), parsed.isFinite, parsed >= 1 else {
                return 1
            }
            return parsed
        }

        /// `runs` (warm-up excluded, in any order) held to `budget`, the reference machine's, on this machine. On
        /// the runner, a 95th percentile over the scaled budget is recorded as a warning at the caller's line.
        public static func verdict(
            _ runs: [Duration],
            budget: Duration,
            statistic: Statistic = .percentile95,
            sourceLocation: SourceLocation = #_sourceLocation
        ) -> Verdict {
            let verdict = verdict(runs, budget: budget, statistic: statistic, factor: factor)
            if verdict.tailExceedsBudget {
                Issue.record(
                    "p95 \(verdict.percentile95) over the runner's budget \(verdict.budget), not held: \(verdict)",
                    severity: .warning,
                    sourceLocation: sourceLocation
                )
            }
            return verdict
        }

        /// The median (the middle run, or the upper middle) and the 95th percentile (the 19th fastest of 20) of
        /// `runs`, in any order: what every verdict and report states.
        public static func statistics(_ runs: [Duration]) -> (median: Duration, percentile95: Duration) {
            precondition(!runs.isEmpty, "a statistic needs at least one run")
            let sorted = runs.sorted()
            return (sorted[sorted.count / 2], sorted[max(0, sorted.count * 95 / 100 - 1)])
        }

        /// As `verdict(_:budget:statistic:)`, for a given factor: with a factor above 1, the median against the
        /// budget times the factor; otherwise `statistic` against the budget.
        public static func verdict(
            _ runs: [Duration],
            budget: Duration,
            statistic: Statistic,
            factor: Double
        ) -> Verdict {
            let (median, percentile95) = statistics(runs)
            let held = factor > 1 ? .median : statistic
            return Verdict(
                statistic: held,
                value: held == .median ? median : percentile95,
                budget: budget * factor,
                factor: factor,
                median: median,
                percentile95: percentile95,
                runs: runs
            )
        }
    }
#endif
