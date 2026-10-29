#if os(iOS) && DEBUG
    @testable import FeatureSettings
    import Foundation
    import LedgerDesign
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import Observation
    import SwiftUI
    import Testing
    import UIKit

    /// F14 S1b, G2: the root, attacked. The title does not move from the loading frame to the loaded page; an
    /// unreadable row; a failed save on screen and to VoiceOver; the switches tapped five times while every save is
    /// held.
    @MainActor
    @Suite("SettingsRoot, adversarial", .serialized, .tags(.feature), .timeLimit(.minutes(1)))
    struct SettingsRootAdversarialTests {
        nonisolated static let sizes: [DynamicTypeSize] = [
            .xSmall, .large, .xxxLarge, .accessibility3, .accessibility5
        ]

        // MARK: The root

        /// Hosts `view` in a window of the phone's size for as long as `body` runs (as `SettingsRootTests` does).
        static func hosting(_ view: some View, _ body: (UIView) async throws -> Void) async rethrows {
            let host = UIHostingController(rootView: view)
            let window = SceneLessWindow.make(frame: CGRect(x: 0, y: 0, width: SnapshotConfig.phoneWidth, height: 874))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            try await body(host.view)
        }

        @Test(
            "N8. The loading title stands where the page's title will, at every size: the screen does not jump",
            arguments: sizes
        )
        func loadingTitle_standsWhereThePagesWill(_ size: DynamicTypeSize) throws {
            let appearance = SnapshotAppearance(.light, size)
            // Both in one stack, from its top-leading corner, so the hosted reader places them alike: the root before
            // the settings are read, and the page it draws once they are.
            let stops = ZStack(alignment: .topLeading) {
                SettingsRoot(store: SettingsScene().store) { _ in }
                SettingsParts(preview: .pounds)
            }
            .placedStops(appearance)
            let titles = stops.filter { $0.stop.label == "Settings" }
            try #require(titles.count == 2, "\(titles.count) titles")
            let (before, after) = (titles[0], titles[1])
            #expect(before.stop == .heading("Settings") && after.stop == .heading("Settings"))
            let (early, late) = (before.frame, after.frame)
            let same = abs(early.minX - late.minX) < 0.5 && abs(early.minY - late.minY) < 0.5
                && abs(early.height - late.height) < 0.5
            #expect(same, "\(size): loading \(before.frame), loaded \(after.frame)")
        }

        @Test("N2. An unreadable row: the root leaves the loading title for the defaults, and a change saves over it")
        func unreadableRow_drawsTheDefaults_andAChangeSaves() async throws {
            let scene = SettingsScene(unreadable: true)
            try await Self.hosting(SettingsRoot(store: scene.store) { _ in }) { _ in
                await eventually { scene.store.model != nil }
                let model = try scene.model
                #expect(model.units.options.first { $0.isSelected }?.action == .setUnits(Settings.default.units))
                #expect(model.problem == nil, "an unreadable row is not a failed save")
                let other: Units = Settings.default.units == .kg ? .lb : .kg
                scene.store.send(.setUnits(other))
                await eventually { scene.store.pending == nil }
                #expect(try await scene.stored().units == other)
                #expect(try scene.model.problem == nil)
            }
        }

        @Test("N1. A failed save, through the root: the switch goes back, and the line is VoiceOver's second stop")
        func failedSave_showsTheLine() async throws {
            let scene = SettingsScene(failures: 1)
            try await Self.hosting(SettingsRoot(store: scene.store) { _ in }) { _ in
                await eventually { scene.store.model != nil }
                let before = try scene.model.switches[0].isOn
                try scene.store.send(scene.model.switches[0].action)
                await eventually { scene.store.model?.problem != nil }
                let model = try scene.model
                #expect(model.switches[0].isOn == before, "the switch went back")
                let stops = SettingsPage(model: model, send: { _ in }).stops()
                #expect(Array(stops.prefix(2)) == [.heading("Settings"), .text("Couldn't save that change.")])
            }
        }

        /// F14-S1b-2. N1 says a failed save shows "Couldn't save that change." and puts the control back. A
        /// VoiceOver user who double-taps a switch hears it turn on; the line then appears at the top of the page,
        /// away from the focus, and the switch turns back, and nothing is said. The app's other screens announce
        /// such a line when it appears (`ProgramRoot` its notice, `CreateExerciseSheet` each problem, through an
        /// injectable `announce`); `SettingsRoot` has no `announce` and posts no announcement, so this test can only
        /// read the sources.
        @Test("F14-S1b-2. The failed save's line is announced to VoiceOver when it appears")
        func failedSave_isAnnounced() throws {
            let sources = try CopyAudit.sources(ofModule: "FeatureSettings")
            try #require(sources.count >= 10)
            let announces = sources.values.contains { text in
                text.contains("AccessibilityNotification.Announcement") || text.contains("announce(")
            }
            withKnownIssue("F14-S1b-2: SettingsRoot never announces \"Couldn't save that change.\"") {
                #expect(announces, "FeatureSettings posts an announcement")
            }
        }

        @Test("N1. Each switch double-tapped five times while every save is held: odd taps flip it, one save at a time")
        func switches_tappedFiveTimes_whileSavesAreHeld() async throws {
            let scene = SettingsScene(holdsSaves: true)
            let run = await scene.running()
            defer { run.cancel() }
            let before = try #require(scene.store.shown)
            let titles = try scene.model.switches.map(\.title)
            let values: [String] = LiveSettingsPage(store: scene.store).withLiveAccessibilityElements { read in
                for title in titles {
                    for _ in 0 ..< 5 {
                        _ = read().first { $0.accessibilityLabel == title }?.accessibilityActivate()
                    }
                }
                return titles
                    .map { title in read().first { $0.accessibilityLabel == title }?.accessibilityValue ?? "-" }
            }
            let expected = [!before.plateMathEnabled, !before.autoRest, !before.watchBuzz]
            #expect(values == expected.map { $0 ? "1" : "0" }, "VoiceOver reads each switch flipped")
            let shown = try #require(scene.store.shown)
            #expect([shown.plateMathEnabled, shown.autoRest, shown.watchBuzz] == expected)
            await scene.untilASaveIsHeld()
            scene.watched.releaseSaves()
            await eventually { scene.store.pending == nil }
            let stored = try await scene.stored()
            #expect([stored.plateMathEnabled, stored.autoRest, stored.watchBuzz] == expected)
            #expect(scene.watched.mostAtOnce == 1)
            #expect(scene.watched.saves.count <= 2, "the taps folded into the held save and one after it")
        }
    }
#endif
