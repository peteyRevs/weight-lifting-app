import Foundation
@testable import LedgerDomain
import Testing

@Suite("WorkoutState", .tags(.domain))
struct WorkoutStateTests {
    private func sample() throws -> WorkoutState {
        let bench = try Fixtures.workoutExercise(Fixtures.bench, index: 0, sets: [
            Fixtures.set(0, pounds: 185, reps: 5),
            Fixtures.set(1, pounds: 185, reps: 4),
            Fixtures.set(2, pounds: 185, reps: 5, done: false)
        ])
        let curl = try Fixtures.workoutExercise(Fixtures.barbellCurl, index: 1, sets: [
            Fixtures.set(3, pounds: 75, reps: 12),
            Fixtures.set(4, pounds: 65, reps: 12, kind: .drop)
        ])
        return Fixtures.workout([bench, curl])
    }

    @Test("Done and total sets count every exercise and kind")
    func setCounts_acrossExercises() throws {
        let state = try sample()
        #expect(state.doneSets == 4)
        #expect(state.totalSets == 5)
    }

    @Test("Volume sums weight × reps over done sets only (rule 34)")
    func volume_doneSetsOnly() throws {
        let expected = Weight.pounds(185).grams * 9 + Weight.pounds(75).grams * 12 + Weight.pounds(65).grams * 12
        #expect(try sample().volume == Volume(gramReps: expected))
    }

    @Test("Elapsed runs from startedAt to now, freezes at endedAt and is never negative (rule 24)")
    func elapsed_fromStartToNowOrEnd() throws {
        var state = try sample()
        #expect(state.elapsed(at: state.startedAt.addingTimeInterval(1234)) == .seconds(1234))
        #expect(state.elapsed(at: state.startedAt.addingTimeInterval(-60)) == .zero)
        state.endedAt = state.startedAt.addingTimeInterval(3600)
        state.phase = .finished
        #expect(state.elapsed(at: state.startedAt.addingTimeInterval(9999)) == .seconds(3600))
    }

    @Test("A workout state round-trips through JSON, including its rest timer")
    func codable_roundTrips() throws {
        var state = try sample()
        state.rest = RestTimer(endsAt: Fixtures.now, total: .seconds(90))
        state.source = WorkoutSource(
            programID: Fixtures.programID,
            weekIndex: 3,
            dayTemplateID: DayTemplateID(Fixtures.uuid(3))
        )
        state.exercises[0].lastPerformance = LastPerformance(date: Fixtures.now, sets: 5, reps: 5, load: .pounds(180))
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(WorkoutState.self, from: data) == state)
    }

    @Test("A logged set is done exactly when it has a doneAt time")
    func loggedSet_isDone() {
        #expect(Fixtures.set(0, pounds: 100, reps: 5).isDone)
        #expect(!Fixtures.set(1, pounds: 100, reps: 5, done: false).isDone)
    }

    @Test("A summary carries its receipt rows and PRs through JSON")
    func summary_codableRoundTrips() throws {
        let record = try PersonalRecord(
            exerciseID: Fixtures.bench.id,
            kind: .weightAtReps(.pounds(200), Fixtures.reps(5)),
            previous: .estimatedOneRepMax(.pounds(219)),
            achievedAt: Fixtures.now,
            workoutID: Fixtures.workoutID
        )
        let summary = WorkoutSummary(
            workoutID: Fixtures.workoutID,
            elapsed: .seconds(3480),
            doneSets: 17,
            totalSets: 18,
            volume: Volume(gramReps: 10_968_000),
            prs: [record],
            rows: [ReceiptRow(name: "Barbell Bench Press", target: "5 × 5 @ 185 lb", actual: ["5 × 185×5"])]
        )
        let data = try JSONEncoder().encode(summary)
        #expect(try JSONDecoder().decode(WorkoutSummary.self, from: data) == summary)
    }
}
