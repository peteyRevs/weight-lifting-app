import Foundation
import LedgerDomain
import LedgerPersistence
import LedgerTestSupport
import Testing

/// F05 S3 adversarial round 1: would the contracts in `LedgerTestSupport` catch a wrong fake? F07's in-memory
/// fakes run `WorkoutRepositoryContract` and `StatsQueriesContract`, and nothing else ties them to the GRDB
/// semantics. `HistoryModel` with no fault keeps every clause; with one fault it is a plausible wrong fake,
/// and a fault no clause catches is a gap in the contract (finding S3-5).
@Suite("Adversarial S3 · the history contracts against wrong fakes", .tags(.persistence), .timeLimit(.minutes(1)))
struct HistoryContractAdversarialTests {
    typealias Fault = HistoryModel.Fault

    static let clauses = WorkoutRepositoryContract.clauses + StatsQueriesContract.clauses

    /// The clauses a fake with `faults` breaks, by name.
    static func broken(by faults: Set<Fault>) async -> [String] {
        var broken: [String] = []
        for clause in clauses {
            let model = HistoryModel(faults: faults, now: StatsQueriesContract.now)
            let stores = HistoryStores(workouts: model, stats: model, programs: model)
            do {
                if let issue = try await clause.check(stores) {
                    broken.append("\(clause.name): \(issue)")
                }
            } catch {
                broken.append("\(clause.name): threw \(error)")
            }
        }
        return broken
    }

    @Test("An honest in-memory history keeps all 21 clauses, so the contracts need no database")
    func honestFake_keepsEveryClause() async {
        #expect(Self.clauses.count == 21)
        #expect(await Self.broken(by: []) == [])
    }

    /// The faults no clause catches today. Each is a way a fake could differ from the GRDB types unnoticed.
    static let uncaught: Set<Fault> = [
        .tiesInInsertionOrder, .lastIsFirstSet, .bestsCountWarmups, .weeksInUTCFromMonday, .weeksByTickTime,
        .sessionsNeedADoneSet, .recordsByWorkoutDate, .recentlyLoggedInWorkoutOrder, .editDropsRecords,
        .emitsEveryWrite
    ]

    @Test("(documents) Which wrong fakes the contracts catch, and which they let through", arguments: Fault.allCases)
    func wrongFake_isCaughtOrListed(fault: Fault) async {
        let broken = await Self.broken(by: [fault])
        #expect(broken.isEmpty == Self.uncaught.contains(fault), "\(fault.rawValue): \(broken)")
    }
}
