import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing
@testable import WatchFeatureWorkout

/// The end of the watch's rest and its haptics (F18 S2b; criteria 6, 7 and 15). Time moves only when a test moves the
/// scene's `RestCoverClock`, and the date with it; each test waits for a task's sleep to be registered before it moves
/// time, and for what it expects by observing the store, never by time.
@MainActor
@Suite("WatchWorkoutStore · rest zero and haptics", .tags(.watch), .timeLimit(.minutes(1)))
struct WatchRestOverTests {
    typealias Scene = WatchStoreScene

    static let rest60 = RestTimer(endsAt: Fixtures.now.addingTimeInterval(60), total: .seconds(60))

    /// A running store and its scene.
    struct Running {
        let scene: Scene
        let store: WatchWorkoutStore
        let task: Task<Void, Never>
    }

    /// A store on Lower A with its first set logged, in a 60 s rest whose task is asleep until the rest's end.
    static func resting(buzz: Bool = true) async throws -> Running {
        let scene = try Scene(live: Scene.lowerA([(0, 0)]))
        try await scene.buzz(buzz)
        let (store, task) = await scene.running(timed: true)
        try await scene.fake?.apply(.restStarted(endsAt: rest60.endsAt, total: rest60.total))
        await scene.clockWait("the rest's task asleep") { scene.clock.asleep == 1 }
        #expect(scene.clock.due == scene.clock.now.advanced(by: .seconds(60)), "it wakes at the rest's end")
        return Running(scene: scene, store: store, task: task)
    }

    @Test("At zero the rest reads GO for 1.2 s, then set-ready: buzzing once with watchBuzz on, not with it off")
    func test_buzz_gatedByWatchBuzz() async throws {
        for buzz in [true, false] {
            let running = try await Self.resting(buzz: buzz)
            let scene = running.scene, store = running.store, task = running.task
            scene.clock.advance(by: .milliseconds(59999))
            #expect(store.mode == .rest(Self.rest60) && store.rest?.title == "REST" && store.rest?.clock == "0:01")
            scene.clock.advance(by: .milliseconds(1))
            await observed("GO at the rest's end") { store.mode == .restOver(Self.rest60) }
            // The rest's task waits out GO; with the buzz, the haptics' turn waits its 100 ms after the buzz.
            await scene.clockWait("GO's wait, and the buzz's turn") { scene.clock.asleep == (buzz ? 2 : 1) }
            #expect(await scene.haptics.played == (buzz ? [.restOver] : []), "the buzz is gated, buzz \(buzz)")
            #expect(store.haptic.queue.isEmpty)
            // The same screen either way (D11): the title, the clock at zero and the ring empty.
            #expect(store.rest?.title == "GO" && store.rest?.clock == "0:00")
            #expect(store.rest?.ringOffset == WatchPresentation.ringLength)
            scene.clock.advance(by: .milliseconds(1199))
            #expect(store.mode == .restOver(Self.rest60), "GO lasts the whole 1.2 s")
            scene.clock.advance(by: .milliseconds(1))
            await observed("set-ready 1.2 s after zero") { store.mode == .ready }
            #expect(store.rest == nil && store.ready != nil)
            #expect(await scene.haptics.played.count == (buzz ? 1 : 0), "once for the rest")
            task.cancel()
        }
    }

    @Test("+30s at zero starts a new 30 s rest titled REST, whose task buzzes at its own end")
    func test_addRest_atZeroStartsThirtySeconds() async throws {
        let running = try await Self.resting(buzz: false)
        let scene = running.scene, store = running.store, task = running.task
        scene.clock.advance(by: .seconds(60))
        await observed("GO") { store.rest?.title == "GO" }
        await scene.clockWait("GO's wait") { scene.clock.asleep == 1 }
        let sleeps = scene.clock.sleeps
        store.send(.extendRest)
        await observed("a new rest") { store.rest?.title == "REST" }
        let fresh = RestTimer(endsAt: Self.rest60.endsAt.addingTimeInterval(30), total: .seconds(30))
        #expect(store.workout?.rest == fresh && store.rest?.clock == "0:30" && store.rest?.ringOffset == 0)
        let atZero = Self.rest60.endsAt
        let sent = WorkoutEvent.restExtended(amount: .seconds(30), extendsShownRest: false, tappedAt: atZero)
        #expect(await scene.fake?.applied.last == sent)
        await scene.clockWait("the new rest's task asleep, GO's cancelled") {
            scene.clock.isAsleep(after: sleeps) && scene.clock.asleep == 1
        }
        #expect(scene.clock.due == scene.clock.now.advanced(by: .seconds(30)))
        scene.clock.advance(by: .seconds(30))
        await observed("GO again") { store.mode == .restOver(fresh) }
        task.cancel()
    }

    @Test("Skip, +30s, Save and Discard each cancel the rest's wait: the rest they leave behind never buzzes")
    func test_buzzTaskCancelledOnSkipExtendFinish() async throws {
        for action in [WatchAction.skipRest, .extendRest, .save, .discard] {
            let running = try await Self.resting()
            let scene = running.scene, store = running.store, task = running.task
            let sleeps = scene.clock.sleeps
            switch action {
            case .skipRest:
                store.send(.skipRest)
                await observed("skipped") { store.mode == .ready }
            case .save:
                store.send(.openEnd)
                store.send(.save)
                await observed("the summary") { store.mode == .summary }
            case .discard:
                store.send(.discard)
                await observed("idle") { store.mode == .idle }
            default:
                store.send(.extendRest)
                await observed("+30s") { store.rest?.clock == "1:30" }
                await scene.clockWait("the longer rest's task asleep") { scene.clock.isAsleep(after: sleeps) }
            }
            let extended = action == .extendRest
            #expect(scene.clock.asleep == (extended ? 1 : 0), "the old wait is cancelled at once, \(action)")
            scene.clock.advance(by: .milliseconds(61200))
            #expect(await scene.haptics.played == [], "nothing at the old rest's end, \(action)")
            if extended {
                let longer = RestTimer(endsAt: Self.rest60.endsAt.addingTimeInterval(30), total: .seconds(90))
                #expect(store.mode == .rest(longer))
                scene.clock.advance(by: .milliseconds(28800))
                await scene.clockWait("the new end's buzz") { scene.clock.asleep == 2 }
                #expect(await scene.haptics.played == [.restOver])
            }
            task.cancel()
        }
    }

    @Test("A rest already over when it is shown reads GO for what is left of 1.2 s, and is not felt late")
    func restOverWhenShown_noBuzz() async throws {
        let scene = try Scene(live: Scene.lowerA())
        let (store, task) = await scene.running(timed: true)
        let ended = RestTimer(endsAt: Fixtures.now.addingTimeInterval(-0.5), total: .seconds(60))
        try await scene.fake?.apply(.restStarted(endsAt: ended.endsAt, total: ended.total))
        await observed("GO") { store.mode == .restOver(ended) }
        await scene.clockWait("GO's wait") { scene.clock.asleep == 1 }
        #expect(scene.clock.due == scene.clock.now.advanced(by: .milliseconds(700)))
        scene.clock.advance(by: .milliseconds(700))
        await observed("set-ready") { store.mode == .ready }
        #expect(await scene.haptics.played == [] && store.haptic.queue.isEmpty)
        task.cancel()
    }

    @Test("An update's haptics play in order, each at least 100 ms after the one before; none is dropped")
    func test_haptics_minimumSpacing100ms() async throws {
        let session = ScriptedSession()
        try await session.publish(Scene.lowerA())
        let scene = try Scene(session: session)
        let (store, task) = await scene.running(timed: true)
        let haptics: [Haptic] = [.setLogged, .workoutFinished, .personalRecord, .setLogged]
        try await session.publish(Scene.lowerA([(0, 0)]), haptics: haptics)
        await scene.clockWait("the first played") { scene.clock.asleep == 1 }
        #expect(await scene.haptics.played == [.setLogged])
        #expect(store.haptic.queue == [.personalRecord, .setLogged], "queued, and the finish takes no turn")
        scene.clock.advance(by: .milliseconds(99))
        #expect(scene.clock.asleep == 1, "not yet")
        for step in [Duration.milliseconds(1), .milliseconds(100)] {
            let sleeps = scene.clock.sleeps
            scene.clock.advance(by: step)
            await scene.clockWait("the next played") { scene.clock.isAsleep(after: sleeps) }
        }
        #expect(await scene.haptics.played == [.setLogged, .personalRecord, .setLogged])
        #expect(await scene.haptics.times == [.zero, .milliseconds(100), .milliseconds(200)])
        task.cancel()
    }

    @Test("The watch plays three haptics: a logged set clicks, rest zero notifies, a record succeeds; a finish, none")
    func hapticPatterns() {
        #expect(Haptic.allCases.map(WatchHapticPattern.init) == [.click, .notification, .success, nil])
    }
}
