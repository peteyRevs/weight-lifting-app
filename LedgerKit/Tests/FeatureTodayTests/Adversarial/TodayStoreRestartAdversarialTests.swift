@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S5 adversarial round 1 (G2): the store over sources driven by hand (`ScriptedScene`), while the root's
/// task is cancelled and started again (deviation 6), while a read is running, and the routes a tap asks for
/// whatever the run is doing (criterion 7). Nothing here waits for time.
@MainActor
@Suite("Adversarial: TodayStore restarted and tapped", .tags(.feature), .timeLimit(.minutes(2)))
struct TodayStoreRestartAdversarialTests {
    // MARK: Deviation 6: the task restarts

    @Test("Restarted ten times without waiting for the old run, each source is listened to once, and reads once")
    func restarts_leaveOneObservationPerSource() async throws {
        let scene = ScriptedScene()
        try scene.speakAll()
        var task = await scene.running()
        #expect(await settles { scene.store.model != nil })
        let publications = StatePublications(scene.store)
        for _ in 0 ..< 10 {
            // As SwiftUI restarts a task: the old one is cancelled and not waited for.
            task.cancel()
            task = Task { await scene.store.run() }
        }
        let isAlone = await comes { scene.listening == [1, 1, 1, 1, 1] && scene.opened.allSatisfy { $0 == 11 } }
        #expect(isAlone, "listening \(scene.listening), opened \(scene.opened)")
        await drain(turns: 60)
        #expect(publications.phases == ["loaded"], "a restart shows nothing but the model")

        // One change now costs one read and gives one model: no second run is still listening.
        let reads = scene.workouts.reads
        var program = try TodayFixtures.program()
        program.days[TodayFixtures.DayIndex.lowerA].name = "Legs"
        scene.programs.yield(program)
        #expect(await settles { scene.store.model?.card.upNext?.title == "Legs" })
        await drain(turns: 60)
        #expect(scene.workouts.reads == reads + 1)
        #expect(publications.changes == 1)
        task.cancel()
        await task.value
        #expect(scene.listening == [0, 0, 0, 0, 0], "a root that went away listens to nothing")
    }

    @Test("A read the old run began ends after the new run's model: it changes nothing, failed or not", arguments: [
        true, false
    ])
    func oldRunsRead_endingLate_changesNothing(fails: Bool) async throws {
        let scene = ScriptedScene()
        try scene.speakAll()
        scene.workouts.isHolding = true
        let first = Task { await scene.store.run() }
        #expect(await comes { scene.workouts.waiting == [1] })

        // The root's task restarts while read 1 waits. The new run reads too (read 2), and is let go first.
        first.cancel()
        let second = Task { await scene.store.run() }
        #expect(await comes { scene.workouts.waiting == [1, 2] }, "\(scene.workouts.waiting)")
        scene.workouts.release(2)
        #expect(await settles { scene.store.model != nil })
        let publications = StatePublications(scene.store)

        scene.workouts.isFailing = fails
        scene.workouts.release(1)
        await first.value
        await drain(turns: 60)
        #expect(scene.store.phase == "loaded")
        #expect(publications.changes == 0)
        scene.workouts.isFailing = false
        scene.workouts.isHolding = false

        // The new run still follows: the old run took nothing with it.
        scene.settings.yield(Fixtures.settingsKg)
        #expect(await settles { scene.store.model?.stats.volume.caption == "kg moved" })
        second.cancel()
    }

    @Test("A change that arrives while a read is running is not lost: the model is the newest value's")
    func changeDuringARead_isNotLost() async throws {
        let scene = ScriptedScene()
        try scene.speakAll()
        scene.workouts.isHolding = true
        let task = Task { await scene.store.run() }
        #expect(await comes { scene.workouts.waiting == [1] })

        // Three programs while read 1 waits; the last is the one that must be shown.
        var program = try TodayFixtures.program()
        for name in ["One", "Two", "Legs"] {
            program.days[TodayFixtures.DayIndex.lowerA].name = name
            scene.programs.yield(program)
        }
        await drain(turns: 30)
        scene.workouts.isHolding = false
        scene.workouts.release(1)
        #expect(await settles { scene.store.model?.card.upNext?.title == "Legs" }, "\(scene.store.phase)")
        await drain(turns: 60)
        #expect(scene.workouts.reads <= 3, "one read was overtaken, one more is enough: \(scene.workouts.reads)")
        task.cancel()
    }

    @Test("A read that a finished workout overtook is not kept: the week is read again and the workout counted")
    func readOvertakenByAFinish_isMadeAgain() async throws {
        let scene = ScriptedScene()
        try scene.speakAll()
        scene.workouts.isHolding = true
        let task = Task { await scene.store.run() }
        #expect(await comes { scene.workouts.waiting == [1] })

        // Read 1 began on an empty week. A workout is stored and reported while it waits.
        let done = try TodayFixtures.workout(71, pounds: 1000, startedAt: Fixtures.now.addingTimeInterval(-3600))
        scene.workouts.week = [done]
        scene.recent.yield([done])
        await drain(turns: 30)
        scene.workouts.isHolding = false
        scene.workouts.release(1)
        #expect(await settles { scene.store.model?.stats.sessions.value == "1" }, "the old read was kept")
        task.cancel()
    }

    // MARK: Criterion 7: intents with no task, and after it was cancelled

    @Test("A route asked for with no run, during a read and after the task was cancelled is handed on once each")
    func routes_whateverTheRunDoes_areHandedOnOnce() async throws {
        let scene = ScriptedScene()
        var handed: [TodayRoute] = []
        // Before any run.
        scene.store.send(.settings)
        scene.store.send(.settings)
        scene.store.deliverRoute { handed.append($0) }

        // While the first read is running: a double tap.
        try scene.speakAll()
        scene.workouts.isHolding = true
        let task = Task { await scene.store.run() }
        #expect(await comes { scene.workouts.waiting == [1] })
        scene.store.send(.openProgram)
        scene.store.send(.openProgram)
        scene.store.deliverRoute { handed.append($0) }
        scene.store.deliverRoute { handed.append($0) }

        // After the root's task was cancelled, and after the run has ended.
        task.cancel()
        scene.store.send(.resumeWorkout)
        scene.store.deliverRoute { handed.append($0) }
        scene.workouts.release(1)
        await task.value
        scene.store.send(.setUpProgram)
        scene.store.send(.setUpProgram)
        scene.store.deliverRoute { handed.append($0) }

        #expect(handed == [.settings, .openProgram, .resumeWorkout, .setUpProgram])
        #expect(scene.store.pendingRoute == nil)
        #expect(scene.store.phase == "loading", "a cancelled run that never loaded shows nothing")
    }

    @Test("A handler that asks for another route while it is handed one does not lose it and is not called twice")
    func route_sentFromInsideTheHandler_isKeptForTheNextDelivery() {
        let store = ScriptedScene().store
        var handed: [TodayRoute] = []
        store.send(.settings)
        store.deliverRoute { route in
            handed.append(route)
            // The app's handler runs while the first route still waits: this one is dropped, by the rule
            // "one route waits at a time", and must not be delivered inside the same call.
            store.send(.openProgram)
        }
        #expect(handed == [.settings])
        #expect(store.pendingRoute == nil)
        store.send(.openProgram)
        store.deliverRoute { handed.append($0) }
        #expect(handed == [.settings, .openProgram])
    }
}
