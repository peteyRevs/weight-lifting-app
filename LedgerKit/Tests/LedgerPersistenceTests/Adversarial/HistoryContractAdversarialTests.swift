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

    /// Sanctioned edits: 24 since the `bestSets` clause (F12 S1, N3), 25 since `exerciseSessions` (F12 S2, N9).
    @Test("An honest in-memory history keeps all 25 clauses, so the contracts need no database")
    func honestFake_keepsEveryClause() async {
        #expect(Self.clauses.count == 25)
        #expect(await Self.broken(by: []) == [])
    }

    /// The faults no clause catches: none since S3 fix round 1, which closed the ten that round 1 listed here
    /// (finding S3-4; orchestrator decision, 2026-10-01). A new fault that no clause catches fails the test.
    static let uncaught: Set<Fault> = []

    @Test("Every wrong fake breaks at least one contract clause", arguments: Fault.allCases)
    func wrongFake_isCaughtOrListed(fault: Fault) async {
        let broken = await Self.broken(by: [fault])
        #expect(broken.isEmpty == Self.uncaught.contains(fault), "\(fault.rawValue): \(broken)")
    }
}
