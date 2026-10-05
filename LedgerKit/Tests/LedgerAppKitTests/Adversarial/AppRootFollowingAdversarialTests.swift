#if os(iOS)
    import Foundation
    import GRDB
    @testable import LedgerAppKit
    import LedgerDomain
    import LedgerPersistence
    import SwiftUI
    import Testing

    /// F08 S3 adversarial round 1 (G2), criteria 3, 4 and 8 (revised): the hosted root keeps its screen through
    /// the scene leaving and returning, mid-onboarding and mid-save; a program that arrives switches it to the
    /// tabs; two roots follow one store; and a second boot on the same file opens on the tabs. The return to
    /// onboarding when the program goes away is `AppRootResetAdversarialTests`' (round 2).
    @Suite("Adversarial F08 S3 · the real root keeps following", .serialized, .timeLimit(.minutes(1)))
    struct AppRootFollowingAdversarialTests {
        typealias Onboarding = AppRootOnboardingAdversarialTests

        /// Changes the scene's phase and suspends until the root's next call has read the active program anew.
        static func move(_ scene: GateRootScene, to phase: ScenePhase) async {
            let reads = scene.app.journal.activeProgramReads.count
            scene.move(to: phase)
            await scene.app.journal.until { entries in
                entries.count { $0.hasPrefix("sql ") && $0.contains("FROM program WHERE is_active = 1") } > reads
            }
        }

        @Test("The scene leaves and returns mid-onboarding: the step stays, the root never bounces, and it still saves")
        func phaseChanges_midOnboarding_keepTheStep() async throws {
            let app = GateApp()
            defer { app.remove() }
            try await GateRootScene.run(app) { scene in
                scene.tap("Continue")
                scene.tap("Continue")
                for phase in [ScenePhase.inactive, .background, .inactive, .active, .background, .active] {
                    await Self.move(scene, to: phase)
                    let shown = scene.host.shown
                    #expect(shown.isOnboarding, "after \(phase): \(shown)")
                    #expect(shown.labels == ["Start training", "Skip setup"], "after \(phase): step 3 was left")
                }
                scene.tap("Start training")
                await app.journal.until("programs.save done")
                await gateObserved { scene.gate.destination == .main }
                #expect(scene.host.shown.isTabs)
                #expect(scene.recorder.seen == [.onboarding, .main], "\(scene.recorder.seen)")
                // The unit is read once when onboarding appears, and once by the save: a third read is a
                // second onboarding screen, made when the first was taken out of the tree.
                #expect(app.journal.count(of: "settings.load begins") == 2)
                try await Onboarding.expectTheDefault(scene.theOneProgram(), in: scene)
            }
        }

        @Test(
            "The scene leaves mid-save: the save is not cancelled, one program is stored, and the root shows the tabs"
        )
        func phaseChanges_midSave_keepTheSave() async throws {
            let app = GateApp()
            defer { app.remove() }
            try await GateRootScene.run(app) { scene in
                scene.tap("Continue")
                scene.tap("Continue")
                let release = scene.holdNextSave()
                scene.tap("Start training")
                await app.journal.until("programs.save waits")
                await Self.move(scene, to: .inactive)
                await Self.move(scene, to: .background)
                #expect(scene.host.shown.isOnboarding)
                try await scene.expectRows("program", 0)
                release.wake()
                await app.journal.until("programs.save done")
                #expect(app.journal.count(of: "programs.save on a cancelled task") == 0)
                await gateObserved { scene.gate.destination == .main }
                await Self.move(scene, to: .active)
                #expect(scene.host.shown.isTabs)
                #expect(scene.recorder.seen == [.onboarding, .main], "\(scene.recorder.seen)")
                #expect(app.journal.count(of: "programs.save begins") == 1)
                try await Onboarding.expectTheDefault(scene.theOneProgram(), in: scene)
            }
        }
    }

    extension AppRootFollowingAdversarialTests {
        @Test("The scene leaves and returns on the tabs: the selected tab stays, and the root never leaves the tabs")
        func phaseChanges_onTheTabs_keepTheSelection() async throws {
            let app = GateApp()
            defer { app.remove() }
            try await app.arrange { try await GatePrograms.store([GatePrograms.make()], in: $0) }
            try await GateRootScene.run(app) { scene in
                #expect(scene.host.shown.isTabs)
                #expect(scene.host.tapTab(at: 2))
                #expect(scene.host.shown.labels == ["Library"], "control: the lifter is on Library")
                for phase in [ScenePhase.inactive, .background, .inactive, .active] {
                    await Self.move(scene, to: phase)
                    let shown = scene.host.shown
                    #expect(shown.labels == ["Library"], "after \(phase): \(shown)")
                    #expect(shown.tabBars == 1)
                }
                #expect(scene.recorder.seen == [.main], "\(scene.recorder.seen)")
            }
        }

        @Test("A program that arrives by another route while onboarding is shown switches the root to the tabs")
        func programArrives_midOnboarding_showsTheTabs() async throws {
            let app = GateApp()
            defer { app.remove() }
            try await GateRootScene.run(app) { scene in
                scene.tap("Continue")
                try await scene.stores.programs.save(GatePrograms.make(days: .six))
                await gateObserved { scene.gate.destination == .main }
                let shown = scene.host.shown
                #expect(shown.isTabs, "\(shown)")
                #expect(!scene.host.activate("Skip setup"), "onboarding is gone: it can save no second program")
                try await scene.expectRows("program", 1)
                #expect(app.journal.count(of: "programs.save begins") == 0)
            }
        }

        @Test("Two roots over one composition: onboarding in one saves, and both switch to the tabs")
        func twoRoots_oneComposition_bothFollow() async {
            let app = GateApp()
            defer { app.remove() }
            let composition = app.booted()
            let gates = await [GateAnswers.followed(composition), GateAnswers.followed(composition)]
            await withGateDependencies(composition, app.journal) {
                let hosts = gates.map { GateHost(AppRoot(composition: composition, gate: $0)) }
                defer { hosts.forEach { $0.close() } }
                #expect(hosts.map(\.shown.isOnboarding) == [true, true])
                #expect(hosts[0].activate("Skip setup"))
                await app.journal.until("programs.save done")
                await gateObserved { gates.allSatisfy { $0.destination == .main } }
                #expect(hosts.map(\.shown.isTabs) == [true, true])
                #expect(app.journal.count(of: "launch began seedCatalog") == 1)
                #expect(app.journal.count(of: "programs.save begins") == 1)
            }
        }

        @Test(
            "Criterion 8: after onboarding saved a program, a second boot on that file shows the ground, then the tabs"
        )
        func relaunch_afterOnboarding_showsTheTabs() async throws {
            let app = GateApp()
            defer { app.remove() }
            try await GateRootScene.run(app) { scene in
                scene.tap("Skip setup")
                await app.journal.until("programs.save done")
                await gateObserved { scene.gate.destination == .main }
                #expect(scene.host.shown.isTabs)
            }
            let second = app.booted() // the same file, a new composition: the next launch
            #expect(AppRootGateAdversarialTests.drawsTheGroundAlone(AppRoot(composition: second), .dark))
            let gate = RootGate()
            let recorder = GateDestinationRecorder(gate)
            await withGateDependencies(second, app.journal) {
                let host = GateHost(AppRoot(composition: second, gate: gate))
                defer { host.close() }
                let first = host.shown
                #expect(first.isGround, "\(first)")
                await gateObserved { gate.destination != .loading }
                let next = host.shown
                #expect(next.isTabs, "\(next)")
                #expect(recorder.seen == [.loading, .main], "\(recorder.seen)")
            }
        }
    }
#endif
