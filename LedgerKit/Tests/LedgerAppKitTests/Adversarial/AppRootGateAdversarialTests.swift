#if os(iOS)
    import Foundation
    import GRDB
    @testable import LedgerAppKit
    import LedgerDesign
    import LedgerDomain
    import LedgerPersistence
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// F08 S3 adversarial round 1 (G2), criteria 1, 2, 4, 7 and 8 (revised): the app's real root, hosted over a
    /// real database file, read as a lifter and VoiceOver meet it: the ground until the gate has answered, then
    /// the one right screen; the can't-open-your-data state above whatever the gate says; a relaunch.
    @Suite("Adversarial F08 S3 · the real root's first screens", .serialized, .timeLimit(.minutes(1)))
    struct AppRootGateAdversarialTests {
        /// Whether `view`, drawn once as a first frame is, is the ground colour and nothing else. The two
        /// renderings are compared to one `Bool` here: a pixel buffer is never handed to an expectation.
        static func drawsTheGroundAlone(_ view: some View, _ scheme: ColorScheme) -> Bool {
            func pixels(_ view: some View) -> PixelBuffer? {
                RenderedImage.render(
                    view,
                    width: GateHost.phone.width,
                    height: GateHost.phone.height,
                    colorScheme: scheme
                )
                .flatMap(PixelBuffer.init)
            }
            guard let drawn = pixels(view), let ground = pixels(LedgerColor.ground.ignoresSafeArea()) else {
                return false
            }
            return drawn == ground
        }

        @Test(
            "The first frame is the ground alone, whatever the database holds: no tabs, no onboarding",
            arguments: [false, true],
            [ColorScheme.light, .dark]
        )
        func firstFrame_isTheGroundAlone(hasProgram: Bool, scheme: ColorScheme) async throws {
            let app = GateApp("firstFrame\(hasProgram)\(scheme)")
            defer { app.remove() }
            if hasProgram {
                try await app.arrange { try await GatePrograms.store([GatePrograms.make()], in: $0) }
            }
            let composition = app.booted()
            #expect(composition.state == .ready)
            #expect(Self.drawsTheGroundAlone(AppRoot(composition: composition), scheme))
            let host = GateHost(AppRoot(composition: composition)) // the app's own initializer, read at once
            let shown = host.shown
            host.close()
            #expect(shown.isGround, "\(shown)")
            #expect(app.journal.firstProgramStatement == nil, "a store was read before the first frame")
            await composition.resume(in: .active) // let the launch's steps end before the file is removed
        }

        @Test("A fresh install shows the ground, then onboarding on step 1 with no tab bar, and never the tabs")
        func freshInstall_showsTheGround_thenOnboarding() async throws {
            let app = GateApp()
            defer { app.remove() }
            try await GateRootScene.run(app, isAnswered: false) { scene in
                let first = scene.host.shown
                #expect(first.isGround, "\(first)")
                await gateObserved { scene.gate.destination != .loading }
                let second = scene.host.shown
                #expect(second.isOnboarding, "\(second)")
                #expect(second.labels == ["Continue", "Skip setup"], "step 1's pinned buttons")
                #expect(scene.recorder.seen == [.loading, .onboarding], "\(scene.recorder.seen)")
                try await scene.expectRows("program", 0)
            }
        }

        @Test(
            "While a slow first pass runs, the hosted root is the ground; it becomes onboarding when the pass returns"
        )
        func slowPass_showsTheGroundWhileItRuns() async throws {
            let app = GateApp()
            defer { app.remove() }
            let composition = app.booted()
            let hold = try GateWriterHold(#require(composition.stores).queue)
            let gate = RootGate()
            let recorder = GateDestinationRecorder(gate)
            await withGateDependencies(composition, app.journal) {
                let host = GateHost(AppRoot(composition: composition, gate: gate))
                defer { host.close() }
                await app.journal.until("launch began seedCatalog")
                let during = host.shown
                #expect(during.isGround, "\(during)")
                hold.free()
                await gateObserved { gate.destination != .loading }
                let after = host.shown
                #expect(after.isOnboarding, "\(after)")
                #expect(recorder.seen == [.loading, .onboarding])
            }
        }

        @Test("A lifter with a program sees the ground, then the tabs on Today, and never onboarding")
        func program_showsTheGround_thenTheTabs() async throws {
            let app = GateApp()
            defer { app.remove() }
            try await app.arrange { try await GatePrograms.store([GatePrograms.make()], in: $0) }
            try await GateRootScene.run(app, isAnswered: false) { scene in
                let first = scene.host.shown
                #expect(first.isGround, "\(first)")
                await gateObserved { scene.gate.destination != .loading }
                let second = scene.host.shown
                #expect(second.isTabs, "\(second)")
                #expect(scene.recorder.seen == [.loading, .main], "\(scene.recorder.seen)")
                #expect(!app.journal.entries.contains { $0.hasPrefix("settings.load") }, "onboarding's store ran")
            }
        }

        @Test(
            "A database that cannot open shows its own screen whatever the gate says, and an idle app the ground",
            arguments: [false, true]
        )
        func unavailableAndIdle_winOverTheGate(toldThereIsAProgram: Bool) async throws {
            let app = GateApp("winOverTheGate\(toldThereIsAProgram)")
            defer { app.remove() }
            let gate = try await GateAnswers.told(toldThereIsAProgram ? GatePrograms.make() : nil)
            #expect(gate.destination == (toldThereIsAProgram ? .main : .onboarding))
            let idle = app.composition()
            try FileManager.default.createDirectory(at: app.databaseURL, withIntermediateDirectories: true)
            let unavailable = app.composition()
            unavailable.boot()
            #expect(unavailable.state == .databaseUnavailable)
            await withGateDependencies(unavailable, app.journal) {
                let host = GateHost(AppRoot(composition: unavailable, gate: gate))
                let shown = host.shown
                host.close()
                #expect(shown.isUnavailable, "\(shown)")
                let idleHost = GateHost(AppRoot(composition: idle, gate: gate))
                let idleShown = idleHost.shown
                idleHost.close()
                #expect(idleShown.isGround, "\(idleShown)")
            }
        }

        @Test("A database that could not open, then opens on the next foreground, goes from its screen to the ground")
        func unavailable_thenOpens_showsTheGroundNext() async throws {
            let app = GateApp()
            defer { app.remove() }
            try FileManager.default.createDirectory(at: app.databaseURL, withIntermediateDirectories: true)
            let composition = app.composition()
            composition.boot()
            let gate = RootGate()
            let recorder = GateDestinationRecorder(gate)
            let host = GateHost(AppRoot(composition: composition, gate: gate), phase: .inactive)
            #expect(host.shown.isUnavailable)
            await composition.resume(in: .inactive) // the launch's first pass has been made: the next may retry
            try FileManager.default.removeItem(at: app.databaseURL)
            host.scene.phase = .active // the lifter comes back: the launch opens the database (decision #29)
            host.settle()
            await gateObserved { composition.state == .ready }
            // The database has just opened and the pass is running: neither the tabs nor onboarding yet.
            let shown = host.shown
            host.close()
            #expect(shown.isGround, "\(shown)")
            #expect(recorder.seen == [.loading], "\(recorder.seen)")
            await composition.resume(in: .active) // let the launch's steps end before the file is removed
        }
    }
#endif
