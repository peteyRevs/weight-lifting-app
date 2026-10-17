import Dependencies
@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S5, criteria 1 to 6: the store over in-memory stores and F10's fake session. Each test runs `run()` in
/// a task, as `TodayRoot` does, and waits for what it expects by observing the store, never by time.
@MainActor
@Suite("TodayStore", .tags(.feature), .timeLimit(.minutes(1)))
struct TodayStoreTests {
    typealias Scene = TodayScene

    /// A finished Lower A of week 1, started at `start`.
    static func finishedLowerA(_ number: Int = 60, startedAt start: Date) throws -> WorkoutState {
        let program = try TodayFixtures.program()
        return try TodayFixtures.finished(
            TodayFixtures.liveWorkout(
                number, of: program, weekIndex: 0, dayIndex: TodayFixtures.DayIndex.lowerA, startedAt: start
            ),
            after: 3480
        )
    }

    // MARK: Criterion 1

    @Test("1. Idle until it runs; then the day's card, from the stores, at the injected moment")
    func run_scheduledDay_showsUpNext() async throws {
        let scene = try Scene()
        #expect(scene.store.phase == "idle")
        let task = await scene.running()
        let model = try #require(scene.store.model)
        let program = try TodayFixtures.program()
        let route = TodayRoute.startWorkout(
            program: program.id, weekIndex: 0, day: program.days[TodayFixtures.DayIndex.lowerA].id
        )
        #expect(model.header.date == "Wednesday, September 16")
        #expect(model.header.title == "Lower A")
        #expect(model.card.upNext?.title == "Lower A — Squat focus")
        #expect(model.card.upNext?.action == .start(TodayModel.Action(title: "Start workout", route: route)))
        #expect(model.card.upNext?.rows.map(\.name).first == "Back Squat")
        #expect(scene.store.pendingRoute == nil)
        task.cancel()
        await task.value
        #expect(scene.store.phase == "loaded", "a root that went away has not failed")
    }

    @Test("1. With no program it says so; the calendar, the zone and the locale are the injected ones")
    func run_noProgram_inAnotherZoneAndLanguage() async throws {
        // 05:20 UTC on Wednesday is still Tuesday evening in Los Angeles.
        let scene = try Scene(hasProgram: false) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? Fixtures.utc
            $0.calendar = calendar
            $0.locale = Locale(identifier: "de_DE")
        }
        let task = await scene.running()
        #expect(scene.store.model?.card.kind == "noProgram")
        #expect(scene.store.model?.header.date == "Dienstag, 15. September")
        task.cancel()
    }

    @Test("1. A session whose updates end without one, as the key's stub's do, is no live workout")
    func run_sessionWithoutUpdates_stillShowsToday() async throws {
        let scene = try Scene { $0.workoutSession = EndedSession() }
        let task = await scene.running()
        #expect(scene.store.model?.card.upNext?.action.action.title == "Start workout")
        task.cancel()
    }

    // MARK: Criterion 2

    @Test("2. Where the stats week and the program week overlap, one read covers both and a workout counts once")
    func run_overlappingWeeks_readsEachWorkoutOnce() async throws {
        // The block began on Wednesday 2026-09-09: its second week is Wed 16 to Tue 22, the stats week Mon 14
        // to Sun 20. Wednesday's workout is in both; Monday's in the stats week alone.
        let program = try TodayFixtures.program(startingOn: TodayFixtures.civil(2026, 9, 9))
        let monday = try TodayFixtures.workout(61, pounds: 1000, startedAt: Fixtures.date(2026, 9, 14, hour: 7))
        let wednesday = try TodayFixtures.workout(62, pounds: 1000, startedAt: Fixtures.date(2026, 9, 16, hour: 4))
        let scene = try Scene(program: program, finished: [monday, wednesday])
        let task = await scene.running()
        let week = Fixtures.date(2026, 9, 14) ..< Fixtures.date(2026, 9, 23)
        #expect(scene.workouts.ranges == [week])
        #expect(scene.store.model?.stats.sessions.value == "2")
        #expect(scene.store.model?.stats.volume.accessibilitySummary.contains("2,000") == true)
        task.cancel()
    }

    // MARK: Criterion 3

    @Test("3. Once loaded it is never loading again: a change, a slow read and a new run keep the rest day's list")
    func loaded_neverReturnsToLoading() async throws {
        // Thursday of week 1 is a rest day: its card holds the off-schedule sheet's list.
        let scene = try Scene(now: Fixtures.date(2026, 9, 17, hour: 5, minute: 20))
        let first = await scene.running()
        let days = try #require(scene.store.model?.card.restDay?.offSchedule.days)
        #expect(days.count == 4)

        // A change whose read is still running: the model stays, with its list.
        var gate = scene.workouts.hold()
        var settings = Fixtures.settingsLb
        settings.weekStart = .sunday
        try await scene.stores.settings.save(settings)
        await gate.waitForArrival()
        #expect(scene.store.phase == "loaded")
        #expect(scene.store.model?.card.restDay?.offSchedule.days == days)
        gate.open()
        await eventually { scene.store.model?.weekStrip.first?.weekday == "S" }
        #expect(scene.store.model?.card.restDay?.offSchedule.days == days)

        // The root's task restarts (the tab came back): the same holds while the new run reads.
        first.cancel()
        await first.value
        gate = scene.workouts.hold()
        let second = Task { await scene.store.run() }
        await gate.waitForArrival()
        #expect(scene.store.phase == "loaded")
        #expect(scene.store.model?.card.restDay?.offSchedule.days == days)
        gate.open()
        second.cancel()
        await second.value
        #expect(scene.store.phase == "loaded")
    }

    @Test("3. A new run reads again at the moment it starts: the next day is shown without passing through loading")
    func newRun_onTheNextDay_showsThatDay() async throws {
        let scene = try Scene()
        let first = await scene.running()
        #expect(scene.store.model?.header.title == "Lower A")
        first.cancel()
        await first.value
        scene.clock.value = Fixtures.date(2026, 9, 17, hour: 5, minute: 20)
        let second = Task { await scene.store.run() }
        await eventually { scene.store.model?.header.title == "Rest day" }
        #expect(scene.store.model?.header.date == "Thursday, September 17")
        second.cancel()
    }

    // MARK: Criterion 4

    @Test("4. A workout finished and stored shows the day as logged, with no session to say so")
    func workoutMaterialised_showsLogged() async throws {
        let scene = try Scene()
        let task = await scene.running()
        #expect(scene.store.model?.stats.sessions.value == "0")
        let done = try Self.finishedLowerA(startedAt: Fixtures.date(2026, 9, 16, hour: 4))
        try await scene.stores.workouts.materialize(done, slotUpdates: [])
        await eventually { scene.store.model?.card.kind == "logged" }
        #expect(scene.store.model?.card.logged?.action.route == .openWorkout(done.id))
        #expect(scene.store.model?.stats.sessions.value == "1")
        #expect(scene.store.model?.recent.rows.map(\.route) == [.openWorkout(done.id)])
        task.cancel()
    }

    @Test("4. A saved program gives a new model")
    func programSaved_rebuildsTheModel() async throws {
        let scene = try Scene()
        let task = await scene.running()
        var program = try TodayFixtures.program()
        program.days[TodayFixtures.DayIndex.lowerA].name = "Legs"
        try await scene.stores.programs.save(program)
        await eventually { scene.store.model?.card.upNext?.title == "Legs" }
        task.cancel()
    }

    @Test("4. Changed settings give a new model: kilograms on the card, a Sunday start on the strip")
    func settingsChange_rebuildsTheModel() async throws {
        let scene = try Scene()
        let task = await scene.running()
        #expect(scene.store.model?.card.upNext?.rows.first?.scheme == "5 × 5 @ 250")
        #expect(scene.store.model?.weekStrip.first?.weekday == "M")
        var settings = Fixtures.settingsKg
        settings.weekStart = .sunday
        try await scene.stores.settings.save(settings)
        await eventually { scene.store.model?.weekStrip.first?.weekday == "S" }
        #expect(scene.store.model?.card.upNext?.rows.first?.scheme == "5 × 5 @ 113.4")
        #expect(scene.store.model?.stats.volume.caption == "kg moved")
        task.cancel()
    }
}
