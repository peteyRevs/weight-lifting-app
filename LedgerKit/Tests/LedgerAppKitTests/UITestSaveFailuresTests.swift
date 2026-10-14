import Dependencies
import Foundation
@testable import LedgerAppKit
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S7a, fix round 1: a UI test's failing save, `-LEDGER_UITEST_FAIL_FINISH <count>` beside
/// `-LEDGER_UITEST`, read as `UITestClock` reads its argument.
@Suite("UITestSaveFailures", .timeLimit(.minutes(1)))
struct UITestSaveFailuresTests {
    @Test("The count is read beside -LEDGER_UITEST, and only there")
    func count_isReadOnlyForAUITest() throws {
        #expect(try UITestSaveFailures.count(arguments: [
            "Ledger",
            "-LEDGER_UITEST",
            "1",
            "-LEDGER_UITEST_FAIL_FINISH",
            "3"
        ]) == 3)
        #expect(try UITestSaveFailures.count(arguments: ["Ledger", "-LEDGER_UITEST", "1"]) == nil)
        #expect(try UITestSaveFailures.count(arguments: ["Ledger", "-LEDGER_UITEST_FAIL_FINISH", "3"]) == nil)
    }

    @Test("A count that is missing, not a number or under 1 is refused", arguments: [nil, "none", "0", "-2"])
    func count_refusesWhatIsNoCount(value: String?) {
        let arguments = ["Ledger", "-LEDGER_UITEST", "1", "-LEDGER_UITEST_FAIL_FINISH"] + [value].compactMap(\.self)
        #expect(throws: UITestSaveFailures.InvalidCount(value: value)) {
            try UITestSaveFailures.count(arguments: arguments)
        }
    }

    @Test("The bound session refuses the first finishes, then saves; nothing reached the host before")
    func boundSession_failsThenSaves() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.composition(failedFinishes: 2)
        composition.boot()
        let session = withDependencies {
            $0.context = .live
            composition.bind(&$0)
        } operation: {
            @Dependency(\.workoutSession) var session
            return session
        }
        #expect(session is UITestFailingFinishSession)
        let workout = EventBuilders.seedSession()
        try await session.start(workout)
        let row = workout.exercises[0].sets[0]
        _ = try await session.apply(.setLogged(
            exerciseIndex: 0, setID: row.id, weight: row.weight, reps: row.reps, doneAt: Harness.now
        ))
        for _ in 0 ..< 2 {
            await #expect(throws: UITestFailingFinishSession.Refused.self) {
                _ = try await session.finish(endedAt: Harness.now)
            }
            #expect(try await session.current()?.phase == .live)
        }
        #expect(try await session.finish(endedAt: Harness.now).phase == .finished)
    }

    @Test("Without the argument the composition binds the host itself")
    func withoutTheArgument_bindsTheHost() {
        let harness = Harness()
        defer { harness.remove() }
        let session = withDependencies {
            $0.context = .live
            harness.booted().bind(&$0)
        } operation: {
            @Dependency(\.workoutSession) var session
            return session
        }
        #expect(!(session is UITestFailingFinishSession))
    }
}
