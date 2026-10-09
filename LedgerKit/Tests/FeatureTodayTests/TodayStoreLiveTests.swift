@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S5, criteria 5 and 7: the live workout on the card, through F10's fake session, and the routes a tap
/// asks for.
@MainActor
@Suite("TodayStore: the live workout and the routes", .tags(.feature), .timeLimit(.minutes(1)))
struct TodayStoreLiveTests {
    typealias Scene = TodayScene

    private nonisolated static let resume = TodayModel.Action(title: "Resume · 3:00", route: .resumeWorkout)

    // MARK: Criterion 5

    @Test("5. A live workout offers Resume from its start; logging under the cover reads nothing and changes nothing")
    func liveWorkout_showsResume_withoutReadingPerSet() async throws {
        let live = try Scene.liveLowerA()
        let scene = try Scene(live: live)
        let task = await scene.running()
        #expect(scene.store.model?.card.upNext?.action == .resume(Self.resume, startedAt: live.startedAt))
        let reads = scene.workouts.ranges.count
        #expect(reads == 1)

        // Two sets logged, and the clock a minute on: the model is the one that was made, and nothing was read.
        scene.clock.value = Fixtures.now.addingTimeInterval(60)
        for set in live.exercises[0].sets.prefix(2) {
            try await scene.fake.apply(.setLogged(
                exerciseIndex: 0, setID: set.id, weight: set.weight, reps: set.reps, doneAt: Fixtures.now
            ))
        }
        // The discard is the next thing the store shows, so the two updates before it were taken in.
        try await scene.fake.discard(endedAt: Fixtures.now)
        await eventually { scene.store.model?.card.upNext?.action.action.title == "Start workout" }
        #expect(scene.workouts.ranges.count == reads + 1, "only the update that ended the workout read again")
        task.cancel()
    }

    @Test("5. A workout finished elsewhere shows the day as logged in the update that ends it, before it is stored")
    func liveWorkout_showsResume_thenLoggedOnFinish() async throws {
        let live = try Scene.liveLowerA()
        let scene = try Scene(live: live)
        let task = await scene.running()
        #expect(scene.store.model?.card.upNext?.action.action.route == .resumeWorkout)
        _ = try await scene.fake.finish(endedAt: Fixtures.now)
        await eventually { scene.store.model?.card.kind == "logged" }
        #expect(scene.store.model?.card.logged?.action.route == .openWorkout(live.id))
        #expect(try await scene.stores.workouts.workout(id: live.id) == nil, "the fake session stores nothing")
        task.cancel()
    }

    @Test("5. A workout started elsewhere turns the card to Resume, and its discard turns it back")
    func startedElsewhere_showsResume_discardedShowsStart() async throws {
        let scene = try Scene()
        let task = await scene.running()
        #expect(scene.store.model?.card.upNext?.action.action.route != .resumeWorkout)
        let live = try Scene.liveLowerA(startedBefore: 0)
        try await scene.fake.start(live)
        await eventually { scene.store.model?.card.upNext?.action.action.route == .resumeWorkout }
        #expect(scene.store.model?.card.upNext?.action.action.title == "Resume · 0:00")
        try await scene.fake.discard(endedAt: Fixtures.now)
        await eventually { scene.store.model?.card.upNext?.action.action.title == "Start workout" }
        #expect(scene.store.model?.stats.sessions.value == "0")
        task.cancel()
    }

    // MARK: Criterion 15

    /// Logs the first set of `live` in the scene's session: a change that makes no read stale by itself.
    private static func logASet(of live: WorkoutState, in scene: Scene) async throws {
        let set = live.exercises[0].sets[0]
        try await scene.fake.apply(.setLogged(
            exerciseIndex: 0, setID: set.id, weight: set.weight, reps: set.reps, doneAt: scene.clock.value
        ))
    }

    @Test("15. A rebuild past midnight inside the week shows the new day over the same reads, which are still right")
    func rebuild_acrossMidnight_showsTheNewDay() async throws {
        let live = try Scene.liveLowerA()
        let scene = try Scene(live: live)
        let task = await scene.running()
        #expect(scene.store.model?.header.date == "Wednesday, September 16")
        scene.clock.value = Fixtures.date(2026, 9, 17, hour: 0, minute: 10)
        try await Self.logASet(of: live, in: scene)
        await eventually { scene.store.model?.header.date == "Thursday, September 17" }
        #expect(scene.store.model?.header.title == "Rest day")
        #expect(scene.workouts.ranges.count == 1, "Thursday asks for the same two weeks: nothing to read again")
        task.cancel()
    }

    @Test("15. A rebuild past the week's end reads the new weeks, though no source made the reads stale")
    func rebuild_acrossTheWeeksEnd_readsTheNewWeeks() async throws {
        // Sunday night of week 1, with Wednesday's 1,000 lb stored and a workout begun at 23:40 still running.
        let program = try TodayFixtures.program()
        let wednesday = try TodayFixtures.workout(63, pounds: 1000, startedAt: Fixtures.date(2026, 9, 16, hour: 7))
        let live = try TodayFixtures.liveWorkout(
            50, of: program, weekIndex: 0, dayIndex: TodayFixtures.DayIndex.lowerA,
            startedAt: Fixtures.date(2026, 9, 20, hour: 23, minute: 40)
        )
        let scene = try Scene(finished: [wednesday], live: live, now: Fixtures.date(2026, 9, 20, hour: 23, minute: 50))
        let task = await scene.running()
        #expect(scene.workouts.ranges == [Fixtures.date(2026, 9, 14) ..< Fixtures.date(2026, 9, 21)])
        #expect(scene.store.model?.stats.sessions.value == "1")
        #expect(scene.store.model?.stats.volume.accessibilitySummary == "1,000 lb moved this week")

        // Ten past midnight a set is logged under the cover: the update of a live workout forgets no read.
        scene.clock.value = Fixtures.date(2026, 9, 21, hour: 0, minute: 10)
        try await Self.logASet(of: live, in: scene)
        await eventually { scene.store.model?.header.date == "Monday, September 21" }
        #expect(scene.workouts.ranges.last == Fixtures.date(2026, 9, 21) ..< Fixtures.date(2026, 9, 28))
        #expect(scene.workouts.ranges.count == 2)
        #expect(scene.store.model?.stats.sessions.value == "0", "Wednesday's workout is last week's now")
        let summary = scene.store.model?.stats.volume.accessibilitySummary
        #expect(summary == "0 lb moved this week, \u{2212}100% from last week", "against the week that just ended")

        // The new reads are kept for the new weeks: the next set reads nothing.
        let next = live.exercises[0].sets[1]
        try await scene.fake.apply(.setLogged(
            exerciseIndex: 0, setID: next.id, weight: next.weight, reps: next.reps, doneAt: scene.clock.value
        ))
        try await scene.fake.discard(endedAt: scene.clock.value)
        await eventually { scene.store.model?.card.upNext?.action.action.title == "Start workout" }
        #expect(scene.workouts.ranges.count == 3, "the two sets read nothing; the update that ended the workout did")
        task.cancel()
    }

    // MARK: Criterion 7

    private nonisolated static let routes: [TodayRoute] = [
        .startWorkout(program: Fixtures.programID, weekIndex: 2, day: DayTemplateID(Fixtures.uuid(7))),
        .resumeWorkout,
        .openWorkout(Fixtures.sessionID),
        .editWeek(program: Fixtures.programID, weekIndex: 1),
        .openProgram,
        .settings,
        .setUpProgram
    ]

    @Test("7. Every route is handed to the app once per tap", arguments: routes)
    func route_isHandedOnOnce(_ route: TodayRoute) throws {
        let store = try Scene().store
        var handed: [TodayRoute] = []
        store.deliverRoute { handed.append($0) }
        #expect(handed.isEmpty, "nothing was asked for")

        store.send(route)
        #expect(store.pendingRoute?.route == route)
        store.deliverRoute { handed.append($0) }
        store.deliverRoute { handed.append($0) }
        #expect(handed == [route])
        #expect(store.pendingRoute == nil)

        // The next tap is a new route, told from the first by its number.
        store.send(route)
        #expect(store.pendingRoute == TodayPendingRoute(number: 2, route: route))
        store.deliverRoute { handed.append($0) }
        #expect(handed == [route, route])
    }

    @Test("7. A second tap before the first route was handed on is dropped: a double tap is one route")
    func secondTapWhileRouting_isDropped() throws {
        let store = try Scene().store
        var handed: [TodayRoute] = []
        store.send(Self.routes[0])
        store.send(Self.routes[0])
        store.send(.settings)
        #expect(store.pendingRoute == TodayPendingRoute(number: 1, route: Self.routes[0]))
        store.deliverRoute { handed.append($0) }
        #expect(handed == [Self.routes[0]])
        #expect(store.pendingRoute == nil)
    }

    @Test("7. The route a card's button carries is the one handed on: the off-schedule list's day starts that day")
    func offSchedule_pick_handsOnTheStartOfThatDay() async throws {
        let scene = try Scene(now: Fixtures.date(2026, 9, 17, hour: 5, minute: 20))
        let task = await scene.running()
        let program = try TodayFixtures.program()
        let days = try #require(scene.store.model?.card.restDay?.offSchedule.days)
        var handed: [TodayRoute] = []
        scene.store.send(days[TodayFixtures.DayIndex.upperB].route)
        scene.store.deliverRoute { handed.append($0) }
        #expect(handed == [
            .startWorkout(program: program.id, weekIndex: 0, day: program.days[TodayFixtures.DayIndex.upperB].id)
        ])
        task.cancel()
    }
}
