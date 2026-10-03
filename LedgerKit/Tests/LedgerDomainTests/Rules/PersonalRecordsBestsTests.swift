import Foundation
@testable import LedgerDomain
import Testing

/// `PersonalRecords.Bests` (product decision #27): what `detect` judges a workout against, and how a workout
/// raises it, so a store can replay records over history.
@Suite("PersonalRecords.Bests", .tags(.domain))
struct PersonalRecordsBestsTests {
    private func workout(_ sets: [LoggedSet], deload: Bool = false) throws -> WorkoutState {
        try Fixtures.workout([Fixtures.workoutExercise(Fixtures.bench, index: 0, sets: sets)], isDeload: deload)
    }

    private func estimate(_ pounds: Decimal, _ reps: Int) -> Weight? {
        OneRepMax.brzycki(weight: .pounds(pounds), reps: Reps(clamping: reps))
    }

    @Test("A workout raises the bests with its done working and added sets only (decision #25), deload or not")
    func include_countsRecordSetsOnly() throws {
        var bests = PersonalRecords.Bests()
        try bests.include(workout([
            Fixtures.set(0, pounds: 200, reps: 5),
            Fixtures.set(1, pounds: 190, reps: 8, kind: .added),
            Fixtures.set(2, pounds: 150, reps: 15),
            Fixtures.set(3, pounds: 300, reps: 1, kind: .warmup),
            Fixtures.set(4, pounds: 280, reps: 2, kind: .drop),
            Fixtures.set(5, pounds: 400, reps: 5, done: false)
        ]))
        #expect(bests.e1RM == [Fixtures.bench.id: estimate(190, 8) ?? .zero]) // 15 reps have no estimate
        #expect(try bests.weightAtReps == [Fixtures.bench.id: [
            Fixtures.reps(5): .pounds(200), Fixtures.reps(8): .pounds(190), Fixtures.reps(15): .pounds(150)
        ]])
        // A lighter set never lowers a best; a deload's heavier set raises it.
        try bests.include(workout([Fixtures.set(0, pounds: 180, reps: 5)]))
        try bests.include(workout([Fixtures.set(0, pounds: 210, reps: 5)], deload: true))
        #expect(try bests.weightAtReps[Fixtures.bench.id]?[Fixtures.reps(5)] == .pounds(210))
        #expect(bests.e1RM[Fixtures.bench.id] == estimate(210, 5))
    }

    @Test("bestSet is the heaviest set of the bests, and of two as heavy the one with more reps")
    func bestSet_isHeaviest_thenMoreReps() throws {
        let bests = try PersonalRecords.Bests(weightAtReps: [Fixtures.bench.id: [
            Fixtures.reps(3): .pounds(210), Fixtures.reps(5): .pounds(210), Fixtures.reps(8): .pounds(190)
        ]])
        let best = try #require(bests.bestSet(of: Fixtures.bench.id))
        #expect(best.weight == .pounds(210))
        #expect(try best.reps == Fixtures.reps(5))
        #expect(bests.bestSet(of: ExerciseID(Fixtures.uuid(404))) == nil)
    }

    @Test("Detecting against bests is detecting against its two maps; replaying a history sets each record once")
    func detectAgainstBests_replaysAHistory() throws {
        var bests = PersonalRecords.Bests()
        var found: [[PRKind]] = []
        for pounds: Decimal in [200, 210, 205, 215] {
            let session = try workout([Fixtures.set(0, pounds: pounds, reps: 5)])
            let records = PersonalRecords.detect(workout: session, against: bests, now: Fixtures.now)
            #expect(records == PersonalRecords.detect(
                workout: session,
                bestE1RM: bests.e1RM,
                bestWeightAtReps: bests.weightAtReps,
                now: Fixtures.now
            ))
            found.append(records.map(\.kind))
            bests.include(session)
        }
        let five = try Fixtures.reps(5)
        #expect(found == [
            [], // the first workout is a baseline
            [.estimatedOneRepMax(estimate(210, 5) ?? .zero), .weightAtReps(.pounds(210), five)],
            [],
            [.estimatedOneRepMax(estimate(215, 5) ?? .zero), .weightAtReps(.pounds(215), five)]
        ])
    }
}
