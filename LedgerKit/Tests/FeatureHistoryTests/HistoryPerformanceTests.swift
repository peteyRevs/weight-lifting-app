@testable import FeatureHistory
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F13 S1, N4, by measurement: the History list's model over 1,000 workouts (every week grouped, every row written)
/// takes under 30 ms, at the median of five runs after one warm-up. The store builds it off the main actor, so it
/// costs no frame either way. A timing is only meaningful without other suites competing for the CPU, so this is
/// `.performance`: nightly lane only (testing-strategy §6). The query's budget is
/// `HistoryQueriesPerformanceTests`'.
@Suite(
    "History · timing",
    .tags(.feature, .performance),
    .enabled(if: TestLane.runsSlowTests, "a .performance test: nightly lane only")
)
struct HistoryPerformanceTests {
    static let model: Duration = .milliseconds(30)
    static let runs = 5

    @Test("N4. The list's model over 1,000 workouts, four a week with records, takes under 30 ms")
    func model_underBudget() {
        // Four workouts a week, newest first, from Fixtures.now back about five years; every third holds records.
        let entries = (0 ..< 1000).map { number in
            HistoryEntry(
                HistoryFixtures.workout(
                    number,
                    startedAt: Fixtures.now.addingTimeInterval(-43200 - 151_200 * Double(number))
                ),
                prCount: number % 3 == 0 ? 2 : 0
            )
        }
        let input = HistoryFixtures.input(entries)
        var built: HistoryModel?
        let work = { built = HistoryPresentation.make(input) }
        work()
        let clock = ContinuousClock()
        let timings = (0 ..< Self.runs).map { _ in clock.measure(work) }.sorted()
        let median = timings[Self.runs / 2]
        #expect(built?.rows.count == 1000)
        #expect(median < Self.model, "\(median)")
        Attachment.record("HistoryPresentation.make over 1,000 workouts: median \(median)", named: "history-list.txt")
    }
}
