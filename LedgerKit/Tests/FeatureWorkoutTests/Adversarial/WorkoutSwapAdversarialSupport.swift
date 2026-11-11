import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The shipped catalog, by name.
nonisolated enum SwapG2Catalog {
    static func all() throws -> [Exercise] {
        try ExerciseCatalog.seed()
    }

    static func named(_ name: String) throws -> Exercise {
        try #require(all().first { $0.name == name }, "no \(name) in the catalog")
    }

    /// `EventBuilders.seedSession()` with its exercises made the catalog's `names` (id, name, equipment and
    /// the equipment's step), from a program (`source` set) unless `adHoc`, in `units`.
    static func workout(
        _ names: [String] = [
            "Barbell Bench Press", "Incline DB Press", "Chest-Supported Row", "Lat Pulldown", "Cable Lateral Raise"
        ],
        units: Units = .lb,
        adHoc: Bool = false
    ) throws -> WorkoutState {
        var workout = EventBuilders.seedSession()
        workout.units = units
        workout.source = adHoc ? nil : WorkoutSource(
            programID: ProgramID(EventBuilders.uuid(0xA100)),
            weekIndex: 0,
            dayTemplateID: DayTemplateID(EventBuilders.uuid(0xA200))
        )
        for (index, name) in names.enumerated() where workout.exercises.indices.contains(index) {
            let exercise = try named(name)
            workout.exercises[index].exerciseID = exercise.id
            workout.exercises[index].name = exercise.name
            workout.exercises[index].equipment = exercise.equipment
            workout.exercises[index].step = exercise.equipment.defaultStep(in: units)
            if adHoc {
                workout.exercises[index].slotID = nil
            }
        }
        return workout
    }
}

/// A store on a `PumpSession` (the real engine, the test's hand on every call) with the swap's two reads
/// bound to the doubles above, following the session as the cover does. The root's tasks are the test's:
/// `open()` runs the load as `.task(id: swapAttempt)` does, `use(_:)` drains as the pump does.
@MainActor
struct SwapG2Bench {
    let session: PumpSession
    let store: WorkoutStore
    let following: Task<Void, Never>
    let exercises: SwapG2Exercises
    let stats: SwapG2Stats
    let running: WorkoutState

    static func make(
        _ workout: WorkoutState? = nil,
        catalog: [Exercise]? = nil,
        _ prepare: (SwapG2Stats) async -> Void = { _ in }
    ) async throws -> SwapG2Bench {
        let live = try workout ?? SwapG2Catalog.workout()
        let client = PumpSession(live: live)
        let repository = try SwapG2Exercises(catalog ?? SwapG2Catalog.all())
        let queries = SwapG2Stats()
        await prepare(queries)
        let cover = withTestDependencies {
            $0.workoutSession = client
            $0.exerciseRepository = repository
            $0.statsQueries = queries
        } operation: {
            WorkoutStore()
        }
        let task = Task { await cover.follow() }
        await eventually("the session's first update") { cover.shown != nil }
        return SwapG2Bench(
            session: client,
            store: cover,
            following: task,
            exercises: repository,
            stats: queries,
            running: live
        )
    }

    /// The card's "Swap exercise", then the read its task runs.
    func open() async {
        store.send(.openSwap)
        await store.loadSwap()
    }

    var sheet: SwapSheetModel? {
        store.dialog == .swap ? store.swapSheet : nil
    }

    var card: ExerciseCardModel? {
        guard case let .workout(model) = store.model else {
            return nil
        }
        return model.page.card
    }

    var page: WorkoutPageModel? {
        guard case let .workout(model) = store.model else {
            return nil
        }
        return model.page
    }

    /// A tap on the row named `name`; false when the sheet has no such row.
    @discardableResult
    func use(_ name: String) -> Bool {
        guard let row = store.swapSheet?.rows.first(where: { $0.name == name }) else {
            return false
        }
        store.send(.edit(row.choose))
        return true
    }

    /// Lets the pump apply what waits, and the page show the session's workout.
    func settle() async {
        await store.drain()
        await session.deliver()
        let truth = await session.current()
        await eventually("the page to show the session's workout") { store.shown == truth }
    }

    func set(_ exercise: Int, _ row: Int) -> SetID {
        running.exercises[exercise].sets[row].id
    }

    /// How many `exerciseSwapped` reached the engine from this store.
    func swapsApplied() async -> Int {
        await session.applied.count {
            if case .exerciseSwapped = $0 {
                return true
            }
            return false
        }
    }
}
