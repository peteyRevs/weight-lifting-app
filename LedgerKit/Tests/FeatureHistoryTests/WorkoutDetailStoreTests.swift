import Dependencies
@testable import FeatureHistory
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// F13 S2, criteria 3, 5 and 7, N8 to N10, through the store over in-memory stores: the model, what an edit redraws
/// without navigating (its own, and an earlier workout's that takes its records), the units, a delete (once, failed,
/// made elsewhere), a workout that can't be read, and a row's route.
@MainActor
@Suite("WorkoutDetailStore", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
struct WorkoutDetailStoreTests {
    static let twelve = HistoryFixtures.twelve()

    static func workout(_ index: Int) throws -> WorkoutState {
        try #require(twelve.indices.contains(index) ? twelve[index] : nil)
    }

    @Test("3. The first model is the presentation's of the workout as stored, with its records, in pounds")
    func run_firstModel_isThePresentations() async throws {
        let newest = try Self.workout(11)
        let scene = DetailScene(newest.id)
        let run = await scene.running()
        defer { run.cancel() }
        let isThePresentations = try await scene.model == scene.expected(newest.id)
        #expect(isThePresentations)
        #expect(try scene.model.receipt.records == "2 new PRs this session")
    }

    @Test("N8. An edit of the workout while its detail is up redraws it, without navigating")
    func workoutEdited_redraws() async throws {
        let newest = try Self.workout(11)
        let scene = DetailScene(newest.id)
        let run = await scene.running()
        defer { run.cancel() }
        let sets = Array(newest.exercises[0].sets.prefix(2))
        try await scene.memory.workouts.updateSets(workoutExerciseID: newest.exercises[0].id, sets: sets)
        await eventually { (try? scene.model.receipt.rows.first?.chips) == ["2 × 190×5"] }
        #expect(try scene.model.receipt.tiles.dropFirst().first?.value == "2/2")
    }

    @Test("N8. An earlier workout raised past this one takes its records away, and the records line goes")
    func earlierWorkoutEdited_takesTheRecordsAway() async throws {
        let (oldest, second) = try (Self.workout(0), Self.workout(1))
        let scene = DetailScene(second.id)
        let run = await scene.running()
        defer { run.cancel() }
        #expect(try scene.model.receipt.records != nil)
        var raised = oldest.exercises[0].sets
        for index in raised.indices {
            raised[index].weight = .pounds(145)
        }
        try await scene.memory.workouts.updateSets(workoutExerciseID: oldest.exercises[0].id, sets: raised)
        await eventually { (try? scene.model.receipt.records) == .some(nil) }
    }

    @Test("7. A change of units redraws every weight, without navigating")
    func unitsChanged_redrawsTheWeights() async throws {
        let scene = try DetailScene(Self.workout(11).id)
        let run = await scene.running()
        defer { run.cancel() }
        try await scene.memory.settings.save(Fixtures.settingsKg)
        await eventually { (try? scene.model.receipt.tiles.last?.label) == "KG MOVED" }
        #expect(try scene.model.receipt.rows.first?.chips == ["3 × 86.2×5"])
    }

    @Test("3. A row's tap waits as one route; a second tap before the app took it is dropped")
    func rowTapped_twice_isOneRoute() async throws {
        let scene = try DetailScene(Self.workout(11).id)
        let run = await scene.running()
        defer { run.cancel() }
        let route = try #require(scene.model.rowRoutes.first)
        scene.store.send(route)
        scene.store.send(route)
        var handed: [HistoryRoute] = []
        scene.store.deliverRoute { handed.append($0) }
        scene.store.deliverRoute { handed.append($0) }
        #expect(handed == [.exercise(HistoryFixtures.bench.id)])
    }

    @Test("5, N9. Delete confirmed twice deletes once, then the detail asks to close")
    func delete_confirmedTwice_deletesOnce() async throws {
        let newest = try Self.workout(11)
        let scene = DetailScene(newest.id)
        let run = await scene.running()
        defer { run.cancel() }
        scene.store.confirmDelete()
        scene.store.confirmDelete()
        #expect(scene.store.deletion == 1, "the second confirmation is dropped")
        await scene.store.delete()
        await scene.store.delete()
        #expect(scene.workouts.deleteCount == 1)
        #expect(try await scene.memory.workouts.workout(id: newest.id) == nil)
        #expect(scene.store.state == .gone)
        #expect(scene.store.pendingRoute?.route == .closeWorkout(newest.id))
        scene.store.confirmDelete()
        #expect(scene.store.deletion == 1, "nothing is left to delete")
    }

    @Test("N9. A delete that fails says so and keeps the screen; a later one may try again")
    func delete_failed_keepsTheScreen() async throws {
        let newest = try Self.workout(11)
        let scene = DetailScene(newest.id, failsDeletes: true)
        let run = await scene.running()
        defer { run.cancel() }
        let shown = try scene.model
        scene.store.confirmDelete()
        await scene.store.delete()
        #expect(scene.store.showsDeleteFailure)
        let isKept = try scene.model == shown
        #expect(isKept)
        #expect(scene.store.pendingRoute == nil)
        scene.store.confirmDelete()
        #expect(scene.store.deletion == 2)
    }

    @Test("N9. Nothing is deleted until the alert's Delete: the detail runs no delete of its own")
    func delete_notConfirmed_deletesNothing() async throws {
        let scene = try DetailScene(Self.workout(11).id)
        let run = await scene.running()
        defer { run.cancel() }
        await scene.store.delete()
        #expect(scene.workouts.deleteCount == 0)
        #expect(scene.store.deletion == nil)
    }

    @Test("N8, N9. A delete made elsewhere closes the detail")
    func deletedElsewhere_closes() async throws {
        let newest = try Self.workout(11)
        let scene = DetailScene(newest.id)
        let run = await scene.running()
        defer { run.cancel() }
        try await scene.memory.workouts.delete(id: newest.id)
        await eventually { scene.store.state == .gone }
        #expect(scene.store.pendingRoute?.route == .closeWorkout(newest.id))
        var handed: [HistoryRoute] = []
        scene.store.deliverRoute { handed.append($0) }
        #expect(handed == [.closeWorkout(newest.id)])
    }

    @Test("A detail run again on a workout already gone asks to close again")
    func runAgain_onAGoneWorkout_closesAgain() async throws {
        let newest = try Self.workout(11)
        let scene = DetailScene(newest.id)
        try await scene.memory.workouts.delete(id: newest.id)
        let run = await scene.running()
        defer { run.cancel() }
        scene.store.deliverRoute { _ in }
        run.cancel()
        await run.value
        let again = await scene.running()
        defer { again.cancel() }
        await eventually { scene.store.pendingRoute?.route == .closeWorkout(newest.id) }
    }

    @Test("N10. A workout that can't be read says so, with Delete still offered and working")
    func unreadable_saysSo_andDeletes() async throws {
        let newest = try Self.workout(11)
        let scene = DetailScene(newest.id, endsObservation: true)
        let run = await scene.running()
        defer { run.cancel() }
        #expect(scene.store.state == .unreadable(WorkoutDetailPresentation.unreadable))
        scene.store.confirmDelete()
        await scene.store.delete()
        #expect(scene.workouts.deleteCount == 1)
        #expect(scene.store.state == .gone)
        #expect(scene.store.pendingRoute?.route == .closeWorkout(newest.id))
    }
}
