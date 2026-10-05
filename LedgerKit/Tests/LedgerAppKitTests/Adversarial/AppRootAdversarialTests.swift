import Foundation
@testable import LedgerAppKit
import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

/// F09 S1 adversarial round 1, criterion 6: the database-unavailable and idle states of the root are what they were
/// on `main` (a526874), apart from criterion 4's sentence. The screen `main` drew is rebuilt here from
/// `git show a526874:…/AppRoot.swift`, its two strings as literals (the second sentence as criterion 4 was revised
/// after round 1), and compared pixel for pixel with what the root draws now.
@Suite("Adversarial F09 S1 · the root's other states", .timeLimit(.minutes(1)))
struct AppRootAdversarialTests {
    static let size = CGSize(width: SnapshotConfig.phoneWidth, height: 874)

    /// `DatabaseUnavailableView.body` on `main`.
    static var unavailableOnMain: some View {
        EmptyState(
            "Can't open your data right now",
            body: "Your workouts are still on this iPhone. The app tries again when you come back to it."
        )
        .padding(.horizontal, LedgerSpacing.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LedgerColor.ground)
    }

    static func pixels(_ view: some View, _ appearance: SnapshotAppearance) -> PixelBuffer? {
        RenderedImage.render(
            view,
            width: size.width,
            height: size.height,
            colorScheme: appearance.colorScheme,
            dynamicTypeSize: appearance.dynamicTypeSize
        )
        .flatMap(PixelBuffer.init)
    }

    @Test(
        "Database unavailable is drawn as main draws it, pixel for pixel",
        arguments: SnapshotAppearance.phoneMatrix + [SnapshotAppearance(.dark, .accessibility5)]
    )
    func databaseUnavailable_isDrawnAsMainDrawsIt(_ appearance: SnapshotAppearance) throws {
        let now = try #require(Self.pixels(DatabaseUnavailableView(), appearance))
        let onMain = try #require(Self.pixels(Self.unavailableOnMain, appearance))
        let ground = try #require(Self.pixels(LedgerColor.ground, appearance))
        #expect(now == onMain)
        #expect(now != ground, "control: the screen draws its text")
    }

    @Test("The root of a composition whose database did not open draws that screen, and nothing of the tabs")
    func root_databaseUnavailable_drawsThatScreen() async throws {
        let harness = Harness()
        defer { harness.remove() }
        try FileManager.default.createDirectory(at: harness.databaseURL, withIntermediateDirectories: true)
        let composition = harness.booted()
        await composition.resume(in: .active)
        #expect(composition.state == .databaseUnavailable)
        let appearance = SnapshotAppearance(.dark, .large)
        let root = try #require(Self.pixels(AppRoot(composition: composition), appearance))
        let onMain = try #require(Self.pixels(Self.unavailableOnMain, appearance))
        #expect(root == onMain)
    }

    @Test("The root of a composition that has not booted draws the ground alone", arguments: [ColorScheme.light, .dark])
    func root_idle_drawsTheGroundAlone(_ scheme: ColorScheme) throws {
        let harness = Harness("idle\(scheme)")
        defer { harness.remove() }
        let composition = harness.composition()
        #expect(composition.state == .idle)
        let appearance = SnapshotAppearance(scheme, .large)
        let root = try #require(Self.pixels(AppRoot(composition: composition), appearance))
        let ground = try #require(Self.pixels(LedgerColor.ground.ignoresSafeArea(), appearance))
        #expect(root == ground)
        #expect(composition.state == .idle, "drawing the root opens nothing")
    }

    @Test("The root of a composition whose database is open draws without trapping, here and on the simulator")
    func root_ready_draws() async throws {
        let harness = Harness()
        defer { harness.remove() }
        let (composition, gate) = try await harness.bootedWithAProgram()
        #expect(composition.state == .ready)
        #expect(renderPreview(size: Self.size) { AppRoot(composition: composition, gate: gate) })
    }

    #if os(iOS)
        @Test("Database unavailable reads to VoiceOver as main's does: the title, a header, then the body")
        func databaseUnavailable_readsAsMainsDoes() {
            let elements = DatabaseUnavailableView().accessibilityElements()
            let title = "Can't open your data right now"
            let body = "Your workouts are still on this iPhone. The app tries again when you come back to it."
            #expect(elements.map(\.label) == [title, body])
            #expect(elements.first?.traits.contains(.header) == true)
            #expect(elements == Self.unavailableOnMain.accessibilityElements())
        }

        @Test("An idle root has nothing for VoiceOver, and a ready root shows the shell on Today")
        func root_idleAndReady_readToVoiceOver() async throws {
            let harness = Harness()
            defer { harness.remove() }
            #expect(AppRoot(composition: harness.composition()).accessibilityElements().isEmpty)
            let (composition, gate) = try await harness.bootedWithAProgram()
            let elements = AppRoot(composition: composition, gate: gate).accessibilityElements()
            #expect(elements.map(\.label) == ["Today"])
            #expect(elements.first?.traits.contains(.header) == true)
        }
    #endif
}
