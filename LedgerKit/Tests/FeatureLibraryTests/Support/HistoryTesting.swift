import Dependencies
@testable import FeatureLibrary
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport

/// The fixtures of an exercise's history (F12 S2). Bench is the catalog's Barbell Bench Press.
nonisolated enum HistoryFixtures {
    static let day: TimeInterval = 86400

    static var bench: Exercise {
        get throws {
            try LibraryFixtures.exercise(named: "Barbell Bench Press")
        }
    }

    /// A session of `sets` done sets of `reps` × `pounds` lb, started at `date`.
    static func session(_ number: Int, _ date: Date, sets: Int, _ pounds: Decimal, _ reps: Int) -> ExerciseSession {
        ExerciseSession(
            workoutID: WorkoutID(Fixtures.uuid(7000 + number)),
            startedAt: date,
            sets: (0 ..< sets).map { place in
                LoggedSet(
                    id: SetID(Fixtures.uuid(70000 + number * 20 + place)),
                    weight: .pounds(pounds),
                    reps: Reps(clamping: reps),
                    kind: .working,
                    doneAt: date
                )
            }
        )
    }

    /// Criterion 4 (restated per C11): a week's top set in each of the eight weeks to `Fixtures.now`, none in W3 and
    /// W6, the best 195 × 5 in the current week: estimates 191, 197, —, 205, 208, —, 214, 219.
    static let criterion4: [(back: Int, pounds: Decimal)] = [
        (0, 195), (1, 190), (3, 185), (4, 182.5), (6, 175), (7, 170)
    ]

    static var criterion4Sessions: [ExerciseSession] {
        criterion4.map { week in
            session(week.back, Fixtures.now.addingTimeInterval(-Double(week.back) * 7 * day), sets: 3, week.pounds, 5)
        }
    }

    /// Criterion 7 (restated per C12), newest first: Aug 12 180 × 5 ×5, Aug 5 175 × 5 ×4 and 175 × 4, Jul 29
    /// 175 × 5 ×4, Jul 22 170 × 5 ×5, Jun 24 175 × 6; Aug 12 alone set a record.
    static var criterion7Sessions: [ExerciseSession] {
        let date = { (month: Int, day: Int) in Fixtures.date(2026, month, day, hour: 7) }
        var august5 = session(4, date(8, 5), sets: 4, 175, 5)
        august5.sets += session(14, date(8, 5), sets: 1, 175, 4).sets
        return [
            session(5, date(8, 12), sets: 5, 180, 5), august5, session(3, date(7, 29), sets: 4, 175, 5),
            session(2, date(7, 22), sets: 5, 170, 5), session(1, date(6, 24), sets: 1, 175, 6)
        ]
    }

    static func input(
        _ sessions: [ExerciseSession],
        records: Set<WorkoutID> = [],
        units: Units = .lb,
        now: Date = Fixtures.now
    ) throws -> ExerciseHistoryInput {
        try ExerciseHistoryInput(
            exercise: bench,
            sessions: sessions,
            records: records,
            units: units,
            weekStart: .monday,
            now: now,
            calendar: Fixtures.calendar,
            locale: Fixtures.locale
        )
    }
}

/// An `ExerciseHistoryStore` for bench and what it reads, under test: in-memory stores seeded with the catalog,
/// `workouts` and the settings in pounds.
@MainActor
struct HistoryScene {
    let memory: InMemoryStores
    let store: ExerciseHistoryStore

    init(
        exercise: ExerciseID? = nil,
        workouts: [WorkoutState] = [],
        configure: (inout DependencyValues) -> Void = { _ in }
    ) throws {
        let stores = InMemoryStores(seed: InMemoryStores.Seed(
            catalog: LibraryFixtures.catalog + [LibraryFixtures.custom],
            workouts: workouts,
            settings: Fixtures.settingsLb
        ))
        memory = stores
        let id = try exercise ?? HistoryFixtures.bench.id
        store = withTestDependencies {
            $0.exerciseRepository = stores.exercises
            $0.workoutRepository = stores.workouts
            $0.statsQueries = stores.stats
            $0.settingsRepository = stores.settings
            configure(&$0)
        } operation: {
            ExerciseHistoryStore(exercise: id)
        }
    }

    func running() async -> Task<Void, Never> {
        let task = Task { await store.run() }
        await eventually { store.state != .loading }
        return task
    }

    var model: ExerciseHistoryModel {
        get throws {
            guard case let .loaded(model) = store.state else {
                throw LibraryScene.NotLoaded(state: "\(store.state)")
            }
            return model
        }
    }

    /// Three bench workouts, a week apart, ending at `Fixtures.now`: 185, 190 and 195 × 5.
    static func benchWorkouts() throws -> [WorkoutState] {
        let bench = try HistoryFixtures.bench
        return ([185, 190, 195] as [Decimal]).enumerated().map { place, pounds in
            let ended = Fixtures.now.addingTimeInterval(-Double(2 - place) * 7 * 86400)
            return Seeders.workout(number: 600 + place, endedAt: ended, [
                .straight(bench, sets: 3, reps: 5, pounds: pounds)
            ])
        }
    }
}

extension ExerciseHistoryModel {
    /// The bars' values as drawn, nil for a week with none.
    var numbers: [Int?] {
        chart.bars.map(\.number)
    }
}
