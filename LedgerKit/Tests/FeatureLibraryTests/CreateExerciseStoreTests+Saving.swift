@testable import FeatureLibrary
import Foundation
import LedgerDomain
import Testing

/// F12 S3, N16: a double tap, a failure and a cancellation, in a file of their own for the suite's length.
extension CreateExerciseStoreTests {
    @Test("N16. A second tap while the save runs does nothing: one attempt, one save")
    func doubleTap_savesOnce() async {
        let scene = CreateScene(holdsRead: true)
        scene.fillCriterion9()
        scene.store.send(.save)
        scene.store.send(.save)
        scene.store.send(.setName("Changed"))
        #expect(scene.store.attempt == 1)
        #expect(scene.store.draft.name == "Landmine Squeeze Press 2", "nothing changes while it saves")
        let first = Task { await scene.store.save() }
        while !scene.exercises.isHoldingRead {
            await Task.yield()
        }
        await scene.store.save()
        scene.exercises.releaseRead()
        await first.value
        #expect(scene.exercises.saves.count == 1)
        #expect(scene.store.phase == .saved)
    }

    @Test("N16. A save that fails keeps the sheet up with the draft and a line, and Save works again")
    func failure_keepsTheSheet() async throws {
        let scene = CreateScene(failures: 1)
        scene.fillCriterion9()
        scene.store.send(.save)
        await scene.store.save()
        #expect(scene.store.phase == .editing)
        #expect(scene.store.model.foot.problem == "Couldn't save the exercise. Try again.")
        #expect(scene.store.model.foot.action == .save)
        #expect(scene.store.draft.name == "Landmine Squeeze Press 2")
        #expect(try await scene.stored("Landmine Squeeze Press 2") == nil)
        scene.store.send(.save)
        await scene.store.save()
        #expect(scene.store.phase == .saved)
        #expect(scene.exercises.saves.count == 2)
        #expect(try await scene.stored("Landmine Squeeze Press 2") != nil)
    }

    @Test("N16. A save cancelled before its write, as the sheet goes down, stores nothing and shows nothing")
    func cancellation_changesNothing() async throws {
        let scene = CreateScene(holdsRead: true)
        scene.fillCriterion9()
        scene.store.send(.save)
        let running = Task { await scene.store.save() }
        while !scene.exercises.isHoldingRead {
            await Task.yield()
        }
        running.cancel()
        scene.exercises.releaseRead()
        await running.value
        #expect(scene.exercises.saves.isEmpty)
        #expect(scene.store.phase == .editing)
        #expect(scene.store.problem == nil)
        #expect(try await scene.stored("Landmine Squeeze Press 2") == nil)
    }
}
