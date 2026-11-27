import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing
@testable import WatchFeatureWorkout

/// The watch's store (F18 S2a; criteria 2, 4, 9, 10, 11). Each test runs `run()` in a task, as the root's `.task` does,
/// and waits for what it expects by observing the store, never by time.
@MainActor
@Suite("WatchWorkoutStore", .tags(.watch), .timeLimit(.minutes(1)))
struct WatchWorkoutStoreTests {
    typealias Scene = WatchStoreScene

    static func plan(_ store: WatchWorkoutStore) -> WatchIdleModel.Plan? {
        if case let .plan(plan)? = store.idle {
            plan
        } else {
            nil
        }
    }

    static func shownSet(_ store: WatchWorkoutStore) -> LoggedSet? {
        guard let workout = store.workout, let row = WatchPresentation.activeRow(of: workout), let set = row.set else {
            return nil
        }
        return workout.exercises[row.exercise].sets[set]
    }

    @Test("Start reaches set-ready in one emission: today's session, its first set, the dots and Done set")
    func start_readyInOneEmission() async throws {
        let scene = try Scene()
        let (store, task) = await scene.running()
        #expect(Self.plan(store)?.start == "Start" && store.mode == .idle)
        let heard = store.updatesHeard
        store.send(.start)
        store.send(.start)
        await observed("set-ready") { store.mode == .ready }
        #expect(store.updatesHeard == heard + 1, "one emission from idle to set-ready")
        let ready = try #require(store.ready)
        let first = try #require(store.workout?.exercises.first)
        #expect(ready.setLabel == "SET 1 OF \(first.sets.count)" && ready.exerciseName == first.name)
        #expect(ready.dots == Array(repeating: false, count: first.sets.count))
        #expect(ready.reps == "× \(first.sets[0].reps.value)" && ready.heartRate.value == "—")
        #expect(store.crownWeight == first.sets[0].weight.formatted(in: .lb))
        #expect(store.crownDial?.weight == store.crownWeight && store.crownDial?.unit == "LB")
        await Scene.settled(store)
        #expect(await scene.fake?.applied.count == 1, "a double tap starts one workout")
        task.cancel()
    }

    @Test("Reps − stops at one, + adds one, each one change of the shown set")
    func test_reps_minimumOne() async throws {
        var live = try Scene.lowerA()
        live.exercises[0].sets[0].reps = Reps(clamping: 2)
        let scene = try Scene(live: live)
        let (store, task) = await scene.running()
        store.send(.stepReps(.downward))
        store.send(.stepReps(.downward))
        await observed("one rep") { Self.shownSet(store)?.reps == .one }
        store.send(.stepReps(.upward))
        await observed("two reps") { Self.shownSet(store)?.reps.value == 2 }
        #expect(await scene.fake?.applied.count == 2, "the second − at one rep sends nothing")
        task.cancel()
    }

    @Test("The crown shows its turn at once and commits it once, on idle: +5 lb, and +2.5 kg")
    func test_crown_commitsOnceOnIdle() async throws {
        for (settings, step, shown) in [(Fixtures.settingsLb, 5.0, "+5"), (Fixtures.settingsKg, 2.5, "+2.5")] {
            var live = try Scene.lowerA(settings: settings)
            let units = live.units
            live.exercises[0].sets[0].weight = units == .lb ? .pounds(185) : .kilograms(80)
            let scene = try Scene(live: live)
            let (store, task) = await scene.running()
            let start = try #require(store.crown.reading)
            #expect(start.step == (units == .lb ? .pounds(5) : .kilograms(Decimal(string: "2.5") ?? 0)))
            store.send(.crownRotated(store.crown.value + step))
            #expect(store.crownWeight == (units == .lb ? "190" : "82.5"), "\(shown) before anything is sent")
            #expect(store.queue.isEmpty, "nothing is sent while the crown turns")
            store.send(.crownRested)
            store.send(.crownRested)
            #expect(store.queue.count == 1, "one commit")
            let turned = units == .lb ? Weight.pounds(190) : .kilograms(Decimal(string: "82.5") ?? 0)
            await observed("the commit") { Self.shownSet(store)?.weight == turned }
            let sent = WorkoutEvent.setTargetChanged(
                exerciseIndex: 0,
                setID: start.target.setID,
                weight: turned,
                reps: nil
            )
            #expect(await scene.fake?.applied == [sent])
            task.cancel()
        }
    }

    @Test("At rest the crown follows a change from the phone; turning, it holds it, then its own turn wins")
    func test_crown_followsRemoteWhenIdle() async throws {
        var live = try Scene.lowerA()
        live.exercises[0].sets[0].weight = .pounds(185)
        let scene = try Scene(live: live)
        let (store, task) = await scene.running()
        let setID = live.exercises[0].sets[0].id
        let phone = { (weight: Weight) in
            try await scene.fake?.apply(.setTargetChanged(exerciseIndex: 0, setID: setID, weight: weight, reps: nil))
        }
        try await phone(.pounds(200))
        await observed("the phone's weight") { store.crownWeight == "200" }
        store.send(.crownRotated(205))
        try await phone(.pounds(225))
        await observed("the phone's change heard") { Self.shownSet(store)?.weight == .pounds(225) }
        #expect(store.crownWeight == "205", "the number does not jump under the finger")
        store.send(.crownRested)
        await observed("the turn wins") { Self.shownSet(store)?.weight == .pounds(205) }
        // A turn that comes back to where it began gives way to the phone's change.
        store.send(.crownRotated(210))
        try await phone(.pounds(135))
        await observed("heard") { Self.shownSet(store)?.weight == .pounds(135) }
        store.send(.crownRotated(205))
        store.send(.crownRested)
        #expect(store.queue.isEmpty && store.crownWeight == "135", "nothing sent, and the phone's weight shows")
        task.cancel()
    }

    @Test("A change of mode closes the list; the end overlay stays; neither shows once the workout is not live")
    func test_listClosesOnModeChange_endDoesNot() async throws {
        let scene = try Scene(live: Scene.lowerA())
        let (store, task) = await scene.running()
        store.send(.openList)
        #expect(store.shownOverlay == .list)
        try await scene.fake?.apply(.restStarted(endsAt: Fixtures.now.addingTimeInterval(90), total: .seconds(90)))
        await observed("rest") { store.rest != nil }
        #expect(store.shownOverlay == nil, "the rest closed the list")
        store.send(.openList)
        store.send(.openEnd)
        try await scene.fake?.apply(.restExtended(amount: .seconds(30), extendsShownRest: true, tappedAt: Fixtures.now))
        await observed("+30s heard") { store.rest?.clock == "2:00" }
        store.send(.keepLifting)
        #expect(store.shownOverlay == .list, "a rest moved by +30s is the same screen, and Keep lifting is the list")
        store.send(.openEnd)
        try await scene.fake?.apply(.restSkipped)
        await observed("ready") { store.mode == .ready }
        #expect(store.shownOverlay == .end, "a mode change leaves the end overlay up")
        store.send(.closeList)
        #expect(store.shownOverlay == .end)
        try await scene.fake?.discard(endedAt: Fixtures.now)
        await observed("idle") { store.mode == .idle }
        #expect(store.overlay == nil)
        store.send(.openList)
        #expect(store.shownOverlay == nil, "no overlay over idle")
        task.cancel()
    }

    @Test("A row of the list selects its exercise, at its first set to log, and closes the list")
    func select_closesTheList() async throws {
        let scene = try Scene(live: Scene.lowerA([(2, 0)]))
        let (store, task) = await scene.running()
        store.send(.openList)
        store.send(.selectExercise(2))
        #expect(store.shownOverlay == nil)
        await observed("the third exercise") { store.ready?.setLabel.hasSuffix("SET 2 OF 3") == true }
        #expect(store.list?.rows[2].isCurrent == true)
        store.send(.selectExercise(99))
        await Scene.settled(store)
        #expect(await scene.fake?.applied.count == 1, "a row that is not there selects nothing")
        task.cancel()
    }
}

extension WatchWorkoutStoreTests {
    @Test("Start lost to the phone's, then the phone's workout replaced the watch's: never through idle")
    func doubleStart_winnerSwap() async throws {
        let phones = try WatchSample.session(day: 1)
        let session = ScriptedSession(winner: phones)
        let scene = try Scene(session: session)
        let (store, task) = await scene.running()
        store.send(.start)
        await observed("the phone's workout") { store.workout?.id == phones.id }
        #expect(store.mode == .ready && store.ready?.exerciseName == phones.exercises[0].name)
        #expect(await session.starts == 1)
        await observed("the start answered") { store.queue.isEmpty }
        // The reconciliation hands the stream another workout in its place, with the list up.
        store.send(.openList)
        let other = try Scene.session(day: 0, id: WorkoutID(Fixtures.uuid(77)))
        let heard = store.updatesHeard
        await session.publish(other)
        await observed("the winner") { store.workout?.id == other.id }
        #expect(store.updatesHeard == heard + 1 && store.mode == .ready)
        #expect(store.shownOverlay == nil, "another workout starts afresh")
        #expect(store.crown.reading?.target.setID == other.exercises[0].sets[0].id, "the crown follows the winner")
        task.cancel()
    }

    @Test("Save workout → summary → Done → idle, which shows the day logged; Discard ends at idle")
    func finish_summary_done_idle() async throws {
        let scene = try Scene(live: Scene.lowerA([(0, 0)]))
        let (store, task) = await scene.running()
        store.send(.openList)
        store.send(.openEnd)
        #expect(store.end?.canSave == true)
        store.send(.save)
        await observed("summary") { store.mode == .summary }
        task.cancel()
        await task.value
        let again = Task { await store.run() }
        await observed("heard again") { store.hasHeardSession }
        #expect(store.mode == .summary, "a stream that starts again on no workout keeps the summary until Done")
        let total = store.workout?.totalSets ?? 0
        #expect(store.summary?.sets == "1/\(total)" && store.summary?.done == "Done" && store.shownOverlay == nil)
        store.send(.dismissSummary)
        #expect(store.mode == .idle && store.summary == nil)
        let plan = try #require(Self.plan(store))
        #expect(plan.planLine.hasPrefix("Logged · 1 set") && plan.start == nil)
        again.cancel()

        let discarding = try Scene(live: Scene.lowerA([(0, 0)]))
        let (other, otherTask) = await discarding.running()
        other.send(.openEnd)
        other.send(.discard)
        await observed("idle") { other.mode == .idle }
        #expect(other.workout?.phase == .discarded && other.summary == nil)
        otherTask.cancel()
    }

    @Test("Done set logs the shown set once, at the crown's weight; +30s and Skip answer the rest")
    func logSet_rest() async throws {
        var live = try Scene.lowerA()
        live.exercises[0].sets[0].weight = .pounds(185)
        let scene = try Scene(live: live)
        let (store, task) = await scene.running()
        store.send(.crownRotated(190))
        store.send(.logSet)
        store.send(.logSet)
        await observed("logged") { store.workout?.doneSets == 1 }
        #expect(store.workout?.exercises[0].sets[0].weight == .pounds(190))
        await Scene.settled(store)
        #expect(await scene.fake?.applied.count == 2, "the weight, then one log: the second Done set found it logged")
        try await scene.fake?.apply(.restStarted(endsAt: Fixtures.now.addingTimeInterval(60), total: .seconds(60)))
        await observed("rest") { store.rest?.clock == "1:00" }
        store.send(.extendRest)
        await observed("+30s") { store.rest?.clock == "1:30" }
        store.send(.skipRest)
        store.send(.skipRest)
        await observed("skipped") { store.mode == .ready }
        await Scene.settled(store)
        let skips = await scene.fake?.applied.count { $0 == .restSkipped }
        #expect(skips == 1, "a second Skip finds no rest")
        task.cancel()
    }

    @Test("A refused change drops the taps behind it; the connection line follows the phone's rule")
    func refusal_andConnection() async throws {
        let session = ScriptedSession()
        try await session.publish(Scene.lowerA())
        let scene = try Scene(session: session)
        let (store, task) = await scene.running()
        store.send(.stepReps(.upward))
        store.send(.stepReps(.upward))
        await Scene.settled(store)
        #expect(await session.applyCalls == 1, "the tap behind the refused one is dropped")
        #expect(store.ready?.connection == nil, "a solo watch that never heard the phone says nothing")
        await scene.connection.change(to: .connected(.mirroring))
        await observed("heard the phone") { store.hasHeardPhone }
        await scene.connection.change(to: .solo)
        await observed("the line") { store.ready?.connection != nil }
        task.cancel()
    }
}

extension WatchWorkoutStoreTests {
    @Test("Today's session logged before the store ran is \"Logged earlier today\" with no Start; a rest day never is")
    func todayLogged_noStart() async throws {
        let scene = try Scene()
        let (store, task) = await scene.running()
        #expect(Self.plan(store)?.start == "Start")
        var earlier = try Scene.lowerA([(0, 0)])
        earlier.startedAt = Fixtures.now.addingTimeInterval(-3600)
        earlier.endedAt = Fixtures.now.addingTimeInterval(-600)
        earlier.phase = .finished
        try await scene.stores.workouts.materialize(earlier, slotUpdates: [])
        await observed("logged earlier today") { Self.plan(store)?.planLine == "Logged earlier today" }
        #expect(Self.plan(store)?.start == nil)
        let program = try #require(store.program)
        let thursday = Fixtures.now.addingTimeInterval(86400)
        #expect(!WatchPresentation.isLogged(
            today: program, in: [earlier], settings: Fixtures.settingsLb, now: thursday, calendar: Fixtures.calendar
        ))
        task.cancel()
    }
}
