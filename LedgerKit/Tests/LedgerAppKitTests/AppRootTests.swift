#if os(iOS)
    import Foundation
    @testable import LedgerAppKit
    import LedgerDesign
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// What the root draws for each thing its gate says (F08 S3), on a composition whose database is open: the
    /// ground colour alone until the gate has its answer, onboarding while there is no active program, and the
    /// tabs while there is one. Hosted in a window on the simulator, as the shell's own tests are.
    ///
    /// A root that makes its own gate is read before any awaited read can have returned, so what it shows is
    /// the first frame of a launch. The other states are read from a root handed a gate that has followed the
    /// composition to its answer (`Harness.gate(following:)`), as the root's own task does.
    @Suite("AppRoot", .timeLimit(.minutes(1)))
    struct AppRootTests {
        static let size = CGSize(width: SnapshotConfig.phoneWidth, height: 874)

        /// What the pinned part of onboarding reads as on step 1; its page scrolls, so the hosted reader is told
        /// to read around the scroll view (testing-strategy §2.6: the pinned parts of a real root).
        static let onboarding = ["Continue", "Skip setup"]

        static func pixels(_ view: some View, _ scheme: ColorScheme) -> PixelBuffer? {
            RenderedImage.render(view, width: size.width, height: size.height, colorScheme: scheme)
                .flatMap(PixelBuffer.init)
        }

        /// The labels VoiceOver finds in a root handed `gate`, outside any scroll view, with the keys bound to
        /// the composition's stores as the app binds them: onboarding's store reads them when it is made.
        static func labels(of composition: AppComposition, _ gate: RootGate) -> [String] {
            withTestDependencies { composition.bind(&$0) } operation: {
                AppRoot(composition: composition, gate: gate)
                    .accessibilityElements(outsideScrollViews: true)
                    .map(\.label)
            }
        }

        /// A composition whose launch's pass has run, on a database with the default program or with none.
        static func launched(_ harness: Harness, hasProgram: Bool) async throws -> AppComposition {
            if hasProgram {
                return try await harness.bootedWithAProgram().composition
            }
            let composition = harness.booted()
            await composition.resume(in: .active)
            return composition
        }

        @Test(
            "Criteria 1 and 2: the first frame is the ground colour and nothing to read, with a program or without",
            arguments: [false, true], [ColorScheme.light, .dark]
        )
        func firstFrame_isTheGroundAlone(hasProgram: Bool, scheme: ColorScheme) async throws {
            let harness = Harness("firstFrame\(hasProgram)\(scheme)")
            defer { harness.remove() }
            let composition = try await Self.launched(harness, hasProgram: hasProgram)
            #expect(composition.state == .ready)

            // Read first, drawn second. `ImageRenderer` traps on the tab shell and on a scroll view, which is
            // what a root that showed a screen too early would hand it: the reader fails the test instead.
            let stops = AppRoot(composition: composition).accessibilityElements(SnapshotAppearance(scheme, .large))
            try #require(stops.isEmpty, "no tab, no title, no button before the gate's answer")

            let root = try #require(Self.pixels(AppRoot(composition: composition), scheme))
            let ground = try #require(Self.pixels(LedgerColor.ground.ignoresSafeArea(), scheme))
            let unavailable = try #require(Self.pixels(DatabaseUnavailableView(), scheme))
            // Compared outside `#expect`, which would write every pixel of both buffers into the result.
            let isTheGround = root == ground
            let controlDiffers = unavailable != ground
            #expect(isTheGround)
            #expect(controlDiffers, "control: a screen that draws anything is not the ground")
        }

        @Test("Criterion 1: with no active program the root shows onboarding on step 1, and nothing of the tabs")
        func noProgram_showsOnboarding_neverTheShell() async throws {
            let harness = Harness()
            defer { harness.remove() }
            let composition = try await Self.launched(harness, hasProgram: false)
            let gate = await harness.gate(following: composition)
            #expect(gate.destination == .onboarding)
            #expect(Self.labels(of: composition, gate) == Self.onboarding)
        }

        @Test("Criteria 2 and 4: a program shows Today; deleted, the root shows onboarding; saved again, Today")
        func program_showsTheTabs_andTheRootFollowsTheGate() async throws {
            let harness = Harness()
            defer { harness.remove() }
            let (composition, gate) = try await harness.bootedWithAProgram()
            let programs = try #require(composition.stores).programs
            #expect(Self.labels(of: composition, gate) == ["Today"])

            let follow = Task { await gate.follow(composition, in: .active) }
            defer { follow.cancel() }
            try await programs.delete(Fixtures.defaultProgramID)
            #expect(await gate.change(from: .main) == .onboarding)
            #expect(Self.labels(of: composition, gate) == Self.onboarding)

            try await programs.save(Fixtures.defaultProgram())
            #expect(await gate.change(from: .onboarding) == .main)
            #expect(Self.labels(of: composition, gate) == ["Today"])
        }
    }
#endif
