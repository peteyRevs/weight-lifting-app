#if os(iOS)
    @testable import FeatureOnboarding
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import Observation
    import SwiftUI
    import Testing
    import UIKit

    /// Counts the calls of a closure the root keeps.
    final class Tally {
        var calls = 0
    }

    /// `OnboardingRoot` itself, hosted in a window on the simulator: what it opens on (criterion 1), that taps on
    /// its controls reach its store and come back as the next step, and that its tasks run the store's work, the
    /// retry's preparation included. The store's own behaviour is in the `OnboardingStore` suites; here the store
    /// is the one the hosted root draws.
    @Suite("OnboardingRoot", .serialized, .timeLimit(.minutes(1)))
    struct OnboardingRootTests {
        private static func stops(_ elements: [NSObject]) -> [Stop] {
            elements.map {
                Stop($0.accessibilityLabel ?? "", value: $0.accessibilityValue ?? "", $0.accessibilityTraits)
            }
        }

        private static func tap(_ label: String, in elements: [NSObject]) -> Bool {
            elements.first { $0.accessibilityLabel == label }?.accessibilityActivate() ?? false
        }

        /// Hosts `root` in a window for as long as `body` runs, so its `.task`s start and stay alive across the
        /// body's suspensions. (`withLiveAccessibilityElements` takes a synchronous body, and takes the window
        /// down when it returns.)
        private static func hosting(_ root: OnboardingRoot, _ body: () async throws -> Void) async rethrows {
            let host = UIHostingController(rootView: root)
            let window = SceneLessWindow.make(frame: CGRect(x: 0, y: 0, width: SnapshotConfig.phoneWidth, height: 874))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            try await body()
        }

        /// Suspends until `condition` holds of what the store shows, as the root's tasks change it. No polling:
        /// `Observations` wakes on each change of what `condition` read.
        private static func until(_ condition: @escaping @MainActor @Sendable () -> Bool) async {
            for await holds in Observations(condition) where holds {
                return
            }
        }

        @Test("OnboardingRoot opens on step 1 of 3, with Both picked and the bars read as one step count")
        func root_opensOnStepOne() {
            let found = withTestDependencies {
                $0.inMemoryStores(seed: .seeded())
            } operation: {
                OnboardingRoot().accessibilityElements().map { Stop($0.label, value: $0.value, $0.traits) }
            }
            #expect(found == OnboardingTrees.all.first?.expected)
        }

        @Test("Taps go through the root: a pick moves the selection, Continue and Back move the step, picks stay")
        func root_taps_pickAndStep() {
            withTestDependencies {
                $0.inMemoryStores(seed: .seeded())
            } operation: {
                OnboardingRoot().withLiveAccessibilityElements { read in
                    #expect(Self.tap("Get stronger, Low reps, linear load increases", in: read()))
                    let picked = Self.stops(read())
                    #expect(picked.filter { $0.traits & UIAccessibilityTraits.selected.rawValue != 0 } == [
                        .button("Get stronger, Low reps, linear load increases", .selected)
                    ])

                    #expect(Self.tap("Continue", in: read()))
                    #expect(Self.stops(read()) == OnboardingTrees.all[1].expected)
                    #expect(Self.tap("6 days, Body-part split", in: read()))
                    #expect(Self.tap("Continue", in: read()))
                    let program = Self.stops(read())
                    #expect(program.contains(.text("Body-Part Split, 8 weeks, pounds. Editable any time.")))
                    #expect(program.contains(.button("Start training")))
                    #expect(program.count(where: { $0.traits == UIAccessibilityTraits.staticText.rawValue }) == 7)

                    #expect(Self.tap("Back", in: read()))
                    #expect(Self.stops(read()).contains(.button("6 days, Body-part split", .selected)))
                    #expect(Self.tap("Back", in: read()))
                    #expect(Self.stops(read()).contains(
                        .button("Get stronger, Low reps, linear load increases", .selected)
                    ))
                    #expect(!Self.stops(read()).contains(.button("Back")))
                }
            }
        }

        @Test("An accepted tap makes the root's task save: Skip setup writes the default program, once")
        func root_runsTheSaveItsStoreAsksFor() async throws {
            try await StoreScene.run { scene in
                await Self.hosting(OnboardingRoot(store: scene.store, prepareRetry: {})) {
                    scene.store.send(.skipSetup)
                    await Self.until { scene.store.state.phase == .saved }
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
                await Self.hosting(root) {
                    await Self.until { scene.store.state.units == .kg }
                    #expect(scene.store.attempt == nil, "the unit was read by the root's first task, before any save")

                    scene.store.send(.advance)
                    scene.store.send(.advance)
                    scene.store.send(.startTraining)
                    await Self.until { scene.store.state.phase == .failed }
                    #expect(preparations.calls == 0)

                    scene.store.send(.retry)
                    await Self.until { scene.store.state.phase == .saved }
                }
                #expect(preparations.calls == 1)
                #expect(scene.programs.saved.count == 1)
                #expect(scene.programs.saved.first?.days.first?.slots.first?.startLoad == .kilograms(20))
            }
        }
    }
#endif
