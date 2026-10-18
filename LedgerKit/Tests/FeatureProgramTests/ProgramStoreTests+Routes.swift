@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S13, criteria 12 and 13: the notice's line and the routes.
extension ProgramStoreTests {
    // MARK: Criterion 12

    @Test("12. A notice is replaced by an action that carries one and dropped by any other edit and by a week")
    func notice_isReplacedAndDropped() async throws {
        var program = try Fixtures.seedProgram()
        program.weeks.removeLast(6)
        let scene = try ProgramStoreScene(program: program)
        let running = await scene.running()
        try scene.store.send(scene.model.block.removeWeek)
        #expect(scene.store.notice == .minimumTwoWeeks)
        scene.store.send(.selectWeek(1))
        #expect(scene.store.notice == nil)
        try scene.store.send(scene.model.block.removeWeek)
        scene.store.send(.edit(.setSchedule(week: 1, weekday: .tuesday, day: nil), notice: .dayHasNoExercises))
        #expect(scene.store.notice == .dayHasNoExercises, "replaced, although the edit changes nothing")
        scene.store.send(.edit(.setDeload(true, week: 0)))
        #expect(scene.store.notice == nil)
        await scene.idle()
        await running.cancel()
    }

    // MARK: Criterion 13

    @Test("13. The new day's route is emitted once its write has returned, and handed on once")
    func route_isEmittedOnce_afterTheSaveReturned() async throws {
        let scene = try ProgramStoreScene()
        let running = await scene.running()
        await scene.probe.hold(.updateProgram)
        try scene.store.send(#require(scene.model.days.addDay.action))
        try await scene.probe.waitUntilHeld()
        #expect(scene.store.pendingRoute == nil, "the day is not stored yet")
        await scene.probe.release()
        await eventually { scene.store.pendingRoute != nil }
        let day = try #require(await scene.stored().days.last)
        var handed: [ProgramRoute] = []
        scene.store.deliverRoute { handed.append($0) }
        scene.store.deliverRoute { handed.append($0) }
        #expect(handed == [.day(day.id, weekIndex: 4)])
        #expect(scene.store.pendingRoute == nil && scene.store.routeAfterSave == nil)
        await running.cancel()
    }

    @Test("13. A day added while a write runs opens once the write that holds it has returned")
    func addDay_duringAWrite_opensAfterItsOwnWrite() async throws {
        let scene = try ProgramStoreScene()
        let running = await scene.running()
        await scene.probe.hold(.updateProgram)
        scene.store.send(.rename("Block A"))
        try await scene.probe.waitUntilHeld()
        try scene.store.send(#require(scene.model.days.addDay.action))
        await scene.probe.hold(.updateProgram)
        await scene.probe.release()
        try await scene.probe.waitUntilHeld()
        #expect(scene.store.pendingRoute == nil, "the first write returned without the day")
        await scene.probe.release()
        await eventually { scene.store.pendingRoute != nil }
        #expect(try await scene.stored().days.count == 5)
        await running.cancel()
    }

    @Test("13. A double tap on \"+ Add training day\" adds one day and one route")
    func addDay_doubleTap_addsOneDay() async throws {
        let scene = try ProgramStoreScene()
        let running = await scene.running()
        let add = try #require(scene.model.days.addDay.action)
        scene.store.send(add)
        scene.store.send(add)
        #expect(try scene.model.days.cards.count == 5)
        await eventually { scene.store.pendingRoute != nil }
        var handed: [ProgramRoute] = []
        scene.store.deliverRoute { handed.append($0) }
        #expect(handed.count == 1)
        #expect(try await scene.stored().days.count == 5)
        await running.cancel()
    }

    @Test("13. A write that fails emits no route; a route asked for twice before it is handed on is one route")
    func failedWrite_emitsNoRoute_andARouteTwiceIsOne() async throws {
        let scene = try ProgramStoreScene()
        let running = await scene.running()
        await scene.probe.fail(.updateProgram)
        try scene.store.send(#require(scene.model.days.addDay.action))
        await scene.idle()
        #expect(scene.store.pendingRoute == nil && scene.store.routeAfterSave == nil)
        #expect(try scene.model.days.cards.count == 4 && scene.model.notice == "That change wasn't saved. Try again.")

        let card = try #require(scene.model.days.cards.first)
        scene.store.send(card.action)
        scene.store.send(card.action)
        var handed: [ProgramRoute] = []
        scene.store.deliverRoute { handed.append($0) }
        scene.store.deliverRoute { handed.append($0) }
        #expect(handed == [.day(card.id, weekIndex: 4)])
        await running.cancel()
    }
}
