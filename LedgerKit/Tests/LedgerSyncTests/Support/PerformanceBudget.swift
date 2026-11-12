/// LedgerSync's performance budgets (architecture §15, testing-strategy §2.2): kept here, never inline in a test.
enum PerformanceBudget {
    /// Architecture §15: an `apply` on the session host, its append to the store on a database file included
    /// (the F10 brief's "Non-functional"), at the 95th percentile of `runs` runs.
    static let apply: Duration = .milliseconds(30)
    /// How many timed applies, after the warm-up: enough for a 95th percentile (the 19th fastest of 20).
    static let runs = 20
}
