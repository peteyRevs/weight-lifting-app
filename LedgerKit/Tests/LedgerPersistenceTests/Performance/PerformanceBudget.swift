/// LedgerPersistence's performance budgets (architecture §15, testing-strategy §2.2): kept here, never
/// inline in a test.
enum PerformanceBudget {
    /// F05 risk "watchOS first-launch migration": `LedgerDatabase.open(at:)` creating and migrating a new
    /// file. Above it, F07 opens the database after the first frame.
    static let firstLaunchOpen: Duration = .milliseconds(300)
    /// How many timed runs a measured test takes the median of, after one untimed warm-up.
    static let runs = 5
}
