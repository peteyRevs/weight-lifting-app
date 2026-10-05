import Dependencies
import Foundation
import GRDB
@testable import LedgerAppKit
import LedgerDependencies
import LedgerDomain
import LedgerPersistence
import LedgerSync
import LedgerTestSupport
import SwiftUI
import Testing

/// F10 S2 criterion 9: the iPhone's composition builds the live workout's host when the database opens, binds
/// `workoutSession` to it, and runs its recovery as the launch step `resumeWorkout`: once, then again on a
/// return to the foreground while the host has work left. The launch owns the step's task.
@Suite("AppComposition · the live workout's host", .timeLimit(.minutes(1)))
struct WorkoutSessionWiringTests {
    typealias Hold = LaunchCloseoutAdversarialTests.WriterHold

    /// A workout that was finished and never saved, as the envelopes a killed app left in `workout_event`.
    nonisolated static let finished = EventBuilders.log(from: [
        .started(EventBuilders.seedSession()),
        .finished(endedAt: EventBuilders.start.addingTimeInterval(600))
    ])

    nonisolated static let refuseSave =
        "CREATE TRIGGER refuse BEFORE INSERT ON workout BEGIN SELECT RAISE(ABORT, 'full'); END"

    /// Stores the envelopes in the harness's file before any composition opens it.
    static func arrange(
        _ envelopes: [EventEnvelope],
        refusing trigger: String? = nil,
        in harness: Harness
    ) async throws {
        let queue = try LedgerDatabase.open(at: harness.databaseURL)
        _ = try await GRDBWorkoutEventStore(queue, now: { Harness.now }).append(envelopes)
        if let trigger {
            try await queue.write { try $0.execute(sql: trigger) }
        }
        try queue.close()
    }

    static func began(_ harness: Harness) -> Int {
        LaunchAdversarialTests.spelled(harness.log).filter { $0 == "began resumeWorkout" }.count
    }

    @Test("Opening the database builds the host over its stores, and workoutSession is bound to it")
    func boot_buildsTheHost_andBindsTheKey() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let idle = harness.composition()
        #expect(idle.session == nil)
        let composition = harness.booted()
        let host = try #require(composition.session)
        let bound = withDependencies { composition.bind(&$0) } operation: {
            @Dependency(\.workoutSession) var session
            return session
        }
        #expect(bound as? LocalWorkoutSessionActor === host)
        // It is the host of this database: a workout started through the key is in the composition's log.
        try await bound.start(EventBuilders.seedSession())
        #expect(try await #require(composition.stores).events.uncompactedWorkoutIDs() == [EventBuilders.workoutID])
        #expect(try await host.current()?.id == EventBuilders.workoutID)
    }

    @Test("A database that opens only on a later foreground gets its host then, and the step runs")
    func lateOpen_buildsTheHostThen() async throws {
        let harness = Harness()
        defer { harness.remove() }
        try FileManager.default.createDirectory(at: harness.databaseURL, withIntermediateDirectories: true)
        let composition = harness.booted()
        await composition.resume(in: .active)
        #expect(composition.state == .databaseUnavailable && composition.session == nil)
        #expect(Self.began(harness) == 0)
        try FileManager.default.removeItem(at: harness.databaseURL)
        await composition.resume(in: .active)
        #expect(composition.state == .ready && composition.session != nil)
        #expect(Self.began(harness) == 1)
    }

    @Test(
        "The step resumes a workout the app was killed in, in whatever phase the launch runs",
        arguments: [ScenePhase.active, .inactive, .background]
    )
    func launchStep_resumesALiveWorkout(phase: ScenePhase) async throws {
        let harness = Harness("launchStepResumes\(phase)") // a directory of its own for each case
        defer { harness.remove() }
        let live = EventBuilders.log(from: [.started(EventBuilders.seedSession()), .restSkipped])
        try await Self.arrange(live, in: harness)
        let composition = harness.booted()
        await composition.resume(in: phase)
        #expect(Self.began(harness) == 1)
        #expect(await composition.session?.needsRecovery == false)
        #expect(try await composition.session?.current() == EventBuilders.seedSession())
        // Nothing is left to do: no later call runs the step again.
        await composition.resume(in: .active)
        await composition.resume(in: .background)
        #expect(Self.began(harness) == 1)
    }

    @Test("A step that fails is recorded, and retried on the next foreground only")
    func stepFailure_isRecorded_andRetriedInTheForeground() async throws {
        let harness = Harness()
        defer { harness.remove() }
        try await Self.arrange(Self.finished, refusing: Self.refuseSave, in: harness)
        let composition = harness.booted()
        await composition.resume(in: .active)
        let stores = try #require(composition.stores)
        #expect(LaunchAdversarialTests.spelled(harness.log).suffix(4) == [
            "began resumeWorkout", "failed resumeWorkout", "began activateCompanionSession", "companion"
        ])
        #expect(try await stores.events.uncompactedWorkoutIDs() == [EventBuilders.workoutID])
        await composition.resume(in: .background)
        await composition.resume(in: .inactive)
        #expect(Self.began(harness) == 1)
        await composition.resume(in: .active)
        #expect(LaunchAdversarialTests.spelled(harness.log).filter { $0 == "failed resumeWorkout" }.count == 2)
        try await stores.queue.write { try $0.execute(sql: "DROP TRIGGER refuse") }
        await composition.resume(in: .active)
        #expect(Self.began(harness) == 3)
        #expect(try await stores.workouts.workout(id: EventBuilders.workoutID)?.phase == .finished)
        #expect(try await stores.events.uncompactedWorkoutIDs().isEmpty)
        await composition.resume(in: .active)
        #expect(Self.began(harness) == 3)
    }

    @Test("A finish whose save failed is retried by the step on the next foreground, and its streams are told")
    func failedFinish_isRetriedOnTheNextForeground() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.booted()
        await composition.resume(in: .active)
        let stores = try #require(composition.stores)
        let session = try #require(composition.session)
        try await session.start(EventBuilders.seedSession())
        try await stores.queue.write { try $0.execute(sql: Self.refuseSave) }
        await #expect(throws: DatabaseError.self) { _ = try await session.finish(endedAt: Harness.now) }
        var updates = await session.updates().makeAsyncIterator()
        #expect(await updates.next()?.live == EventBuilders.seedSession())
        await composition.resume(in: .background)
        #expect(Self.began(harness) == 1)
        try await stores.queue.write { try $0.execute(sql: "DROP TRIGGER refuse") }
        await composition.resume(in: .active)
        #expect(Self.began(harness) == 2)
        #expect(try await stores.workouts.workout(id: EventBuilders.workoutID)?.phase == .finished)
        #expect(await updates.next()?.state?.phase == .finished)
        #expect(try await session.current() == nil)
    }

    @Test("A scene-phase task that is cancelled never cancels the step: the workout is saved all the same")
    func cancelledCaller_neverCancelsTheStep() async throws {
        let harness = Harness()
        defer { harness.remove() }
        try await Self.arrange(Self.finished, refusing: Self.refuseSave, in: harness)
        let composition = harness.booted()
        await composition.resume(in: .active)
        let stores = try #require(composition.stores)
        try await stores.queue.write { try $0.execute(sql: "DROP TRIGGER refuse") }
        // The retry's first read waits for the database; its caller is cancelled while it waits there.
        let hold = Hold(stores.queue)
        let caller = Task { await composition.resume(in: .active) }
        for _ in 0 ..< 1000 where Self.began(harness) < 2 {
            await Task.yield()
        }
        #expect(Self.began(harness) == 2)
        caller.cancel()
        hold.free()
        await caller.value
        // A background call starts nothing; it waits for the step if it is still running.
        await composition.resume(in: .background)
        #expect(try await stores.workouts.workout(id: EventBuilders.workoutID)?.phase == .finished)
        #expect(LaunchAdversarialTests.spelled(harness.log).filter { $0 == "failed resumeWorkout" }.count == 1)
        #expect(Self.began(harness) == 2)
    }
}
