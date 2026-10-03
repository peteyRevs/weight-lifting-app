import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S3 adversarial round 1: the history lists: ties, limits, ranges, rows of other phases, and the
/// observation.
@Suite("Adversarial S3 · history reads", .tags(.persistence), .timeLimit(.minutes(1)))
struct HistoryReadAdversarialTests {
    @Test("Workouts that ended at one instant list in id order, whatever order they were stored in", arguments: 0 ..< 6)
    func ties_listInIDOrder(rotation: Int) async throws {
        let stack = try await S3Kit.stack()
        let tied = [3, 1, 4, 2].map { S3Kit.mixed($0) }
        let earlier = S3Kit.mixed(5, endedAt: S3Kit.now.addingTimeInterval(-0.000_001))
        var order = tied + [earlier]
        order.swapAt(rotation % 5, (rotation * 2 + 1) % 5)
        for workout in order {
            try await stack.materialize(workout)
        }
        let sorted = tied.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString } + [earlier]
        #expect(try await stack.workouts.recent(limit: 10) == sorted)
        #expect(try await stack.workouts.recent(limit: 2) == Array(sorted.prefix(2)))
        #expect(try await stack.workouts.workouts(in: S3Kit.day(-1) ..< S3Kit.day(1)) == sorted)
        // A re-materialisation and a delete keep the order of the rest.
        stack.clock.advance()
        try await stack.materialize(tied[0])
        try await stack.workouts.delete(id: tied[1].id)
        #expect(try await stack.workouts.recent(limit: 10) == sorted.filter { $0.id != tied[1].id })
    }

    @Test("A range holds its lower bound and not its upper; an empty or infinite range, and any limit, are safe")
    func rangesAndLimits_atTheirEdges() async throws {
        let stack = try await S3Kit.stack()
        // Workout i starts at day i (product decision #26: a range selects by start); each lasts 45 minutes.
        let workouts = (0 ..< 4).map { S3Kit.mixed($0 + 1, endedAt: S3Kit.day(Double($0)).addingTimeInterval(45 * 60)) }
        for workout in workouts {
            try await stack.materialize(workout)
        }
        let repository = stack.workouts
        let (first, last) = (S3Kit.day(0), S3Kit.day(3))
        #expect(try await repository.workouts(in: first ..< last).map(\.id) == [3, 2, 1].map(S3Kit.workoutID))
        #expect(try await repository.workouts(in: first ..< first) == [])
        #expect(try await repository.workouts(in: last ..< last.addingTimeInterval(0.001)) == [workouts[3]])
        let infinity = Date(timeIntervalSinceReferenceDate: .infinity)
        let always = Date(timeIntervalSinceReferenceDate: -.infinity) ..< infinity
        #expect(try await repository.workouts(in: always) == workouts.reversed())
        #expect(try await repository.workouts(in: infinity ..< infinity) == [])
        #expect(try await repository.recent(limit: .max) == workouts.reversed())
        #expect(try await repository.recent(limit: .min) == [])
        #expect(try await stack.stats().recentlyLogged(limit: .max) == [S3Kit.bench, S3Kit.squat])
        #expect(try await stack.stats().recentlyLogged(limit: .min) == [])
        #expect(try await stack.stats().sessionsCompleted(in: always) == 4)
        #expect(try await stack.stats().weeklyVolume(in: last ..< infinity) == workouts[3].volume)
    }

    /// (documents) Finding S3-N1. `recent(limit:)` picks its rows before it reads them, so an unreadable
    /// workout uses up a place: the list is shorter than the limit although more readable workouts exist.
    @Test("(documents) An unreadable workout among the newest takes a place of the limit")
    func unreadableWorkout_takesAPlaceOfTheLimit() async throws {
        let stack = try await S3Kit.stack()
        let workouts = (1 ... 4).map { S3Kit.mixed($0, endedAt: S3Kit.day(Double(-$0))) }
        for workout in workouts {
            try await stack.materialize(workout)
        }
        try await stack.execute("UPDATE workout SET units = 'stone' WHERE id = ?", [workouts[0].id.rawValue.uuidString])
        #expect(try await stack.workouts.recent(limit: 2) == [workouts[1]])
        #expect(try await stack.workouts.recent(limit: 4) == Array(workouts.dropFirst()))
    }

    /// Finding S3-N2. Only `materialize` writes `workout`, and only finished workouts. A row in another phase
    /// can come from a foreign writer alone. Round 1 documented that the lists showed it while the stats
    /// skipped it; since S3 fix round 1 (orchestrator decision, 2026-10-01) the lists skip it too. A finished
    /// row with no end is foreign damage too (`materialize` refuses a workout without one): since S3 fix round 3
    /// (orchestrator decision, 2026-10-02) it is listed nowhere and counted nowhere, and the "Last" line skips it.
    @Test("A stored row that is not finished, or has no end, is listed nowhere and counts for no stats")
    func foreignPhase_isListedButNotCounted() async throws {
        let stack = try await S3Kit.stack()
        let workout = S3Kit.mixed(1)
        try await stack.materialize(workout)
        try await stack.execute("UPDATE workout SET phase = 'discarded'")
        let always = Date.distantPast ..< Date.distantFuture
        #expect(try await stack.workouts.recent(limit: 5) == [])
        #expect(try await stack.workouts.workouts(in: always) == [])
        #expect(try await stack.stats().sessionsCompleted(in: always) == 0)
        #expect(try await stack.stats().weeklyVolume(in: always) == .zero)
        try await stack.execute("UPDATE workout SET phase = 'finished', ended_at = NULL")
        #expect(try await stack.workouts.recent(limit: 5) == [])
        #expect(try await stack.workouts.workouts(in: always) == [])
        #expect(try await stack.stats().sessionsCompleted(in: always) == 0)
        #expect(try await stack.stats().weeklyVolume(in: always) == .zero)
        #expect(try await stack.stats().lastPerformance(exerciseID: S3Kit.bench) == nil)
    }

    @Test("The observation emits for a change in its list only: not for records, misses, or a workout outside it")
    func observation_emitsOnlyOnChange() async throws {
        let stack = try await S3Kit.stack()
        let program = try S2Kit.program(1, weeks: 3, days: 2, slotsPerDay: 2)
        try await stack.programs.save(program)
        let workouts = (0 ..< 3).map { S3Kit.mixed($0 + 1, endedAt: S3Kit.day(Double($0))) }
        let observation = GRDBWorkoutRepository.recentObservation(limit: 2)
        var values = ObservationTests.everyValue(observation, in: stack.queue).makeAsyncIterator()
        #expect(await values.next() == [])
        try await stack.materialize(workouts[1])
        #expect(await values.next() == [workouts[1]])
        // None of these changes the two newest workouts as values.
        var slot = program.days[0].slots[0]
        slot.misses = [0, 1, 2]
        let record = S3Kit.record(S3Kit.bench, .estimatedOneRepMax(.pounds(215)), in: workouts[1])
        try await stack.materialize(workouts[1], prs: [record], slots: [slot])
        try await stack.workouts.updateSets(
            workoutExerciseID: workouts[1].exercises[0].id,
            sets: workouts[1].exercises[0].sets
        )
        try await stack.workouts.delete(id: workouts[0].id)
        try await stack.materialize(workouts[2])
        #expect(await values.next() == [workouts[2], workouts[1]])
        try await stack.materialize(workouts[0]) // third newest
        try await stack.workouts.delete(id: workouts[0].id)
        // Damage hides a workout, the stream goes on, and a repair brings it back.
        try await stack.execute("UPDATE workout SET units = 'stone' WHERE id = ?", [workouts[2].id.rawValue.uuidString])
        #expect(await values.next() == [workouts[1]])
        try await stack.materialize(workouts[2])
        #expect(await values.next() == [workouts[2], workouts[1]])
    }

    @Test("Readers racing sixteen re-materialisations of one workout see only whole states; the last one is stored")
    func racingWrites_areWhole() async throws {
        let stack = try await S3Kit.stack()
        let states = (0 ..< 16).map { index in
            S3Kit.workout(
                1,
                [S3Kit.RowSpec(S3Kit.bench, Array(repeating: S3Kit.set(Decimal(100 + index), 5), count: index % 5))]
            )
        }
        try await stack.materialize(states[0])
        let seen = try await withThrowingTaskGroup(of: [WorkoutState].self) { group in
            for state in states {
                group.addTask {
                    try await stack.materialize(state)
                    return try await stack.workouts.recent(limit: 3)
                }
            }
            return try await group.reduce(into: []) { $0 += $1 }
        }
        #expect(seen.allSatisfy { states.contains($0) })
        let final = try #require(try await stack.workouts.workout(id: S3Kit.workoutID(1)))
        #expect(states.contains(final))
        #expect(try await stack.liveCounts() == S3Kit.expectedCounts([final]))
    }
}
