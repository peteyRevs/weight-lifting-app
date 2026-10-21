import Dependencies
@testable import FeatureLibrary
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Observation
import Testing

/// Tags live in the test target (F00 implementation notes #6), as `LedgerDesignTests`' do.
extension Tag {
    /// Every FeatureLibrary suite (layer tag, testing-strategy §6).
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

/// The catalog's exercises the Library's criteria name.
nonisolated enum LibraryFixtures {
    static let catalog: [Exercise] = (try? ExerciseCatalog.seed()) ?? []

    static func exercise(named name: String) throws -> Exercise {
        try #require(catalog.first { $0.name == name }, "\(name) is not in the catalog")
    }

    /// One of the lifter's own: a barbell chest press the catalog lacks.
    static let custom = Exercise(
        id: ExerciseID(Fixtures.uuid(901)),
        name: "Landmine Squeeze Press",
        shortName: "LM SQZ",
        equipment: .barbell,
        primaryMuscle: .chest,
        secondaryMuscles: [.shoulders, .triceps],
        pattern: .horizontalPush,
        defaultStartLoad: [:],
        isCustom: true
    )

    /// `count` workouts of one exercise, a day apart and ending at `Fixtures.now`, each with one done working set
    /// of `reps` × `pounds` lb.
    static func sessions(of exercise: Exercise, _ count: Int, pounds: Decimal, reps: Int) -> [WorkoutState] {
        (0 ..< count).map { number in
            Seeders.workout(number: 500 + number, endedAt: Fixtures.now.addingTimeInterval(-86400 * Double(number)), [
                .straight(exercise, sets: 1, reps: reps, pounds: pounds)
            ])
        }
    }
}

/// A `LibraryStore` and what it reads, under test: in-memory stores seeded with the bundled catalog, `workouts`
/// and the settings in pounds. The store is made inside `withTestDependencies`, so its dependencies are the
/// scene's for its whole life.
@MainActor
struct LibraryScene {
    let memory: InMemoryStores
    let store: LibraryStore

    init(
        catalog: [Exercise] = LibraryFixtures.catalog,
        workouts: [WorkoutState] = [],
        configure: (inout DependencyValues) -> Void = { _ in }
    ) {
        let stores = InMemoryStores(seed: InMemoryStores.Seed(
            catalog: catalog,
            workouts: workouts,
            settings: Fixtures.settingsLb
        ))
        memory = stores
        store = withTestDependencies {
            $0.exerciseRepository = stores.exercises
            $0.workoutRepository = stores.workouts
            $0.statsQueries = stores.stats
            $0.settingsRepository = stores.settings
            configure(&$0)
        } operation: {
            LibraryStore()
        }
    }

    /// The store's run, as `LibraryRoot`'s task runs it, once it shows anything but loading. The task is the
    /// root's: a test cancels it where the view would go away.
    func running() async -> Task<Void, Never> {
        let task = Task { await store.run() }
        await eventually { store.state != .loading }
        return task
    }

    /// The model on screen.
    var model: LibraryModel {
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

extension LibraryModel {
    /// The sections drawn, or none.
    var sections: [Section] {
        if case let .sections(sections) = content {
            return sections
        }
        return []
    }

    /// The section of `kind`, if drawn.
    func section(_ kind: SectionKind) -> Section? {
        sections.first { $0.id == kind }
    }

    /// The names of the rows of the section of `kind`, in order.
    func names(_ kind: SectionKind) -> [String] {
        section(kind)?.rows.map(\.name) ?? []
    }

    /// The row of `name` in the section of `kind`.
    func row(_ name: String, in kind: SectionKind = .all) -> Row? {
        section(kind)?.rows.first { $0.name == name }
    }

    /// The titles of the selected chips: the muscle row's, then the equipment row's.
    var selectedChips: [String] {
        (muscles.chips + equipment.chips).filter(\.isSelected).map(\.title)
    }
}
