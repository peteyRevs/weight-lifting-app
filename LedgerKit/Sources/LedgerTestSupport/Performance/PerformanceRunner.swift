#if DEBUG
    import Foundation

    /// The machine a performance budget is measured on (testing-strategy §2.2, "Budgets and the runner"). A
    /// budget belongs to the reference machine, a simulator on a developer Mac; a shared CI runner's virtual
    /// machine is not it. Read from `LEDGER_PERFORMANCE_RUNNER_FACTOR`: unset, as on a developer Mac, in the
    /// local nightly and in `swift test`, every budget holds as written. Only the hosted nightly sets it (as
    /// `TEST_RUNNER_LEDGER_PERFORMANCE_RUNNER_FACTOR`, which `xcodebuild` hands to the test runner without its
    /// prefix), and there each timing is held to its budget times the factor. Every timed budget asks through
    /// `budget(_:)`, so this is the one place the factor applies.
    public enum PerformanceRunner {
        /// The factor a timing budget is multiplied by on this machine: 1 unless the variable holds a finite
        /// number of at least 1 (a factor never tightens a budget).
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

        /// `budget` on this machine: the reference machine's budget, times `factor`.
        public static func budget(_ budget: Duration) -> Duration {
            budget * factor
        }
    }
#endif
