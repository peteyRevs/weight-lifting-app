import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S3 close-out round: the fix of S3-3 (a parent id must be stored as text), the `phase` filter on the
/// lists (review N1, tester S3-N2), and the contracts as tightened for S3-4.
@Suite("Adversarial S3 close-out · parent ids, phases and contracts", .tags(.persistence), .timeLimit(.minutes(1)))
struct HistoryCloseoutAdversarialTests {
    static let first = S3Kit.mixed(1)

    /// Finding S3-5. `UUID(uuidString:)` reads lowercase text, so the id passes `ColumnReader.identifier` and
    /// the new storage check; SQL compares it with its children's uppercase `…_id` and finds none. It is
    /// S3-3's symptom, through text.
    @Test("An exercise row whose id is its uuid in lowercase fails the read, or reads whole: never without its sets")
    func lowercaseExerciseID_neverReadsAsAnEmptyExercise() async throws {
        let stack = try await S3Kit.stack()
        try await stack.materialize(Self.first)
        try await stack.damage("UPDATE workout_exercise SET id = lower(id) WHERE position = 0")
        let read = try? await stack.workouts.workout(id: Self.first.id)
        #expect(
            read == nil || read == Self.first,
            "read with sets \(String(describing: read?.exercises.map(\.sets.count)))"
        )
        let listed = try await stack.workouts.recent(limit: 5)
        #expect(listed == [] || listed == [Self.first])
        try await stack.materialize(Self.first)
        #expect(try await stack.workouts.workout(id: Self.first.id) == Self.first)
    }

    @Test("A workout row whose id is its uuid in lowercase is left out, or reads whole; a rebuild stores it once")
    func lowercaseWorkoutID_neverReadsAsAnEmptyWorkout() async throws {
        let stack = try await S3Kit.stack()
        try await stack.materialize(Self.first)
        try await stack.damage("UPDATE workout SET id = lower(id)")
        let listed = try await stack.workouts.recent(limit: 5)
        #expect(listed == [] || listed == [Self.first], "listed with \(listed.map(\.exercises.count)) exercises")
        try await stack.materialize(Self.first)
        #expect(try await stack.workouts.recent(limit: 5) == [Self.first], "the workout is listed twice")
    }

    @Test(
        "A parent id that is text but no uuid fails the read by name, hides only its workout, and a rebuild repairs it",
        arguments: [
            "workout_exercise SET id = 'nope'", "workout_exercise SET id = ''", "workout_exercise SET id = 7",
            "workout_exercise SET id = id || ' '", "workout SET id = 'nope'", "workout SET id = 7.5"
        ]
    )
    func textIDThatIsNoUUID_isDamage(damage: String) async throws {
        let stack = try await S3Kit.stack()
        let other = S3Kit.mixed(2, endedAt: S3Kit.day(-1))
        try await stack.materialize(Self.first)
        try await stack.materialize(other)
        try await stack.damage(
            "UPDATE \(damage) WHERE \(damage.hasPrefix("workout_exercise") ? "position = 0 AND workout_id" : "id") = ?",
            [
                Self.first.id.rawValue.uuidString
            ]
        )
        #expect(try await stack.workouts.recent(limit: 5) == [other])
        if damage.hasPrefix("workout_exercise") {
            await #expect(throws: LedgerPersistenceError.self) {
                _ = try await stack.workouts.workout(id: Self.first.id)
            }
        } else {
            #expect(try await stack.workouts.workout(id: Self.first.id) == nil)
        }
        try await stack.materialize(Self.first)
        #expect(try await stack.workouts.recent(limit: 5) == [Self.first, other])
        #expect(try await stack.workouts.workout(id: Self.first.id) == Self.first)
    }

    @Test("A row of another phase takes no place of the limit and moves no other workout; it is in no range")
    func foreignPhase_takesNoPlace() async throws {
        let stack = try await S3Kit.stack()
        let workouts = (1 ... 4).map { S3Kit.mixed($0, endedAt: S3Kit.day(Double(-$0))) }
        for workout in workouts {
            try await stack.materialize(workout)
        }
        let newest = workouts[0].id.rawValue.uuidString
        for phase in ["live", "discarded", "paused", "FINISHED", ""] {
            try await stack.execute("UPDATE workout SET phase = ? WHERE id = ?", [phase, newest])
            #expect(try await stack.workouts.recent(limit: 2) == [workouts[1], workouts[2]], "\(phase)")
            #expect(try await stack.workouts
                .workouts(in: S3Kit.day(-9) ..< S3Kit.day(9)) == Array(workouts.dropFirst()))
            #expect(try await stack.stats().sessionsCompleted(in: S3Kit.day(-9) ..< S3Kit.day(9)) == 3)
        }
        try await stack.materialize(workouts[0])
        #expect(try await stack.workouts.recent(limit: 2) == [workouts[0], workouts[1]])
    }

    @Test("The observation emits once when a listed row leaves its phase, and not for a write that changes no list")
    func observation_followsThePhaseFilter() async throws {
        let stack = try await S3Kit.stack()
        let workouts = (1 ... 3).map { S3Kit.mixed($0, endedAt: S3Kit.day(Double(-$0))) }
        for workout in workouts {
            try await stack.materialize(workout)
        }
        let observation = GRDBWorkoutRepository.recentObservation(limit: 2)
        var values = ObservationTests.everyValue(observation, in: stack.queue).makeAsyncIterator()
        #expect(await values.next() == [workouts[0], workouts[1]])
        try await stack.execute(
            "UPDATE workout SET phase = 'discarded' WHERE id = ?",
            [workouts[0].id.rawValue.uuidString]
        )
        #expect(await values.next() == [workouts[1], workouts[2]])
        // The hidden row changes again, and a row outside the list: neither changes the list.
        try await stack.execute(
            "UPDATE workout SET phase = 'live', name = 'x' WHERE id = ?",
            [workouts[0].id.rawValue.uuidString]
        )
        try await stack.materialize(S3Kit.mixed(4, endedAt: S3Kit.day(-4)))
        try await stack.materialize(workouts[0])
        #expect(await values.next() == [workouts[0], workouts[1]])
    }

    /// The clause that must catch each wrong fake: the one about the behaviour the fake gets wrong, by a word of
    /// its name. A fake caught only by some other clause is caught by accident, and the next fixture change
    /// could let it through again.
    static let catchingClause: [HistoryModel.Fault: String] = [
        .tiesInInsertionOrder: "newest first", .datedByStart: "newest first", .hardDelete: "even deleted",
        .keepsLiveFields: "reads back equal", .lastIsFirstSet: "lastPerformance",
        .lastCountsEveryKind: "lastPerformance",
        .lastOfAnyWorkout: "lastPerformance", .bestsCountWarmups: "bestSet", .bestsCountDrops: "bestSet",
        .bestSetFewerReps: "bestSet", .estimatesAbove12Reps: "bestE1RM", .weeksInUTCFromMonday: "e1RMByWeek",
        .weeksByTickTime: "e1RMByWeek", .futureWeeksCount: "e1RMByWeek", .volumeSkipsWarmups: "weeklyVolume",
        .sessionsNeedADoneSet: "sessionsCompleted", .sessionCountIgnoresDone: "sessionCount",
        .recordsByWorkoutDate: "personalRecords", .recordsInGivenOrder: "personalRecords",
        .recentlyLoggedInWorkoutOrder: "recentlyLogged", .editDropsRecords: "updateSets",
        .emitsEveryWrite: "observeRecent", .missesAreMerged: "slotUpdates", .closedRanges: "workouts(in:)",
        .negativeLimitIsAll: "limit"
    ]

    @Test(
        "Each wrong fake is caught by the clause about what it gets wrong, not by another one",
        arguments: HistoryModel.Fault.allCases
    )
    func wrongFake_isCaughtByItsOwnClause(fault: HistoryModel.Fault) async throws {
        let word = try #require(Self.catchingClause[fault])
        let broken = await HistoryContractAdversarialTests.broken(by: [fault])
        #expect(broken.contains { $0.contains(word) }, "\(fault.rawValue) is caught only by \(broken)")
    }
}
