import Dispatch
import Foundation
import GRDB
@testable import LedgerAppKit
import LedgerPersistence
import Testing

/// F07 S2 close-out: the shared `DatabaseLaunch` (fix round 1) when a cancellation lands while a step waits for the
/// database, beneath a foreground call that overlaps it, as `.task(id: scenePhase)` produces on a first launch that
/// passes from `.inactive` to `.active`; and the UI-test boot rule.
@Suite("Adversarial F07 S2 close-out · iPhone launch", .timeLimit(.minutes(1)))
struct LaunchCloseoutAdversarialTests {
    /// Holds the database's writer until `release()`: what the seed and the settings then wait for.
    final class WriterHold: @unchecked Sendable {
        private let held = DispatchSemaphore(value: 0)
        private let release = DispatchSemaphore(value: 0)

        init(_ queue: DatabaseQueue) {
            DispatchQueue.global().async { [held, release] in
                queue.inDatabase { _ in
                    held.signal()
                    release.wait()
                }
            }
            held.wait()
        }

        func free() {
            release.signal()
        }
    }

    @Test("F7-S2-3: a seed cancelled while it waits, beneath an overlapping foreground call, is run by the next call")
    func seedCancelledBeneathAForegroundCall_runsOnTheNextCall() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.booted()
        let queue = try #require(composition.stores).queue
        let hold = WriterHold(queue)
        // The first call (phase .inactive) starts the seed and waits for the writer.
        let first = Task { await composition.resume(in: .inactive) }
        await Task.yield()
        // The phase becomes .active: SwiftUI starts the second call and cancels the first.
        let second = Task { await composition.resume(in: .active) }
        await Task.yield()
        first.cancel()
        hold.free()
        await first.value
        await second.value
        // The seed never ran to an end in either call, so the first pass has not either: the next call runs it, in
        // any phase (a later .background one here, or the next foreground).
        await composition.resume(in: .background)
        #expect(composition.isCatalogSeeded, "\(LaunchAdversarialTests.spelled(harness.log))")
    }

    @Test("A cancelled pass followed by a background call seeds and loads the settings")
    func cancelledPass_thenBackground_runsIt() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.booted()
        let first = Task { await composition.resume(in: .active) }
        first.cancel()
        await first.value
        await composition.resume(in: .background)
        #expect(composition.isCatalogSeeded)
        let spelled = LaunchAdversarialTests.spelled(harness.log)
        // Sanctioned edit (F07 S2 fix round 2): each step begins exactly once (was: settings twice, the abandoned-
        // then-restarted mechanism that round removed); "not seeded right after the cancelled call" dropped.
        #expect(spelled.filter { $0 == "began seedCatalog" }.count == 1)
        #expect(spelled.filter { $0 == "began loadSettings" }.count == 1)
        #expect(!spelled.contains { $0.hasPrefix("failed") })
        #expect(try await #require(composition.stores).settings.load() == composition.settings)
    }

    @Test("Boots in the app, and under test only with -LEDGER_UITEST", arguments: [
        ([String](), false, true), (["-LEDGER_UITEST", "1"], false, true),
        ([String](), true, false), (["-LEDGER_UITEST", "1"], true, true), (["-LEDGER_UITEST"], true, true)
    ])
    func bootRule(arguments: [String], isTesting: Bool, boots: Bool) {
        #expect(AppComposition.boots(arguments: ["Ledger"] + arguments, isTesting: isTesting) == boots)
    }
}
