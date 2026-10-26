@testable import FeatureLibrary
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F12 S1, N4, by measurement: over 250 exercises, the Library's first model (every row written, then laid out)
/// takes under 100 ms, and one keystroke (the rows filtered and laid out again) under 10 ms; and (F12-S2-R1-2) an
/// exercise's history model over 2,000 sets under a frame, 16 ms (its store builds it off the main actor, so the
/// slower case of 2,000 different weights costs no frame either); each at the median of five runs after one
/// warm-up. A timing is only meaningful without other suites competing for the CPU, so this
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
    static let historyModel: Duration = .milliseconds(16)
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

    @Test("F12-S2-R1-2. An exercise's history over 2,000 sets in 400 sessions is a model in under 16 ms")
    func historyModel_underAFrame() throws {
        var generator = SplitMix(seed: 42)
        let sessions = try Seeders.exerciseSessions(
            of: HistoryFixtures.bench,
            sessions: 400,
            setsPerSession: 5,
            rng: &generator
        )
        #expect(sessions.flatMap(\.sets).count == 2000)
        let records = Set(sessions.prefix(40).map(\.workoutID))
        let input = try HistoryFixtures.input(sessions, records: records, now: EventBuilders.start)
        var model: ExerciseHistoryModel?
        let time = Self.median { model = ExerciseHistoryPresentation.make(input) }
        #expect(model?.log.entries.count == 400)
        #expect(time < Self.historyModel, "\(time)")
        let report = "ExerciseHistoryPresentation.make over 2,000 sets: median \(time)"
        Attachment.record(report, named: "history-model.txt")
    }
}

/// A deterministic generator (SplitMix64, testing-strategy §3 rule 5) for the seeded sessions.
private struct SplitMix: RandomNumberGenerator {
    var seed: UInt64

    mutating func next() -> UInt64 {
        seed &+= 0x9E37_79B9_7F4A_7C15
        var mixed = seed
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
