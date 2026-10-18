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

        /// What the tabs on Today read as outside any scroll view: nothing. Today's title is on its page, inside
        /// its scroll view, since F09 S5 (port of F08 S2/S3; it was "Today" on the S3 branch). What tells the
        /// tabs from the ground is the page's scroll view (`AppRootAdversarialTests.pageScrollViews`).
        static let today: [String] = []

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
            "Criteria 12 and 13: the first frame is the ground colour and nothing to read, with a program or without",
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

        @Test("Criterion 12: with no active program the root shows onboarding on step 1, and nothing of the tabs")
        func noProgram_showsOnboarding_neverTheShell() async throws {
            let harness = Harness()
            defer { harness.remove() }
            let composition = try await Self.launched(harness, hasProgram: false)
            let gate = await harness.gate(following: composition)
            #expect(gate.destination == .onboarding)
            #expect(Self.labels(of: composition, gate) == Self.onboarding)
        }

        /// The page scroll views of a root handed `gate`, with the keys bound as `labels(of:_:)` binds them.
        static func pages(of composition: AppComposition, _ gate: RootGate) -> Int {
            withTestDependencies { composition.bind(&$0) } operation: {
                AppRootAdversarialTests.pageScrollViews(in: AppRoot(composition: composition, gate: gate))
            }
        }

        @Test("Criteria 13 and 15: a program shows Today; deleted, the root shows onboarding; saved again, Today")
        func program_showsTheTabs_andTheRootFollowsTheGate() async throws {
            let harness = Harness()
            defer { harness.remove() }
            let (composition, gate) = try await harness.bootedWithAProgram()
            let programs = try #require(composition.stores).programs
            #expect(Self.labels(of: composition, gate) == Self.today)
            #expect(Self.pages(of: composition, gate) == 1, "Today's page, not the ground")

            let follow = Task { await gate.follow(composition, in: .active) }
            defer { follow.cancel() }
            try await programs.delete(Fixtures.defaultProgramID)
            #expect(await gate.change(from: .main) == .onboarding)
            #expect(Self.labels(of: composition, gate) == Self.onboarding)

            try await programs.save(Fixtures.defaultProgram())
            #expect(await gate.change(from: .onboarding) == .main)
            #expect(Self.labels(of: composition, gate) == Self.today)
            #expect(Self.pages(of: composition, gate) == 1)
        }

        /// The routers a `MainRoot` made to start the shell over with, oldest first.
        final class Made {
            var routers: [AppRouter] = []
        }

        /// The labels VoiceOver finds in `MainRoot` handed `gate` and `router`, read as `labels(of:_:)` reads;
        /// each router it starts over with goes to `made`.
        static func labels(
            of composition: AppComposition,
            _ gate: RootGate,
            _ router: AppRouter,
            made: Made
        ) -> [String] {
            withTestDependencies { composition.bind(&$0) } operation: {
                MainRoot(composition: composition, gate: gate, router: router) {
                    let next = AppRouter()
                    made.routers.append(next)
                    return next
                }
                .accessibilityElements(outsideScrollViews: true)
                .map(\.label)
            }
        }

        /// Ruling R4 (port of F08 S2/S3; F8-S3-1 on the S3 branch): when onboarding appears the shell starts over
        /// with a new router, so the tabs reached after it open on Today with every stack empty, the second time
        /// as the first, whatever the old router held. `MainRoot` owns the router, so this root is hosted from
        /// `MainRoot`, handed the router the test pushes through and keeping the ones it makes; the path from
        /// `AppRoot` to it is the other tests'.
        @Test("Criterion 14: a screen pushed when the program goes away is gone after a second onboarding")
        func pushedScreen_isGoneAfterASecondOnboarding() async throws {
            let harness = Harness()
            defer { harness.remove() }
            let (composition, gate) = try await harness.bootedWithAProgram()
            let programs = try #require(composition.stores).programs
            let made = Made()
            let first = AppRouter()
            first.open(.settings, in: .today)
            first.open(.settings, in: .library)
            #expect(Self.labels(of: composition, gate, first, made: made) == ["Settings"], "control: pushed")
            #expect(made.routers.isEmpty, "control: the shell does not start over while it shows the tabs")

            let follow = Task { await gate.follow(composition, in: .active) }
            defer { follow.cancel() }
            try await programs.delete(Fixtures.defaultProgramID)
            #expect(await gate.change(from: .main) == .onboarding)
            #expect(Self.labels(of: composition, gate, first, made: made) == Self.onboarding)
            let next = try #require(made.routers.last, "onboarding appeared and the shell did not start over")
            #expect(next.selectedTab == .today)
            #expect(AppTab.allCases.allSatisfy { next[path: $0].isEmpty }, "nothing is pushed on any tab")
            #expect(first[path: .library] == [.settings], "a new router, not the old one emptied")

            try await programs.save(Fixtures.defaultProgram())
            #expect(await gate.change(from: .onboarding) == .main)
            #expect(Self.labels(of: composition, gate, next, made: made) == Self.today, "Today, with nothing pushed")
        }
    }
#endif
