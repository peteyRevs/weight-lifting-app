@testable import FeatureOnboarding
import Foundation
import LedgerDomain
import LedgerSnapshotTesting
import LedgerTestSupport
import SwiftUI
import Testing

/// F08 S2 adversarial round 1, criteria 4, 6, 7 and 11 through the root itself: hosted in a window, its own
/// `.task`s run the store's work, so these check the wiring a store test stands in for, and what is left of the
/// store and its work once the view has gone.
@Suite("Adversarial F08 S2 · the root, its tasks and its life", .timeLimit(.minutes(1)))
struct OnboardingRootAdversarialTests {
    @Test("A store nobody shows is freed when it is let go: it holds no task and no cycle of its own")
    func store_neverShown_isFreed() async throws {
        let freed = DeinitSignal()
        weak var store: OnboardingStore?
        do {
            let scene = try AdversarialScene(.seeded())
            await scene.store.loadUnits()
            scene.walk(goal: .strength, days: .three)
            await scene.tap(.startTraining)
            #expect(scene.programs.saved.count == 1)
            freed.watch(scene.store)
            store = scene.store
        }
        await freed.wait()
        #expect(store == nil)
    }

    #if os(iOS)
        /// The root on the scene's store, with the scene's retry step, in a window.
        static func host(_ scene: AdversarialScene) -> PhoneHost {
            PhoneHost(OnboardingRoot(store: scene.store, prepareRetry: { await scene.prepareRetry() }), on: .seventeen)
        }

        @Test("The root reads the stored unit by itself: step 3 says kilograms without a tap")
        func root_storedKilograms_saysKilograms() async throws {
            let scene = try AdversarialScene(.seeded(Fixtures.settingsKg))
            scene.walk(goal: .both, days: .four)
            #expect(scene.store.model.body == BriefCopy.programBody(.four, .lb), "control: not read yet")
            let host = Self.host(scene)
            defer { host.close() }
            await observed { scene.store.state.units == .kg }
            #expect(scene.store.model.body == "Upper / Lower, 8 weeks, kilograms. Editable any time.")
            #expect(scene.programs.offered.isEmpty, "showing the screen saves nothing")
        }

        @Test("Start training on the hosted root saves one program through the root's own task, however often tapped")
        func root_startTraining_savesOneThroughItsTask() async throws {
            let scene = try AdversarialScene(.seeded(Fixtures.settingsKg))
            scene.walk(goal: .hypertrophy, days: .five)
            let host = Self.host(scene)
            defer { host.close() }
            scene.store.send(.startTraining)
            scene.store.send(.startTraining)
            scene.store.send(.skipSetup)
            await observed { scene.store.state.phase == .saved }
            scene.store.send(.startTraining)
            scene.store.send(.skipSetup)
            try await scene.expectOneProgram(goal: .hypertrophy, days: .five)
            #expect(scene.journal.count(of: "prepare.start") == 0)
        }

        @Test("A failed save on the hosted root shows the sentence; Retry awaits the root's step once, then saves")
        func root_failureThenRetry_awaitsTheRootsStep() async throws {
            let scene = AdversarialScene(.unseeded)
            let exercises = scene.stores.exercises
            scene.onPrepare = {
                // A seed that fails here leaves the catalog empty, and the retry then fails the test.
                try? await exercises.seedIfNeeded(ExerciseCatalog.seed(), version: ExerciseCatalog.version)
            }
            scene.walk(goal: .consistency, days: .six)
            let host = Self.host(scene)
            defer { host.close() }
            scene.store.send(.startTraining)
            await observed { scene.store.model.error != nil }
            #expect(scene.store.model.error == BriefCopy.saveFailed)
            #expect(scene.programs.offered.isEmpty)
            #expect(scene.journal.count(of: "prepare.start") == 0)
            scene.store.send(.retry)
            scene.store.send(.retry)
            await observed { scene.store.state.phase == .saved }
            #expect(scene.journal.count(of: "prepare.start") == 1)
            #expect(scene.journal.count(of: "prepare.end") == 1)
            try await scene.expectOneProgram(goal: .consistency, days: .six)
        }

        @Test("The view goes away mid-save: its tasks are cancelled, nothing is written, and the store is freed")
        func root_goneMidSave_cancelsItsWorkAndFreesTheStore() async throws {
            let hold = Checkpoint()
            let freed = DeinitSignal()
            weak var store: OnboardingStore?
            let programs: ProbedPrograms
            do {
                let scene = try AdversarialScene(.seeded())
                // Every read of the settings waits, and gives up when its task is cancelled: the screen's own
                // read when it appears, then the save's.
                scene.settings.script.otherwise(.holdUnlessCancelled(hold))
                scene.walk(goal: .strength, days: .six)
                freed.watch(scene.store)
                store = scene.store
                programs = scene.programs
                let host = PhoneHost(OnboardingRoot(store: scene.store, prepareRetry: {}), on: .seventeen)
                scene.store.send(.startTraining)
                await hold.arrivals(2)
                host.close()
            }
            await hold.cancellation()
            await freed.wait()
            #expect(store == nil, "the store outlives its view: something still holds it")
            #expect(programs.offered.isEmpty)
        }

        @Test("The view goes away with nothing running: the store is freed")
        func root_goneWhileIdle_freesTheStore() async throws {
            let freed = DeinitSignal()
            weak var store: OnboardingStore?
            do {
                let scene = try AdversarialScene(.seeded(Fixtures.settingsKg))
                freed.watch(scene.store)
                store = scene.store
                let host = PhoneHost(OnboardingRoot(store: scene.store, prepareRetry: {}), on: .seventeen)
                await observed { scene.store.state.units == .kg }
                scene.store.send(.advance)
                host.close()
            }
            await freed.wait()
            #expect(store == nil, "the store outlives its view: something still holds it")
        }
    #endif
}
