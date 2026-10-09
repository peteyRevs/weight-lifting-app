#if os(iOS) && DEBUG
    @testable import FeatureToday
    import Foundation
    import LedgerDomain
    import LedgerTestSupport
    import SwiftUI
    import Testing

    // F09 S5 adversarial round 2 (G2), criterion 14: the trips to the background. The suite and its stage are in
    // `TodayRootPhaseAdversarialTests.swift`.

    extension TodayRootPhaseAdversarialTests {
        @Test(
            "In the background nothing is followed; back, what changed there is shown; the rest day's list stays"
        )
        func background_changesMadeThere_areShownOnReturn_withTheListKept() async throws {
            let scene = try TodayScene(now: Fixtures.date(2026, 9, 17, hour: 5, minute: 20))
            let stage = Stage(.active)
            try await Self.hosting(scene, stage) {
                #expect(await settles { scene.store.model != nil })
                let days = try #require(scene.store.model?.card.restDay?.offSchedule.days)
                let publications = StatePublications(scene.store)

                await Self.move(stage, through: .inactive, .background)
                try await scene.stores.settings.save(Fixtures.settingsKg)
                let done = try TodayFixtures.workout(81, pounds: 1000, startedAt: Fixtures.date(2026, 9, 16, hour: 7))
                try await scene.stores.workouts.materialize(done, slotUpdates: [])
                await drain(turns: 60)
                #expect(scene.store.model?.stats.volume.caption == "lb moved", "the background follows nothing")
                #expect(publications.changes == 0)
                #expect(scene.workouts.observations == 1, "and starts nothing on the way there")

                await Self.move(stage, through: .inactive, .active)
                #expect(await settles { scene.store.model?.stats.sessions.value == "1" })
                #expect(scene.store.model?.stats.volume.caption == "kg moved")
                let isSameList = scene.store.model?.card.restDay?.offSchedule.days == days
                #expect(isSameList, "the sheet's list is the one that was on screen")
                #expect(publications.phases == ["loaded"], "the sheet's list never left: \(publications.phases)")
                #expect(scene.workouts.observations == 2)
            }
        }

        @Test("Back from the background in a new week, the new week is read and shown")
        func background_returnInANewWeek_readsTheNewWeek() async throws {
            // Sunday 2026-09-20 23:50, the last minutes of week 1; back on Monday at 00:10.
            let done = try TodayFixtures.workout(82, pounds: 1000, startedAt: Fixtures.date(2026, 9, 18, hour: 7))
            let scene = try TodayScene(finished: [done], now: Fixtures.date(2026, 9, 20, hour: 23, minute: 50))
            let stage = Stage(.active)
            await Self.hosting(scene, stage) {
                #expect(await settles { scene.store.model?.stats.sessions.value == "1" })
                await Self.move(stage, through: .inactive, .background)
                scene.clock.value = Fixtures.date(2026, 9, 21, hour: 0, minute: 10)
                await Self.move(stage, through: .inactive, .active)
                #expect(await settles { scene.store.model?.header.date == "Monday, September 21" })
                #expect(scene.store.model?.stats.sessions.value == "0")
                #expect(scene.store.model?.stats.volume.accessibilitySummary.contains("−100%") == true)
                let week = Fixtures.date(2026, 9, 21) ..< Fixtures.date(2026, 9, 28)
                #expect(scene.workouts.ranges.last == week)
            }
        }

        @Test("A route asked for just before the trip, in the background and just after it is handed on once each")
        func routes_aroundATripToTheBackground_areHandedOnOnce() async throws {
            let scene = try TodayScene()
            let stage = Stage(.active)
            await Self.hosting(scene, stage) {
                #expect(await settles { scene.store.model != nil })
                // Asked for in the same turn as the phase changes: the route's task must not be lost with it.
                scene.store.send(.settings)
                await Self.move(stage, through: .inactive, .background)
                #expect(await settles { scene.store.pendingRoute == nil })
                #expect(stage.handed == [.settings])

                scene.store.send(.openProgram)
                #expect(await settles { scene.store.pendingRoute == nil })
                scene.store.send(.resumeWorkout)
                await Self.move(stage, through: .inactive, .active)
                #expect(await settles { scene.store.pendingRoute == nil })
                #expect(stage.handed == [.settings, .openProgram, .resumeWorkout])
            }
        }
    }
#endif
