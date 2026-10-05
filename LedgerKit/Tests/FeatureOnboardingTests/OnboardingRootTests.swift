#if os(iOS)
    @testable import FeatureOnboarding
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// Counts the calls of a closure the root keeps.
    final class Tally {
        var calls = 0
    }

    /// `OnboardingRoot` itself, hosted in a window on the simulator, with the store it draws: its tasks run the
    /// store's work, the unit read and the retry's preparation included. The store's own behaviour is in the
    /// `OnboardingStore` suites, and what the scroll view adds in `OnboardingScrollTests`.
    ///
    /// Only the pinned part's tree is read here, with the reader's `outsideScrollViews: true`. The root's screen
    /// holds the page in a scroll view, which the hosted reader cannot see inside: what each step reads as is
    /// pinned on the page and the pinned part (`OnboardingAccessibilityTests`), and taps on the page inside the
    /// real scroll view are S3's nightly UI test (testing-strategy §2.6).
    @Suite("OnboardingRoot", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
    struct OnboardingRootTests {
        @Test("The root opens on step 1 with nothing asked, and its pinned buttons reach its store")
        func root_opensOnStepOne_andItsPinnedButtonsAnswer() async throws {
            try await StoreScene.run { scene in
                // The public root, which makes its own store, opens with the same pinned part.
                let opened = OnboardingRoot().accessibilityElements(outsideScrollViews: true).map(\.label)
                #expect(opened == ["Continue", "Skip setup"])

                let root = OnboardingRoot(store: scene.store, prepareRetry: {})
                root.withLiveAccessibilityElements(outsideScrollViews: true) { read in
                    @MainActor
                    func pinned() -> [String] {
                        read().map { $0.accessibilityLabel ?? "" }
                    }
                    @MainActor
                    func activate(_ label: String) {
                        _ = read().first { $0.accessibilityLabel == label }?.accessibilityActivate()
                    }
                    #expect(pinned() == ["Continue", "Skip setup"])
                    #expect(scene.store.state == OnboardingState())
                    #expect(scene.store.attempt == nil)

                    activate("Continue")
                    #expect(scene.store.state.step == .days)
                    activate("Continue")
                    #expect(scene.store.state.step == .program)
                    #expect(pinned() == ["Start training", "Skip setup"])

                    activate("Skip setup")
                    #expect(scene.store.attempt == OnboardingSaveAttempt(number: 1, goal: .both, days: .four))
                    activate("Start training")
                    #expect(scene.store.attempt?.number == 1, "one attempt, whatever is tapped during the save")
                }
            }
        }

        @Test("An accepted tap makes the root's task save: Skip setup writes the default program, once")
        func root_runsTheSaveItsStoreAsksFor() async throws {
            try await StoreScene.run { scene in
                await Hosted.view(OnboardingRoot(store: scene.store, prepareRetry: {})) { _ in
                    scene.store.send(.skipSetup)
                    await Hosted.until { scene.store.state.phase == .saved }
                }
                let expected = try StoreScene.expectedProgram(goal: .both, days: .four)
                #expect(scene.programs.saved == [expected])
            }
        }

        @Test("The root reads the stored unit when it appears, and hands its prepareRetry to the retry")
        func root_loadsTheUnit_andPreparesARetry() async throws {
            let preparations = Tally()
            try await StoreScene.run(seed: InMemoryStores.Seed(settings: Fixtures.settingsKg)) { scene in
                let root = OnboardingRoot(store: scene.store) {
                    preparations.calls += 1
                    try? await scene.seedCatalog()
                }
                await Hosted.view(root) { _ in
                    await Hosted.until { scene.store.state.units == .kg }
                    #expect(scene.store.attempt == nil, "the unit was read by the root's first task, before any save")

                    scene.store.send(.advance)
                    scene.store.send(.advance)
                    scene.store.send(.startTraining)
                    await Hosted.until { scene.store.state.phase == .failed }
                    #expect(preparations.calls == 0)

                    scene.store.send(.retry)
                    await Hosted.until { scene.store.state.phase == .saved }
                }
                #expect(preparations.calls == 1)
                #expect(scene.programs.saved.count == 1)
                #expect(scene.programs.saved.first?.days.first?.slots.first?.startLoad == .kilograms(20))
            }
        }
    }
#endif
