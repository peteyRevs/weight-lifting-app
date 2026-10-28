import Dependencies
@testable import FeatureLibrary
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F12 S3, N20: the Library follows every workout of the history (finding F12-S2-6), in a file of its own for the
/// suite's length.
extension LibraryStoreTests {
    /// F12 S3, N20 (F12-S2-6): the Library follows every workout of the history, not only the newest, as a watch's
    /// workout saved after the phone's would arrive: older than the newest, then edited, then deleted.
    @Test("N20. An older workout finished, edited or deleted while the Library is up reaches its recent rows and PRs")
    func olderWorkoutChanges_whileRunning_show() async throws {
        let benchPress = try LibraryFixtures.exercise(named: Self.bench)
        let squat = try LibraryFixtures.exercise(named: "Back Squat")
        let scene = try LibraryScene(workouts: Self.benchHistory())
        let run = await scene.running()
        defer { run.cancel() }
        // Ends a day and an hour before the newest: behind it, so the newest workout is unchanged.
        let older = Seeders.workout(number: 1, endedAt: Fixtures.now.addingTimeInterval(-90000), [
            .straight(squat, sets: 3, reps: 5, pounds: 225),
            .straight(benchPress, sets: 1, reps: 3, pounds: 205)
        ])
        try await scene.memory.workouts.materialize(older, slotUpdates: [])
        await eventually { (try? scene.model.row(Self.bench)?.record) == "205" }
        #expect(try scene.model.names(.recent) == [Self.bench, "Back Squat"])
        #expect(try scene.model.row(Self.bench, in: .recent)?.meta == "Barbell · Chest · 4 sessions")
        #expect(try scene.model.row("Back Squat")?.record == "225")
        var edited = older.exercises[1]
        edited.sets[0].weight = .pounds(200)
        try await scene.memory.workouts.updateSets(workoutExerciseID: edited.id, sets: edited.sets)
        await eventually { (try? scene.model.row(Self.bench)?.record) == "200" }
        try await scene.memory.workouts.delete(id: older.id)
        await eventually { (try? scene.model.names(.recent)) == [Self.bench] }
        #expect(try scene.model.row(Self.bench)?.record == "195")
        #expect(try scene.model.row(Self.bench, in: .recent)?.meta == "Barbell · Chest · 3 sessions")
        #expect(try scene.model.row("Back Squat")?.record == "—")
    }
}
