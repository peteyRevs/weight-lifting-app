#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import Foundation
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import Observation
    import SwiftUI
    import Testing
    import UIKit

    /// F11 S13 adversarial round 3: the root's sources keyed by the scene's phase, its save loop not (fix round 2).
    /// A write in flight while the app goes to the background and comes back is neither cancelled nor sent twice.
    @MainActor
    @Suite("Adversarial F11 S13 · a write across the background", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
    struct ProgramRootPhaseAdversarialTests {
        @MainActor @Observable
        final class Phase {
            var asked = ScenePhase.active
            var shown: ScenePhase?
        }

        struct Host: View {
            let store: ProgramStore
            let phase: Phase

            var body: some View {
                ProgramRoot(store: store, onRoute: { _ in }, announce: { _ in })
                    .environment(\.scenePhase, phase.asked)
                    .onChange(of: phase.asked, initial: true) { _, asked in phase.shown = asked }
            }
        }

        private static func hosting(_ view: some View, _ body: () async throws -> Void) async rethrows {
            let host = UIHostingController(rootView: view)
            let window = SceneLessWindow.make(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            try await body()
        }

        private static func move(_ phase: Phase, to asked: ScenePhase) async {
            phase.asked = asked
            await s13Until { phase.shown == asked }
        }

        /// Background and back while the probe holds the write, then let it go.
        private static func roundTrip(afterStoring: Bool) async throws {
            let rig = try S13Rig()
            let phase = Phase()
            try await Self.hosting(Host(store: rig.store, phase: phase)) {
                await s13Until { rig.model != nil }
                await rig.probe.hold(.updateProgram, afterStoring: afterStoring)
                rig.store.send(.addWeek(selecting: 8))
                try await rig.probe.waitUntilHeld()
                await Self.move(phase, to: .inactive)
                await Self.move(phase, to: .background)
                #expect(rig.session.isWriting, "going to the background does not end the write")
                await Self.move(phase, to: .active)
                await rig.probe.release()
                await rig.settled()
                let stored = try #require(try await rig.storedProgram())
                #expect(stored.weeks.count == 9, "added once")
                #expect(await rig.updates() == 1, "sent once")
                #expect(rig.store.notice == nil)
                await s13Until { rig.session.shown == stored }
                #expect(rig.model?.block.chips.count == 9)
            }
        }

        @Test("A write held before the store across background → active is stored once, not cancelled")
        func heldBeforeStoring_acrossTheBackground_storedOnce() async throws {
            try await Self.roundTrip(afterStoring: false)
        }

        @Test("A write held after storing across background → active is adopted once; the screen ends on the store")
        func heldAfterStoring_acrossTheBackground_adoptedOnce() async throws {
            try await Self.roundTrip(afterStoring: true)
        }

        @Test("In the background the sources' end is not a failure: back to active, the builder is shown, not failed")
        func background_isNotAFailure() async throws {
            let rig = try S13Rig()
            let phase = Phase()
            await Self.hosting(Host(store: rig.store, phase: phase)) {
                await s13Until { rig.model != nil }
                await Self.move(phase, to: .background)
                #expect(rig.store.state != .failed)
                await Self.move(phase, to: .active)
                await s13Until { rig.model != nil }
                #expect(rig.store.state != .failed)
            }
        }
    }
#endif
