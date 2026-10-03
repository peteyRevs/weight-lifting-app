import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// Product decision #26 moved every list and stats query from `ended_at` to `started_at`, and v002 added
/// `idx_workout_started (started_at DESC, id)` for them. Each query the change touched is run, its statements
/// are traced, and `EXPLAIN QUERY PLAN` of each must use the index it was written for, and scan no history
/// table without an index. No `ANALYZE` runs, as in the app.
@Suite("History query plans", .tags(.persistence), .timeLimit(.minutes(1)))
struct QueryPlanTests {
    /// A query, how to run it, and the index its statement must reach the workouts through.
    struct Query: Sendable, CustomStringConvertible {
        let description: String
        let index: String
        let run: @Sendable (Repositories) async throws -> Void
    }

    static let bench = WorkoutRepositoryContract.exercises[0].id

    static var week: Range<Date> {
        get throws {
            try StatsQueriesContract.calendar.week(containing: StatsQueriesContract.now)
        }
    }

    static let queries: [Query] = [
        Query(description: "recent", index: "SCAN workout USING INDEX idx_workout_started") { repositories in
            _ = try await repositories.workouts.recent(limit: 10)
        },
        Query(
            description: "workouts(in:)",
            index: "SEARCH workout USING INDEX idx_workout_started (started_at>? AND started_at<?)"
        ) { repositories in
            _ = try await repositories.workouts.workouts(in: week)
        },
        Query(
            description: "weeklyVolume",
            index: "SEARCH workout USING INDEX idx_workout_started (started_at>? AND started_at<?)"
        ) { repositories in
            _ = try await repositories.stats.weeklyVolume(in: week)
        },
        Query(
            description: "sessionsCompleted",
            index: "SEARCH workout USING INDEX idx_workout_started (started_at>? AND started_at<?)"
        ) { repositories in
            _ = try await repositories.stats.sessionsCompleted(in: week)
        },
        Query(
            description: "lastPerformance",
            index: "SEARCH workout_exercise USING INDEX idx_wex_exercise_workout"
        ) { repositories in
            _ = try await repositories.stats.lastPerformance(exerciseID: bench)
        },
        Query(
            description: "e1RMByWeek",
            index: "SEARCH workout_exercise USING INDEX idx_wex_exercise_workout"
        ) { repositories in
            _ = try await repositories.stats.e1RMByWeek(
                exerciseID: bench,
                lastWeeks: 8,
                calendar: StatsQueriesContract.calendar
            )
        },
        Query(
            description: "recentlyLogged",
            index: "SCAN workout_exercise USING INDEX idx_wex_exercise_workout"
        ) { repositories in
            _ = try await repositories.stats.recentlyLogged(limit: 5)
        }
    ]

    @Test("Each query the start date changed uses its index, and scans no history table bare", arguments: queries)
    func query_usesItsIndex(_ query: Query) async throws {
        let repositories = try await Repositories.withProgramExercises()
        var generator = SeededGenerator(seed: 26)
        let history = Seeders.history(
            exercises: ProgramRepositoryContract.exercises,
            workouts: 40,
            setsPerWorkout: 10,
            rng: &generator
        )
        for workout in history {
            try await repositories.history.materialize(workout)
        }
        let statements = try await repositories.statements(startingWith: "SELECT") { try await query.run(repositories) }
        #expect(!statements.isEmpty)
        var plans: [String] = []
        for statement in statements {
            plans += try await repositories.queue.read { database in
                try Row.fetchAll(database, sql: "EXPLAIN QUERY PLAN " + statement).map { $0["detail"] as String }
            }
        }
        #expect(plans.contains { $0.hasPrefix(query.index) }, "\(plans)")
        let bare = plans.filter { ["SCAN workout", "SCAN workout_exercise", "SCAN logged_set"].contains($0) }
        #expect(bare.isEmpty, "\(plans)")
        #expect(!plans.contains { $0.contains("idx_workout_ended") }, "no query dates a workout by its end")
    }
}
