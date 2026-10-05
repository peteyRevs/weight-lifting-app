import Foundation
import GRDB
@testable import LedgerAppKit
import LedgerDomain
import LedgerPersistence
import LedgerSync
import LedgerTestSupport
import SwiftUI
import Testing

/// F10 S2 adversarial round 1, criterion 7: kill and relaunch on a real database file, at the five points,
/// through the composition as the app boots it. The app is killed by being abandoned: a new composition opens
/// the same file, and the launch runs `LaunchStep.resumeWorkout`. Expected states are `WorkoutEngine.reduce`
/// folded here.
@Suite("Adversarial F10 S2 · kill and relaunch on a database file", .timeLimit(.minutes(1)))
struct WorkoutRelaunchAdversarialTests {
    typealias Launch = WorkoutLaunch

    /// Launches, starts the seed session and applies `events`.
    static func running(_ harness: Harness, _ events: [WorkoutEvent]) async throws -> AppRun {
        let run = try await AppRun(harness)
        try await run.session.start(Launch.session)
        for event in events {
            try await run.session.apply(event)
        }
        return run
    }

    @Test("Killed after started is stored: the relaunch resumes the workout")
    func kill_afterStarted_resumes() async throws {
        let harness = Harness()
        defer { harness.remove() }
        _ = try await Self.running(harness, [])
        harness.clearLog()
        let relaunched = try await AppRun(harness)
        #expect(try await relaunched.session.current() == Launch.session)
        #expect(Launch.steps(harness, .resumeWorkout) == ["began resumeWorkout"])
        #expect(try await relaunched.history().isEmpty)
    }

    @Test("Killed mid-workout with a rest running: the same sets, cursor and rest come back")
    func kill_midWorkout_resumesTheSameState() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let run = try await Self.running(harness, Launch.middle)
        let expected = try #require(Launch.folded(Launch.middle))
        #expect(try await run.session.current() == expected)
        #expect(expected.rest != nil && expected.cursor == Cursor(exerciseIndex: 3, setIndex: 1) && expected
            .doneSets == 2)
        let relaunched = try await AppRun(harness)
        #expect(try await relaunched.session.current() == expected)
        let next = try await relaunched.session.apply(Launch.logged(3, 1, at: 900))
        #expect(next == Launch.folded(Launch.middle + [Launch.logged(3, 1, at: 900)]))
        let log = try await relaunched.stores.events.envelopes(for: expected.id).sorted()
        #expect(log.map(\.seq) == Array(1 ... 7), "seq goes on where the killed app stopped")
        #expect(zip(log, log.dropFirst()).allSatisfy { $0.wallClock < $1.wallClock }, "on a clock that never moves")
    }

    @Test("Killed after finished is stored and before the save: the relaunch saves and compacts")
    func kill_afterFinishedBeforeTheSave_savesOnRelaunch() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let run = try await Self.running(harness, Launch.middle)
        try await run.execute(Launch.refuseSave)
        await #expect(throws: (any Error).self) { try await run.session.finish(endedAt: Launch.end) }
        #expect(try await run.history().isEmpty)
        try await run.execute(Launch.allow)
        harness.clearLog()
        let relaunched = try await AppRun(harness)
        let finished = try #require(Launch.folded(Launch.middle + [.finished(endedAt: Launch.end)]))
        #expect(try await relaunched.history() == [Launch.asStored(finished)].compactMap(\.self))
        #expect(try await relaunched.logs().isEmpty)
        #expect(try await relaunched.session.current() == nil)
        #expect(Launch.steps(harness, .resumeWorkout) == ["began resumeWorkout"])
    }

    @Test("Killed after the save and before the compaction: the relaunch changes nothing and compacts")
    func kill_afterTheSaveBeforeTheCompaction_compactsOnRelaunch() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let run = try await Self.running(harness, Launch.middle)
        try await run.execute(Launch.refuseDrop)
        await #expect(throws: (any Error).self) { try await run.session.finish(endedAt: Launch.end) }
        let saved = try await run.history()
        #expect(saved.count == 1, "the save went through before the app died")
        #expect(try await run.logs() == [Launch.session.id])
        try await run.execute(Launch.allow)
        let relaunched = try await AppRun(harness)
        #expect(try await relaunched.history() == saved)
        #expect(try await relaunched.logs().isEmpty)
        #expect(try await relaunched.session.current() == nil)
    }

    @Test("Killed after discarded is stored and before the compaction: nothing reaches history")
    func kill_afterDiscardedBeforeTheCompaction_dropsOnRelaunch() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let run = try await Self.running(harness, Launch.middle)
        try await run.execute(Launch.refuseDrop)
        await #expect(throws: (any Error).self) { try await run.session.discard(endedAt: Launch.end) }
        try await run.execute(Launch.allow)
        let relaunched = try await AppRun(harness)
        #expect(try await relaunched.history().isEmpty)
        #expect(try await relaunched.logs().isEmpty)
        #expect(try await relaunched.session.current() == nil)
        try await relaunched.session.start(Launch.session)
        #expect(try await relaunched.session.current() == Launch.session, "the same day can be started again")
    }

    @Test("A workout carried across six relaunches, the clock stepping back at each, finishes as the engine folds it")
    func kill_sixTimesWithTheClockSteppingBack_losesNothing() async throws {
        let harness = Harness()
        defer { harness.remove() }
        _ = try await Self.running(harness, [])
        for (index, event) in Launch.middle.enumerated() {
            let earlier = Harness.now.addingTimeInterval(-3600 * Double(index + 1))
            let relaunched = try await AppRun(harness, now: earlier, in: index.isMultiple(of: 2) ? .active : nil)
            try await relaunched.session.apply(event)
        }
        let last = try await AppRun(harness, now: Harness.now.addingTimeInterval(-86400))
        let log = try await last.stores.events.envelopes(for: Launch.session.id).sorted()
        #expect(log.map(\.event) == [.started(Launch.session)] + Launch.middle, "stamp order is the order of the calls")
        #expect(log.map(\.seq) == Array(1 ... 6))
        let finished = try await last.session.finish(endedAt: Launch.end)
        #expect(finished == Launch.folded(Launch.middle + [.finished(endedAt: Launch.end)]))
        #expect(try await last.history() == [Launch.asStored(finished)].compactMap(\.self))
    }
}
