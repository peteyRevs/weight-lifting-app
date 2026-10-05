@testable import FeatureOnboarding
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F08 S2, criterion 4's last sentence: exactly one program, whatever is tapped and whenever. A second tap, a tap
/// while the save runs, a tap after it succeeded, a second run of the same attempt, and a save cancelled because
/// its view went away. No test sleeps: a `Gate` holds a double until the test has acted.
@Suite("OnboardingStore: one program", .tags(.feature), .timeLimit(.minutes(1)))
struct OnboardingStoreSaveOnceTests {
    /// Every action the screen can send.
    nonisolated static let everyAction: [OnboardingAction] = [
        .pickGoal(.strength), .pickDays(.six), .advance, .back, .startTraining, .skipSetup, .retry
    ]

    @Test("The root's task runs before any tap: it saves nothing")
    func save_beforeAnyTap_doesNothing() async throws {
        try await StoreScene.run { scene in
            await scene.save()
            #expect(scene.programs.saved.isEmpty)
            #expect(scene.store.state == OnboardingState())
        }
    }

    @Test("A double tap asks for one save, and one program is saved")
    func save_twice_savesOneProgram() async throws {
        try await StoreScene.run { scene in
            scene.store.send(.startTraining)
            let first = scene.store.attempt
            scene.store.send(.startTraining)
            scene.store.send(.skipSetup)
            #expect(scene.store.attempt == first, "the task's id does not change, so the root starts no second task")
            #expect(first?.number == 1)
            await scene.save()
            await scene.save()
            #expect(scene.programs.saved.count == 1)
        }
    }

    @Test("After a save succeeded, no tap and no further run of the task saves anything more")
    func save_afterSuccess_doesNothing() async throws {
        try await StoreScene.run { scene in
            await scene.startTraining()
            let saved = scene.store.state
            let attempt = scene.store.attempt
            #expect(saved.phase == .saved)
            for action in Self.everyAction {
                scene.store.send(action)
                await scene.save()
                #expect(scene.store.state == saved, "\(action)")
                #expect(scene.store.attempt == attempt, "\(action)")
            }
            #expect(scene.programs.saved.count == 1)
            #expect(!scene.store.model.canProceed && !scene.store.model.canEdit)
        }
    }

    @Test("While a save runs, every tap is ignored and a second run of the task returns at once")
    func tapsDuringASave_areIgnored() async throws {
        let gate = Gate()
        try await StoreScene.run(changes: [.catalogWaits(gate)]) { scene in
            scene.store.send(.skipSetup)
            let running = Task { await scene.save() }
            await gate.entered()

            let midSave = scene.store.state
            let attempt = scene.store.attempt
            #expect(midSave.phase == .saving)
            #expect(!scene.store.model.canProceed && !scene.store.model.canEdit)
            for action in Self.everyAction {
                scene.store.send(action)
                #expect(scene.store.state == midSave, "\(action)")
                #expect(scene.store.attempt == attempt, "\(action)")
            }
            await scene.save() // the same attempt again, as a view that reappears would run it
            #expect(scene.programs.saved.isEmpty, "the second run did not save in place of the first")

            gate.open()
            await running.value
            #expect(scene.programs.saved.count == 1)
            #expect(scene.store.state.phase == .saved)
        }
    }

    @Test("A save cancelled before its write saves nothing and leaves the tap to make again")
    func save_cancelledMidFlight_savesNothing_andCanBeTappedAgain() async throws {
        let gate = Gate()
        try await StoreScene.run(changes: [.catalogWaits(gate)]) { scene in
            scene.store.send(.pickGoal(.hypertrophy))
            scene.store.send(.advance)
            scene.store.send(.advance)
            scene.store.send(.startTraining)
            let running = Task { await scene.save() }
            await gate.entered()
            running.cancel() // the view went away
            await running.value

            #expect(scene.programs.saved.isEmpty)
            let active = try await scene.stores.programs.active()
            #expect(active == nil)
            #expect(scene.store.state == OnboardingState(step: .program, goal: .hypertrophy))
            #expect(scene.store.model.error == nil, "a cancelled save is not a failed one")

            await scene.save() // the view returns and its task runs the same attempt
            #expect(scene.programs.saved.isEmpty, "the cancelled attempt is not run again by itself")

            scene.store.send(.startTraining)
            #expect(scene.store.attempt?.number == 2)
            await scene.save()
            #expect(scene.programs.saved.count == 1)
            #expect(scene.programs.saved.first?.goal == .hypertrophy)
            #expect(scene.store.state.phase == .saved)
            #expect(scene.preparations == 0, "the tap after a cancelled save is not a retry")
        }
    }

    @Test("A retry cancelled before its write saves nothing and is still a failed attempt to retry")
    func retry_cancelledMidFlight_staysFailed() async throws {
        let gate = Gate()
        try await StoreScene.run(seed: .empty, changes: [.catalogWaits(gate)]) { scene in
            scene.store.send(.skipSetup)
            let failing = Task { await scene.save() }
            await gate.entered()
            gate.open()
            await failing.value
            #expect(scene.store.state.phase == .failed)

            let second = Gate()
            scene.store.send(.retry)
            let retrying = Task {
                await scene.save {
                    try? await scene.seedCatalog()
                    await second.pass()
                }
            }
            await second.entered()
            retrying.cancel()
            await retrying.value

            #expect(scene.programs.saved.isEmpty)
            #expect(scene.store.state.phase == .failed)
            #expect(scene.store.model.primary.title == "Retry")

            scene.store.send(.retry)
            await scene.save()
            #expect(scene.programs.saved.count == 1)
            #expect(scene.preparations == 2)
        }
    }

    @Test("A save cancelled after the repository has written is saved: the phase follows the repository")
    func save_cancelledAfterTheWrite_isSaved() async throws {
        let gate = Gate()
        try await StoreScene.run(changes: [.saveWaitsAfterWriting(gate)]) { scene in
            scene.store.send(.skipSetup)
            let running = Task { await scene.save() }
            await gate.entered()
            #expect(scene.programs.saved.count == 1)
            running.cancel()
            await running.value

            #expect(scene.store.state.phase == .saved)
            scene.store.send(.skipSetup)
            await scene.save()
            #expect(scene.programs.saved.count == 1)
            let active = try await scene.stores.programs.active()
            #expect(active == scene.programs.saved.first)
        }
    }
}
