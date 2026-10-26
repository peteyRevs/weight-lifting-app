import Foundation
import LedgerDomain
import LedgerFakes
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F12 S2, N9, over F05's random history scripts (`HistoryScript`: edits, deletes, refused writes, zero loads, kg
/// beside lb, every kind of set, sets left undone, time zones and clock changes): after every step,
/// `exerciseSessions` reads the same on GRDB, on `HistoryModel` and on LedgerFakes' stores, and
/// `ExerciseHistory.make` of GRDB's sessions equals GRDB's own `bestE1RM`, `bestSet`, `sessionCount` and
/// `e1RMByWeek`. The contract clause pins one hand-made history; this one the random ones.
@Suite("F12 S2 · exerciseSessions and its fold", .tags(.persistence, .property), .timeLimit(.minutes(5)))
struct ExerciseSessionsPropertyTests {
    typealias History = HistoryModelAdversarialTests

    static let seeds = Array(PropertySeed.all.prefix(40))

    /// What the fold of `exercise`'s sessions says that GRDB's queries do not, or nil.
    static func foldMismatch(_ exercise: ExerciseID, _ stats: any StatsQueries, now: Date) async throws -> String? {
        let calendar = S3Kit.calendar()
        let history = try await ExerciseHistory.make(
            sessions: stats.exerciseSessions(exerciseID: exercise),
            records: [],
            now: now,
            calendar: calendar
        )
        let weeks = Dictionary(history.weeks.compactMap { week in
            week.e1RM.map { (calendar.isoWeekKey(for: week.start), $0) }
        }) { first, _ in first }
        let best = try await stats.bestSet(exerciseID: exercise).map { BestSet(weight: $0.weight, reps: $0.reps) }
        let e1RM = try await stats.bestE1RM(exerciseID: exercise)
        let count = try await stats.sessionCount(exerciseID: exercise)
        let byWeek = try await stats.e1RMByWeek(exerciseID: exercise, lastWeeks: 8, calendar: calendar)
        guard history.e1RM == e1RM, history.bestSet == best, history.sessions == count, weeks == byWeek else {
            return "fold \(history.e1RM as Any) \(history.bestSet as Any) \(history.sessions) \(weeks); "
                + "queries \(e1RM as Any) \(best as Any) \(count) \(byWeek)"
        }
        return nil
    }

    static func firstMismatch(_ seed: PropertySeed) async throws -> String? {
        var script = HistoryScript(seed: seed)
        let stack = try await S3Kit.stack()
        let stats = stack.stats(now: script.now)
        let model = HistoryModel(now: script.now)
        let now = script.now
        let fakes = InMemoryStores(now: { now })
        for step in 0 ..< 14 {
            let operation = script.next()
            stack.clock.advance()
            _ = await History.apply(operation, to: stack.workouts)
            _ = await History.apply(operation, to: model)
            _ = await History.apply(operation, to: fakes.workouts)
            for exercise in HistoryScript.exercises {
                let stored = try await stats.exerciseSessions(exerciseID: exercise)
                if try await stored != model.exerciseSessions(exerciseID: exercise) {
                    return "step \(step), \(operation): GRDB and the model differ"
                }
                if try await stored != fakes.stats.exerciseSessions(exerciseID: exercise) {
                    return "step \(step), \(operation): GRDB and the fakes differ"
                }
                if let fold = try await foldMismatch(exercise, stats, now: now) {
                    return "step \(step), \(operation): \(fold)"
                }
            }
        }
        return nil
    }

    @Test("Random histories: the sessions agree everywhere, and their fold is the queries'", arguments: seeds)
    func randomHistory_sessionsAgree_andFoldIsTheQueries(seed: PropertySeed) async throws {
        let mismatch = try await Self.firstMismatch(seed)
        #expect(mismatch == nil, "\(seed)")
    }
}
