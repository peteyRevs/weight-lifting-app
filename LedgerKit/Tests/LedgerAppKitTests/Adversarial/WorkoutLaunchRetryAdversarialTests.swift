import Foundation
import GRDB
@testable import LedgerAppKit
import LedgerDomain
import LedgerPersistence
import LedgerSync
import LedgerTestSupport
import SwiftUI
import Testing

/// F10 S2 adversarial round 1, criteria 6 and 9: a launch step that fails "is recorded and retried on the next
/// foreground", and not otherwise; a finish whose save failed while the app ran is retried there too; and "a
/// scene-phase task that is cancelled never cancels the step".
@Suite("Adversarial F10 S2 · the launch step's failure and retry", .timeLimit(.minutes(1)))
struct WorkoutLaunchRetryAdversarialTests {
    typealias Launch = WorkoutLaunch
    typealias Hold = LaunchCloseoutAdversarialTests.WriterHold

    static let finished = Launch.log(Launch.middle + [.finished(endedAt: Launch.end)])

    @Test("A launch step that fails is recorded once, retried on the next foreground only, and then left alone")
    func launchStep_saveFails_isRetriedOnTheForegroundOnly() async throws {
        let harness = Harness()
        defer { harness.remove() }
        try await Launch.leave(Self.finished, at: harness.databaseURL)
        try harness.arrange { try $0.execute(sql: Launch.refuseSave) }
        let run = try await AppRun(harness)
        #expect(Launch.steps(harness, .resumeWorkout) == ["began resumeWorkout", "failed resumeWorkout"])
        #expect(try await run.logs() == [Launch.session.id], "the log is kept")
        for phase in [ScenePhase.background, .inactive, .background] {
            await run.composition.resume(in: phase)
        }
        #expect(Launch.steps(harness, .resumeWorkout).count == 2, "not retried away from the foreground")
        await run.composition.resume(in: .active)
        #expect(Launch.steps(harness, .resumeWorkout).count == 4, "retried, and failed again: the store still refuses")
        try await run.execute(Launch.allow)
        await run.composition.resume(in: .background)
        #expect(try await run.history().isEmpty)
        await run.composition.resume(in: .active)
        #expect(Launch.steps(harness, .resumeWorkout).suffix(1) == ["began resumeWorkout"])
        #expect(try await run.history().count == 1)
        #expect(try await run.logs().isEmpty)
        let steps = Launch.steps(harness, .resumeWorkout).count
        await run.composition.resume(in: .active)
        #expect(Launch.steps(harness, .resumeWorkout).count == steps, "nothing left: not run again")
    }

    @Test("A finish whose save failed while the app ran is completed on the next foreground, and only there")
    func finish_saveFailsWhileRunning_isCompletedOnTheNextForeground() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let run = try await WorkoutRelaunchAdversarialTests.running(harness, Launch.middle)
        let stream = await run.session.updates()
        try await run.execute(Launch.refuseSave)
        await #expect(throws: (any Error).self) { try await run.session.finish(endedAt: Launch.end) }
        try await run.execute(Launch.allow)
        await run.composition.resume(in: .background)
        #expect(try await run.history().isEmpty, "the background retries nothing")
        #expect(try await run.session.current() == Launch.folded(Launch.middle))
        await run.composition.resume(in: .active)
        let ended = try #require(Launch.folded(Launch.middle + [.finished(endedAt: Launch.end)]))
        #expect(try await run.history() == [Launch.asStored(ended)].compactMap(\.self))
        #expect(try await run.session.current() == nil)
        var ending: WorkoutSessionUpdate?
        for await update in stream where update.state?.phase == .finished {
            ending = update
            break
        }
        #expect(ending == WorkoutSessionUpdate(state: ended), "one ending update, without a haptic")
    }

    @Test("A scene-phase task cancelled while the step waits for the database does not cancel the step")
    func launchStep_callerCancelled_stillRecovers() async throws {
        let harness = Harness()
        defer { harness.remove() }
        try await Launch.leave(Self.finished, at: harness.databaseURL)
        let composition = harness.booted()
        await composition.resume(in: .background)
        #expect(Launch.steps(harness, .resumeWorkout) == ["began resumeWorkout"], "the first pass runs in any phase")
        let stores = try #require(composition.stores)
        #expect(try await stores.workouts.recent(limit: 9).count == 1)
        // A second finished log arrives (the lifter finishes another workout whose save fails), and the
        // foreground task that retries it is cancelled while the writer is held.
        let session = try #require(composition.session)
        try await session.start(Launch.session)
        try await stores.queue.write { try $0.execute(sql: Launch.refuseSave) }
        await #expect(throws: (any Error).self) { try await session.finish(endedAt: Launch.end) }
        try await stores.queue.write { try $0.execute(sql: Launch.allow) }
        let hold = Hold(stores.queue)
        let foreground = Task { await composition.resume(in: .active) }
        await Task.yield()
        foreground.cancel()
        hold.free()
        await foreground.value
        await composition.resume(in: .background)
        #expect(
            try await stores.events.uncompactedWorkoutIDs().isEmpty,
            "\(LaunchAdversarialTests.spelled(harness.log))"
        )
        #expect(try await session.current() == nil)
        #expect(!LaunchAdversarialTests.spelled(harness.log).contains("failed resumeWorkout"))
    }
}
