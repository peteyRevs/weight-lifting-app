@testable import FeatureOnboarding
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F08 S2, criteria 1 and 2: what the store opens on, the picks and the steps. The program a save writes is in
/// `OnboardingStoreSaveTests`, failures and retries in `OnboardingStoreFailureTests`, taps and cancellation around
/// a running save in `OnboardingStoreSaveOnceTests`.
@Suite("OnboardingStore", .timeLimit(.minutes(1)))
struct OnboardingStoreTests {
    @Test("The bundled catalog is read: the seeds of these suites are not empty")
    func bundledCatalog_isRead() throws {
        #expect(try StoreScene.catalog == ExerciseCatalog.seed())
        #expect(StoreScene.catalog.count > 200)
    }

    @Test("It opens on step 1 with Both and four days picked, and no save asked for")
    func defaults_areBothAndFourDays() async throws {
        try await StoreScene.run { scene in
            #expect(scene.store.state == OnboardingState())
            #expect(scene.store.state.step == .goal)
            #expect(scene.store.state.goal == .both)
            #expect(scene.store.state.days == .four)
            #expect(scene.store.state.phase == .editing)
            #expect(scene.store.attempt == nil)
        }
    }

    @Test("Picking changes the pick and nothing else; Continue and Back move one step and stop at the ends")
    func picksAndSteps_changeOnlyWhatWasAskedFor() async throws {
        try await StoreScene.run { scene in
            let store = scene.store
            store.send(.back)
            #expect(store.state.step == .goal)
            store.send(.pickGoal(.strength))
            #expect(store.state == OnboardingState(goal: .strength))
            store.send(.advance)
            #expect(store.state == OnboardingState(step: .days, goal: .strength))
            store.send(.pickDays(.six))
            store.send(.advance)
            #expect(store.state == OnboardingState(step: .program, goal: .strength, days: .six))
            store.send(.advance)
            #expect(store.state.step == .program)
            #expect(store.attempt == nil)
        }
    }

    @Test("The picks survive going back and forth")
    func picks_surviveGoingBackAndForth() async throws {
        try await StoreScene.run { scene in
            let store = scene.store
            store.send(.pickGoal(.consistency))
            store.send(.advance)
            store.send(.pickDays(.three))
            store.send(.advance)
            store.send(.back)
            store.send(.back)
            #expect(store.state == OnboardingState(goal: .consistency, days: .three))
            store.send(.advance)
            #expect(store.state == OnboardingState(step: .days, goal: .consistency, days: .three))
            store.send(.advance)
            #expect(store.state == OnboardingState(step: .program, goal: .consistency, days: .three))
        }
    }

    @Test("Settings that cannot be read leave the default's unit, and the screen stays as it was")
    func loadUnits_failure_keepsTheDefault() async throws {
        try await StoreScene.run(changes: [.settingsCannotBeRead]) { scene in
            await scene.store.loadUnits()
            #expect(scene.store.state == OnboardingState())
            #expect(scene.store.model.error == nil)
        }
    }

    @Test("The model is the presentation of the state, in the injected locale")
    func model_isThePresentationOfTheState() async throws {
        try await StoreScene.run { scene in
            scene.store.send(.pickGoal(.hypertrophy))
            scene.store.send(.advance)
            let expected = OnboardingPresentation.make(scene.store.state, locale: Fixtures.locale)
            #expect(scene.store.model == expected)
            #expect(scene.store.model.progressLabel == "Step 2 of 3")
        }
    }
}
