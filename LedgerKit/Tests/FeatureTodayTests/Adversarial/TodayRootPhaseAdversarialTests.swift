#if os(iOS) && DEBUG
    @testable import FeatureToday
    import Foundation
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F09 S5 adversarial round 2 (G2), criterion 14: `TodayRoot` hosted under a scene phase the test moves.
    /// The root's task has the id `scenePhase == .background` and runs nothing while that is true. Attacked:
    /// a launch that starts inactive, a launch in the background, trips to inactive with changes made
    /// meanwhile, a trip to the background with the rest day's list on screen and changes made there, a
    /// return in a new week, and a route asked for around the trip.
    /// (`SceneLessWindow` is internal to `LedgerSnapshotTesting`, hence the `@testable` import.)
    @MainActor
    @Suite("Adversarial: TodayRoot across the scene's phases", .serialized, .tags(.feature), .timeLimit(.minutes(2)))
    struct TodayRootPhaseAdversarialTests {
        /// The scene's phase as the test sets it, the last one SwiftUI has shown the root, and what the app
        /// was handed.
        @MainActor @Observable
        final class Stage {
            var asked: ScenePhase
            var shown: ScenePhase?
            var handed: [TodayRoute] = []

            init(_ phase: ScenePhase) {
                asked = phase
            }
        }

        struct Staged: View {
            let stage: Stage
            let store: TodayStore

            var body: some View {
                TodayRoot(store: store) { stage.handed.append($0) }
                    .environment(\.scenePhase, stage.asked)
                    .onChange(of: stage.asked, initial: true) { _, asked in stage.shown = asked }
            }
        }

        /// Hosts the root over `scene`'s store, in the phase `stage` asks for, for as long as `body` runs.
        static func hosting(
            _ scene: TodayScene,
            _ stage: Stage,
            _ body: () async throws -> Void
        ) async rethrows {
            let host = UIHostingController(rootView: Staged(stage: stage, store: scene.store))
            let window = SceneLessWindow.make(frame: CGRect(origin: .zero, size: TodayScreenTests.phone))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            try await body()
        }

        /// Moves the scene through `phases` in order, each once SwiftUI has shown the root the one before.
        static func move(_ stage: Stage, through phases: ScenePhase...) async {
            for phase in phases {
                stage.asked = phase
                let isShown = await settles { stage.shown == phase }
                #expect(isShown, "SwiftUI never showed the root \(phase)")
            }
            await drain(turns: 30)
        }

        @Test("A launch that starts inactive loads Today at once, and becoming active starts nothing again")
        func launch_inactiveThenActive_runsOnce() async throws {
            let scene = try TodayScene()
            let stage = Stage(.inactive)
            await Self.hosting(scene, stage) {
                #expect(await settles { scene.store.model != nil }, "inactive: \(scene.store.phase)")
                let publications = StatePublications(scene.store)
                await Self.move(stage, through: .active)
                #expect(scene.workouts.observations == 1)
                #expect(scene.workouts.ranges.count == 1)
                #expect(publications.changes == 0)
            }
        }

        @Test("A launch in the background runs nothing; the first step forward loads Today, once")
        func launch_inTheBackground_runsNothingUntilItComesForward() async throws {
            let scene = try TodayScene()
            let stage = Stage(.background)
            await Self.hosting(scene, stage) {
                await Self.move(stage, through: .background)
                #expect(scene.store.phase == "idle")
                #expect(scene.workouts.observations == 0)
                await Self.move(stage, through: .inactive)
                #expect(await settles { scene.store.model != nil }, "inactive: \(scene.store.phase)")
                await Self.move(stage, through: .active)
                #expect(scene.workouts.observations == 1)
            }
        }

        @Test("Five trips to inactive and back, a setting saved during each: every change is shown, by the one run")
        func inactiveAndBack_restartsNothing_andLosesNothing() async throws {
            let scene = try TodayScene()
            let stage = Stage(.active)
            try await Self.hosting(scene, stage) {
                #expect(await settles { scene.store.model != nil })
                let publications = StatePublications(scene.store)
                var settings = Fixtures.settingsLb
                for (trip, start) in [Weekday.sunday, .tuesday, .saturday, .thursday, .monday].enumerated() {
                    await Self.move(stage, through: .inactive)
                    settings.weekStart = start
                    settings.units = trip.isMultiple(of: 2) ? .kg : .lb
                    try await scene.stores.settings.save(settings)
                    let caption = trip.isMultiple(of: 2) ? "kg moved" : "lb moved"
                    #expect(await settles { scene.store.model?.stats.volume.caption == caption }, "trip \(trip)")
                    await Self.move(stage, through: .active)
                }
                #expect(scene.store.model?.weekStrip.first?.weekday == "M")
                #expect(scene.workouts.observations == 1, "no trip to inactive starts a run")
                #expect(publications.phases == ["loaded"])
            }
        }
    }
#endif
