import Dependencies
@testable import FeatureHistory
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Observation
import Testing

/// Tags live in the test target (F00 implementation notes #6), as `LedgerDesignTests`' do.
extension Tag {
    /// Every FeatureHistory suite (layer tag, testing-strategy §6).
    @Tag static var feature: Self
    /// Suites that compare against committed `__Snapshots__` references.
    @Tag static var snapshot: Self
    /// A timing: nightly lane only (testing-strategy §6).
    @Tag static var performance: Self
}

/// The lane a test plan runs in, from its `LEDGER_TEST_LANE` variable (testing-strategy §6).
nonisolated enum TestLane {
    /// `.slow` and `.performance` tests run only in the nightly plans; the PR plans and `swift test` skip them.
    static var runsSlowTests: Bool {
        ProcessInfo.processInfo.environment["LEDGER_TEST_LANE"] == "nightly"
    }
}

/// Waits until `condition` holds, by watching what it reads (Observation), never by time. A condition that never
/// holds ends at the suite's time limit.
@MainActor
func eventually(_ condition: @escaping @MainActor @Sendable () -> Bool) async {
    for await holds in Observations({ condition() }) where holds {
        return
    }
}

/// The workouts History's criteria name (R10: the fixtures live with the tests, not in LedgerFakes).
nonisolated enum HistoryFixtures {
    static let bench = WorkoutRepositoryContract.exercises[0]
    static let names = ["Upper A", "Lower A", "Upper B"]

    /// Criterion 1's fixture: twelve workouts on Monday, Wednesday and Friday at 07:00 UTC over the four Monday weeks
    /// from 2026-08-17, oldest first, each 58 minutes long and named in turn "Upper A", "Lower A", "Upper B". Workout
    /// `n`'s bench is three sets of 5 at 135 + 5n lb, so each but the first sets records over the one before.
    static func twelve() -> [WorkoutState] {
        (0 ..< 12).map { number in
            let day = (number / 3) * 7 + [0, 2, 4][number % 3]
            let start = Fixtures.date(2026, 8, 17, hour: 7).addingTimeInterval(86400 * Double(day))
            return workout(number, startedAt: start, name: names[number % 3], pounds: 135 + 5 * Decimal(number))
        }
    }

    /// A workout of bench alone, `sets` sets of 5 at `pounds`, started at `startedAt` and `minutes` long.
    static func workout(
        _ number: Int,
        startedAt: Date,
        name: String = "Upper A",
        minutes: Int = 58,
        sets: Int = 3,
        pounds: Decimal = 185
    ) -> WorkoutState {
        var workout = Seeders.workout(
            number: 100 + number,
            endedAt: startedAt.addingTimeInterval(60 * Double(minutes)),
            minutes: minutes,
            [.straight(bench, sets: sets, reps: 5, pounds: pounds)]
        )
        workout.name = name
        return workout
    }

    /// `workouts` (oldest first) as `historyEntries()` gives them, newest first, each with the records it set
    /// against those before it (product decision #27): the previews' builder (review R1-6).
    static func entries(_ workouts: [WorkoutState]) -> [HistoryEntry] {
        HistoryPreviewData.entries(workouts)
    }

    /// The input of `entries`, in `units`, weeks from `weekStart`, at `Fixtures.now` in UTC and en_US.
    static func input(
        _ entries: [HistoryEntry],
        units: Units = .lb,
        weekStart: Weekday = .monday,
        now: Date = Fixtures.now
    ) -> HistoryInput {
        HistoryInput(
            entries: entries,
            units: units,
            weekStart: weekStart,
            now: now,
            calendar: Fixtures.calendar,
            locale: Fixtures.locale
        )
    }
}

/// A `HistoryStore` and what it reads, under test: in-memory stores holding `workouts`, and the settings in pounds.
/// The store is made inside `withTestDependencies`, so its dependencies are the scene's for its whole life.
@MainActor
struct HistoryScene {
    let memory: InMemoryStores
    let store: HistoryStore

    init(workouts: [WorkoutState] = [], configure: (inout DependencyValues) -> Void = { _ in }) {
        let stores = InMemoryStores(seed: InMemoryStores.Seed(workouts: workouts, settings: Fixtures.settingsLb))
        memory = stores
        store = withTestDependencies {
            $0.workoutRepository = stores.workouts
            $0.settingsRepository = stores.settings
            configure(&$0)
        } operation: {
            HistoryStore()
        }
    }

    /// The store's run, as `HistoryRoot`'s task runs it, once it shows anything but loading. The task is the root's:
    /// a test cancels it where the view would go away.
    func running() async -> Task<Void, Never> {
        let task = Task { await store.run() }
        await eventually { store.state != .loading }
        return task
    }

    /// The model on screen.
    var model: HistoryModel {
        get throws {
            guard case let .loaded(model) = store.state else {
                throw NotLoaded(state: "\(store.state)")
            }
            return model
        }
    }

    struct NotLoaded: Error {
        let state: String
    }
}

extension HistoryModel {
    /// The weeks drawn, or none.
    var weeks: [Week] {
        if case let .weeks(weeks) = content {
            return weeks
        }
        return []
    }

    /// Every row, week after week.
    var rows: [Row] {
        weeks.flatMap(\.rows)
    }

    /// The row of the workout `id`.
    func row(_ id: WorkoutID) -> Row? {
        rows.first { $0.id == id }
    }
}

extension String {
    /// A week's header as the tests write it, "Sep 7 – 13", as `Date.IntervalFormatStyle` writes it in en_US: a thin
    /// space (U+2009) on each side of the dash.
    var thinSpaced: String {
        replacingOccurrences(of: " – ", with: "\u{2009}–\u{2009}")
    }
}
