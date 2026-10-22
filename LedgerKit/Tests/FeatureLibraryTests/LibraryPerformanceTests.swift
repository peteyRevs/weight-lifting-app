@testable import FeatureLibrary
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F12 S1, N4, by measurement: over 250 exercises, the Library's first model (every row written, then laid out)
/// takes under 100 ms, and one keystroke (the rows filtered and laid out again) under 10 ms, at the median of
/// five runs after one warm-up. A timing is only meaningful without other suites competing for the CPU, so this
/// is `.performance`: nightly lane only (testing-strategy §6). The query budget, `bestSets` over 20,000 sets, is
/// `StatsQueriesPerformanceTests`'.
@Suite(
    "Library · timing",
    .tags(.feature, .performance),
    .enabled(if: TestLane.runsSlowTests, "a .performance test: nightly lane only")
)
struct LibraryPerformanceTests {
    static let firstModel: Duration = .milliseconds(100)
    static let keystroke: Duration = .milliseconds(10)
    static let runs = 5

    /// The catalog and 26 exercises of the lifter's own: 250; five recent, and a best set for every one.
    static func input() -> LibraryInput {
        let custom = (0 ..< 26).map { number in
            Exercise(
                id: ExerciseID(Fixtures.uuid(2000 + number)),
                name: "Custom press \(number)",
                shortName: "CP \(number)",
                equipment: .machine,
                primaryMuscle: .chest,
                pattern: .horizontalPush,
                defaultStartLoad: [:],
                isCustom: true
            )
        }
        let exercises = LibraryFixtures.catalog + custom
        return LibraryInput(
            exercises: exercises,
            recent: exercises.prefix(5).map(\.id),
            sessions: Dictionary(uniqueKeysWithValues: exercises.prefix(5).map { ($0.id, 34) }),
            bestSets: Dictionary(uniqueKeysWithValues: exercises.map {
                ($0.id, BestSet(weight: .pounds(195), reps: Reps(clamping: 5)))
            }),
            units: .lb,
            locale: Fixtures.locale
        )
    }

    /// The median of `runs` timings of `work`, after one untimed run.
    static func median(_ work: () -> Void) -> Duration {
        work()
        let clock = ContinuousClock()
        let timings = (0 ..< runs).map { _ in clock.measure(work) }.sorted()
        return timings[runs / 2]
    }

    @Test("N4. The first model over 250 exercises takes under 100 ms")
    func firstModel_underBudget() {
        let input = Self.input()
        #expect(input.exercises.count == 250)
        let time = Self.median {
            _ = LibraryPresentation.make(LibraryPresentation.rows(input), filter: LibraryFilter())
        }
        #expect(time < Self.firstModel, "\(time)")
    }

    @Test("N4. One keystroke over 250 exercises takes under 10 ms")
    func keystroke_underBudget() {
        let rows = LibraryPresentation.rows(Self.input())
        let time = Self.median {
            _ = LibraryPresentation.make(rows, filter: LibraryFilter(query: "ro", muscle: .back))
        }
        #expect(time < Self.keystroke, "\(time)")
    }
}
