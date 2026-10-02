/// LedgerPersistence's performance budgets (architecture §15, testing-strategy §2.2): kept here, never
/// inline in a test.
enum PerformanceBudget {
    /// F05 risk "watchOS first-launch migration": `LedgerDatabase.open(at:)` creating and migrating a new
    /// file. Above it, F07 opens the database after the first frame.
    static let firstLaunchOpen: Duration = .milliseconds(300)
    /// F05 risk "seeding time on the watch": `seedIfNeeded` writing a 214-entry catalog into a new file.
    /// Above it, F07 seeds after the first frame.
    static let catalogSeed: Duration = .milliseconds(300)
    /// F12's "search filter < 10 ms/keystroke": one `search` over the seeded catalog and a few custom rows.
    static let exerciseSearch: Duration = .milliseconds(10)
    /// How many timed runs a measured test takes the median of, after one untimed warm-up.
    static let runs = 5
}
