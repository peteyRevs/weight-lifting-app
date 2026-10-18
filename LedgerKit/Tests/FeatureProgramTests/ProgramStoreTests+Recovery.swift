@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S13 fix round 2: what a failure leaves behind. An observation that ends stays failed for the run however
/// the other sources do (review S-1); a new day's route whose edit was dropped waits for nothing (review N-1).
extension ProgramStoreTests {
    @Test("7. An observation that ended keeps the failed state for the run, though later reads of workouts succeed")
    func observationEnded_staysFailed_throughLaterReads() async throws {
        let scene = try ProgramStoreScene { values, _ in values.settingsRepository = OnceSettings() }
        let running = await scene.running()
        await eventually { scene.store.loggedWeeks != nil }
        #expect(scene.store.state == .failed)
        let workout = try await finishedWorkout(of: scene.stored(), weekIndex: 7)
        _ = try await scene.memory.workouts.materialize(workout, slotUpdates: [], droppingLog: false)
        await eventually { scene.store.loggedWeeks == [7] }
        #expect(scene.store.state == .failed, "a successful read does not bring a dead observation back")
        await running.cancel()
    }

    @Test("13. A new day's route whose edit was dropped with another program's edits waits for nothing")
    func addDay_droppedWithAnotherProgram_doesNotBlockTheNextTap() async throws {
        let scene = try ProgramStoreScene()
        let renamed = try Program(
            id: ProgramID(Fixtures.uuid(66666)),
            name: "Other block",
            startDate: #require(CivilDate(year: 2026, month: 9, day: 7)),
            weeks: (0 ..< 3).map { Week(id: WeekID(Fixtures.uuid(66700 + $0)), index: $0) },
            days: []
        )
        try await scene.memory.programs.save(renamed)
        let running = await scene.running()
        await scene.probe.hold(.updateProgram)
        scene.store.send(.rename("Waiting"))
        try await scene.probe.waitUntilHeld()
        try scene.store.send(#require(scene.model.days.addDay.action))
        #expect(scene.store.routeAfterSave != nil)
        try await scene.memory.programs.setActive(renamed.id)
        await scene.probe.release()
        await scene.idle()
        await eventually { scene.store.session.stored?.id == renamed.id }
        #expect(scene.store.routeAfterSave == nil, "its edit was dropped with the other program's")
        try scene.store.send(#require(scene.model.days.addDay.action))
        await eventually { scene.store.pendingRoute != nil }
        #expect(try await scene.stored().days.count == 1)
        await running.cancel()
    }
}
