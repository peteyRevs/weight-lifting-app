import Dispatch
import Foundation
import GRDB
import LedgerPersistence
@testable import LedgerWatchAppKit
import SwiftUI
import Testing

/// F07 S2 fix round 2 verification: `DatabaseLaunch` owns one task per step and callers only wait. A caller cancelled
/// while it waits for a step that then fails loses no failure, and the next foreground still retries it; a failed
/// step is not retried by a background call.
@Suite("Adversarial F07 S2 fix round 2 · watch launch step tasks", .timeLimit(.minutes(1)))
struct WatchLaunchStepTaskAdversarialTests {
    typealias Hold = WatchLaunchCloseoutAdversarialTests.WriterHold

    @Test("A caller cancelled while a failing seed waits: the failure is recorded once, the foreground retries it")
    func cancelledCaller_failingSeed_retriedOnForeground() async throws {
        let harness = Harness()
        defer { harness.remove() }
        try harness.arrange { database in
            try database
                .execute(sql: "CREATE TRIGGER refuse BEFORE INSERT ON exercise BEGIN SELECT RAISE(ABORT, 'no'); END")
        }
        let composition = harness.booted()
        let queue = try #require(composition.stores).queue
        let hold = Hold(queue)
        let first = Task { await composition.resume(in: .inactive) }
        await Task.yield()
        first.cancel()
        hold.free()
        await first.value
        // The step outlives its cancelled caller: wait for it through a background call, which starts nothing.
        await composition.resume(in: .background)
        var spelled = WatchLaunchAdversarialTests.spelled(harness.log)
        #expect(spelled.filter { $0 == "failed seedCatalog" }.count == 1, "\(spelled)")
        #expect(!composition.isCatalogSeeded)
        await composition.resume(in: .background) // a failed step is not retried in the background
        spelled = WatchLaunchAdversarialTests.spelled(harness.log)
        #expect(spelled.filter { $0 == "began seedCatalog" }.count == 1, "\(spelled)")
        try await queue.write { try $0.execute(sql: "DROP TRIGGER refuse") }
        await composition.resume(in: .active)
        #expect(composition.isCatalogSeeded)
        spelled = WatchLaunchAdversarialTests.spelled(harness.log)
        #expect(spelled.filter { $0 == "began seedCatalog" }.count == 2, "\(spelled)")
        #expect(spelled.filter { $0 == "began loadSettings" }.count == 1, "\(spelled)")
    }

    @Test("Three callers racing for the same steps start each step once and all return with it done")
    func racingCallers_shareOneTaskPerStep() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.booted()
        let hold = try Hold(#require(composition.stores).queue)
        let callers = [ScenePhase.inactive, .active, .background].map { phase in
            Task { await composition.resume(in: phase) }
        }
        await Task.yield()
        hold.free()
        for caller in callers {
            await caller.value
        }
        #expect(composition.isCatalogSeeded)
        let spelled = WatchLaunchAdversarialTests.spelled(harness.log)
        #expect(spelled.filter { $0 == "began seedCatalog" }.count == 1, "\(spelled)")
        #expect(spelled.filter { $0 == "began loadSettings" }.count == 1, "\(spelled)")
        #expect(spelled.filter { $0 == "companion" }.count == 1, "\(spelled)")
    }
}
