import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// `WorkoutEventStore`'s documented contract, pinned on the in-memory reference store. The clauses live
/// in `LedgerTestSupport` (`WorkoutEventStoreContract`, moved there by F05), and F05's GRDB store runs
/// the same ones in `LedgerPersistenceTests`.
///
/// Fix round 2 (finding 10) folded in the tester's nine `StoreProbe`s, so the suite kills every mutant
/// in `EventStoreMutationAdversarialTests`, which stays as the suite's own guard.
@Suite("WorkoutEventStore · contract", .tags(.domain))
struct WorkoutEventStoreContractTests {
    @Test("The in-memory reference store keeps the clause", arguments: WorkoutEventStoreContract.clauses)
    func clause_holds(_ clause: WorkoutEventStoreContract.Clause) async throws {
        let issue = try await clause.check(InMemoryWorkoutEventStore())
        #expect(issue == nil, "\(clause.name): \(issue ?? "")")
    }
}
