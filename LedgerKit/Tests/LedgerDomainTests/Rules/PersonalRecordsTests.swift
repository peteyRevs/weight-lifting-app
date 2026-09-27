import Foundation
@testable import LedgerDomain
import Testing

@Suite("PersonalRecords", .tags(.domain))
struct PersonalRecordsTests {
    private func workout(_ sets: [LoggedSet], deload: Bool = false) throws -> WorkoutState {
        try Fixtures.workout([Fixtures.workoutExercise(Fixtures.bench, index: 0, sets: sets)], isDeload: deload)
    }

    private func detect(
        _ workout: WorkoutState,
        e1RM: Weight? = nil,
        atReps: [Int: Decimal] = [:]
    ) throws -> [PersonalRecord] {
        let history = try Dictionary(uniqueKeysWithValues: atReps.map { try (
            Fixtures.reps($0.key),
            Weight.pounds($0.value)
        ) })
        return PersonalRecords.detect(
            workout: workout,
            bestE1RM: e1RM.map { [Fixtures.bench.id: $0] } ?? [:],
            bestWeightAtReps: [Fixtures.bench.id: history],
            now: Fixtures.now
        )
    }

    @Test("200 × 5 beats a 219 lb e1RM with 225 lb, and 195 at ≥ 5 reps by weight (decision #3, criterion 12)")
    func detect_newBestE1RM() throws {
        let records = try detect(workout([Fixtures.set(0, pounds: 200, reps: 5)]), e1RM: .pounds(219), atReps: [5: 195])
        let five = try Fixtures.reps(5)
        #expect(records.map(\.kind) == [.estimatedOneRepMax(.pounds(225)), .weightAtReps(.pounds(200), five)])
        #expect(records.map(\.previous) == [.estimatedOneRepMax(.pounds(219)), .weightAtReps(.pounds(195), five)])
        #expect(records.allSatisfy { $0.exerciseID == Fixtures.bench.id && $0.workoutID == Fixtures.workoutID })
        #expect(records.allSatisfy { $0.achievedAt == Fixtures.now })
    }

    @Test("A weight PR compares against the best weight at the same or more reps (decision #3)")
    func detect_newBestWeightAtSameOrMoreReps() throws {
        let eights = try detect(workout([Fixtures.set(0, pounds: 180, reps: 8)]), atReps: [5: 195, 8: 170])
        #expect(try eights.map(\.kind) == [.weightAtReps(.pounds(180), Fixtures.reps(8))])
        #expect(try eights.map(\.previous) == [.weightAtReps(.pounds(170), Fixtures.reps(8))])
        let sixes = try detect(workout([Fixtures.set(0, pounds: 190, reps: 6)]), atReps: [5: 200, 8: 185])
        #expect(try sixes.map(\.kind) == [.weightAtReps(.pounds(190), Fixtures.reps(6))])
        #expect(try sixes.map(\.previous) == [.weightAtReps(.pounds(185), Fixtures.reps(8))])
        let noHistoryAbove = try detect(workout([Fixtures.set(0, pounds: 150, reps: 10)]), atReps: [5: 200])
        #expect(noHistoryAbove.isEmpty)
    }

    @Test("The heaviest beaten set is the weight PR")
    func detect_reportsHeaviestWeightRecord() throws {
        let sets = [Fixtures.set(0, pounds: 180, reps: 8), Fixtures.set(1, pounds: 200, reps: 3)]
        let records = try detect(workout(sets), atReps: [3: 190, 8: 170])
        #expect(try records.map(\.kind) == [.weightAtReps(.pounds(200), Fixtures.reps(3))])
    }

    @Test("Nothing is a PR when every set is below history")
    func detect_none_whenBelowHistory() throws {
        let sets = (0 ..< 5).map { Fixtures.set($0, pounds: 185, reps: 5) }
        #expect(try detect(workout(sets), e1RM: .pounds(219), atReps: [5: 195]).isEmpty)
    }

    @Test("Sets above 12 reps never produce an e1RM PR (decision #4)")
    func detect_ignoresE1RMAbove12Reps() throws {
        let records = try detect(
            workout([Fixtures.set(0, pounds: 150, reps: 15)]),
            e1RM: .pounds(100),
            atReps: [15: 140]
        )
        #expect(try records.map(\.kind) == [.weightAtReps(.pounds(150), Fixtures.reps(15))])
    }

    @Test("Ties are not PRs")
    func detect_tiesAreNotRecords() throws {
        let set = Fixtures.set(0, pounds: 200, reps: 5)
        let e1RM = try #require(OneRepMax.brzycki(weight: set.weight, reps: set.reps))
        #expect(try detect(workout([set]), e1RM: e1RM, atReps: [5: 200]).isEmpty)
    }

    @Test("Deload workouts never produce PRs (decision #3)")
    func detect_deload_none() throws {
        let heavy = [Fixtures.set(0, pounds: 300, reps: 5)]
        #expect(try detect(workout(heavy, deload: true), e1RM: .pounds(219), atReps: [5: 195]).isEmpty)
    }

    @Test("A first session is a baseline: no history means no PR")
    func detect_noHistory_none() throws {
        #expect(try detect(workout([Fixtures.set(0, pounds: 135, reps: 5)])).isEmpty)
    }

    @Test("Only done working and added sets count; drop, warm-up and undone sets do not")
    func detect_countsWorkingAndAddedOnly() throws {
        let ignored = [
            Fixtures.set(0, pounds: 300, reps: 5, kind: .drop),
            Fixtures.set(1, pounds: 300, reps: 5, kind: .warmup),
            Fixtures.set(2, pounds: 300, reps: 5, done: false)
        ]
        #expect(try detect(workout(ignored), e1RM: .pounds(219), atReps: [5: 195]).isEmpty)
        let added = [Fixtures.set(3, pounds: 200, reps: 5, kind: .added)]
        #expect(try detect(workout(added), e1RM: .pounds(219)).count == 1)
    }

    @Test("An exercise done in two slots yields one record of each kind, in workout order")
    func detect_groupsByExercise() throws {
        let first = try Fixtures.workoutExercise(
            Fixtures.bench,
            index: 0,
            sets: [Fixtures.set(0, pounds: 200, reps: 5)]
        )
        let squat = try Fixtures.workoutExercise(
            Fixtures.backSquat,
            index: 1,
            sets: [Fixtures.set(1, pounds: 300, reps: 5)]
        )
        let second = try Fixtures.workoutExercise(
            Fixtures.bench,
            index: 2,
            sets: [Fixtures.set(2, pounds: 205, reps: 5)]
        )
        let records = PersonalRecords.detect(
            workout: Fixtures.workout([first, squat, second]),
            bestE1RM: [Fixtures.bench.id: .pounds(219), Fixtures.backSquat.id: .pounds(300)],
            bestWeightAtReps: [:],
            now: Fixtures.now
        )
        let best = try #require(OneRepMax.brzycki(weight: .pounds(205), reps: Fixtures.reps(5)))
        #expect(records.map(\.exerciseID) == [Fixtures.bench.id, Fixtures.backSquat.id])
        #expect(records.first?.kind == .estimatedOneRepMax(best))
    }
}
