#if os(iOS)
    @testable import FeatureOnboarding
    import Foundation
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// F08 S2 close-out (round 2): "a disabled 'Back' looks disabled and sits flush" (`PillButton`'s disabled ink
    /// and its `flush` edge, new in `LedgerDesign`), seen where onboarding uses it. The page and the pinned part
    /// are drawn at 1× and read as bands of inked rows: "Back", the bars, then the title's lines, and last of
    /// all "Skip setup".
    @Suite("Adversarial F08 S2 close-out · the pills as onboarding draws them")
    struct OnboardingPillAdversarialTests {
        /// A run of rows that hold ink: the columns it spans and how far its strongest pixel is from the ground.
        struct Band: CustomStringConvertible {
            var rows: ClosedRange<Int>
            var columns: ClosedRange<Int>
            var strength: Int

            var description: String {
                "rows \(rows) columns \(columns) strength \(strength)"
            }
        }

        nonisolated static let width = 402
        nonisolated static let themes: [ColorScheme] = [.light, .dark]

        static func drawn(
            _ state: OnboardingState,
            _ scheme: ColorScheme,
            _ size: DynamicTypeSize = .large
        ) throws -> PixelBuffer {
            let image = RenderedImage.render(
                AdversarialParts(state), width: CGFloat(width), colorScheme: scheme, dynamicTypeSize: size
            )
            return try #require(image.flatMap(PixelBuffer.init))
        }

        /// How far `pixel` is from `ground`, in its most different colour channel.
        static func distance(_ pixel: Pixel, _ ground: Pixel) -> Int {
            max(
                abs(Int(pixel.red) - Int(ground.red)),
                abs(Int(pixel.green) - Int(ground.green)),
                abs(Int(pixel.blue) - Int(ground.blue))
            )
        }

        /// The picture's inked rows, grouped where they touch, top to bottom. Ink is anything more than 20 from
        /// the ground (the pixel in the top left corner), which leaves the hairlines out.
        static func bands(_ buffer: PixelBuffer) -> [Band] {
            let ground = buffer.pixel(column: 0, row: 0)
            var bands: [Band] = []
            for row in 0 ..< buffer.height {
                let distances = (0 ..< buffer.width).map { distance(buffer.pixel(column: $0, row: row), ground) }
                guard let first = distances.firstIndex(where: { $0 > 20 }),
                      let last = distances.lastIndex(where: { $0 > 20 })
                else {
                    continue
                }
                let strength = distances.max() ?? 0
                if var open = bands.last, open.rows.upperBound == row - 1 {
                    open.rows = open.rows.lowerBound ... row
                    open.columns = min(open.columns.lowerBound, first) ... max(open.columns.upperBound, last)
                    open.strength = max(open.strength, strength)
                    bands[bands.count - 1] = open
                } else {
                    bands.append(Band(rows: row ... row, columns: first ... last, strength: strength))
                }
            }
            return bands
        }

        @Test("Back's word starts where the bars and the title start, enabled or locked, at two text sizes")
        func back_sitsFlushWithTheBarsAndTheTitle() throws {
            let states = [
                OnboardingState(step: .days), OnboardingState(step: .program, phase: .failed),
                OnboardingState(step: .program, phase: .saving)
            ]
            for state in states {
                for scheme in Self.themes {
                    // The hosted PR run keeps the default size alone (F08 S2/S3 port, criterion 25).
                    for size in TestSweep.sizes([.large, .accessibility3]) {
                        let bands = try Self.bands(Self.drawn(state, scheme, size))
                        let context: Comment = "\(state.step) \(state.phase) \(scheme) \(size): \(bands.prefix(3))"
                        try #require(bands.count >= 4, context)
                        let back = bands[0].columns.lowerBound
                        let bars = bands[1].columns.lowerBound
                        let title = bands[2].columns.lowerBound
                        #expect(bands[1].rows.count <= 3, "control: the second band is the 2 pt bars. \(context)")
                        #expect(bands[1].columns.upperBound - bars > Self.width / 2, context)
                        // A letter's own side bearing is a pixel or two, more at the title's size.
                        #expect(
                            (0 ... 2).contains(back - bars),
                            "Back starts \(back - bars) px from the bars. \(context)"
                        )
                        #expect(abs(title - back) <= 4, "Back starts \(back - title) px from the title. \(context)")
                    }
                }
            }
        }

        @Test("A locked Back and a locked Skip setup are fainter than the open ones, still drawn, and move nothing")
        func lockedPills_lookLockedAndStayPut() throws {
            for scheme in Self.themes {
                let open = try Self.bands(Self.drawn(OnboardingState(step: .days), scheme))
                let locked = try Self.bands(Self.drawn(OnboardingState(step: .days, phase: .saving), scheme))
                try #require(open.count == locked.count && open.count >= 4, "\(scheme): \(open.count), \(locked.count)")
                // The first band is "Back", the last "Skip setup".
                for index in [0, open.count - 1] {
                    let (was, isNow) = (open[index], locked[index])
                    #expect(isNow.strength < was.strength - 15, "\(scheme) band \(index): \(was) then \(isNow)")
                    #expect(isNow.strength > 30, "a locked pill is still drawn. \(scheme) band \(index): \(isNow)")
                    #expect(isNow.rows == was.rows, "\(scheme) band \(index)")
                    #expect(abs(isNow.columns.lowerBound - was.columns.lowerBound) <= 1, "\(scheme) band \(index)")
                    #expect(abs(isNow.columns.upperBound - was.columns.upperBound) <= 1, "\(scheme) band \(index)")
                }
            }
        }

        @Test("The failure locks Back's look as it locks Back: fainter than on the same step while picking")
        func failed_backLooksLocked() throws {
            for scheme in Self.themes {
                let picking = try Self.bands(Self.drawn(OnboardingState(step: .program), scheme))
                let failed = try Self.bands(Self.drawn(OnboardingState(step: .program, phase: .failed), scheme))
                let (was, isNow) = try (#require(picking.first), #require(failed.first))
                #expect(isNow.strength < was.strength - 15, "\(scheme): \(was) then \(isNow)")
                #expect(isNow.rows == was.rows && isNow.columns == was.columns, "\(scheme): \(was) then \(isNow)")
                // "Skip setup" stays open while the failure is shown: as strong as while picking.
                let (skipWas, skipIsNow) = try (#require(picking.last), #require(failed.last))
                #expect(abs(skipIsNow.strength - skipWas.strength) <= 2, "\(scheme): \(skipWas) then \(skipIsNow)")
            }
        }

        @Test("On step 1 the hidden Back leaves no ink: the first thing drawn is the bars")
        func stepOne_hiddenBack_drawsNothing() throws {
            for scheme in Self.themes {
                let bands = try Self.bands(Self.drawn(OnboardingState(), scheme))
                let first = try #require(bands.first)
                #expect(first.rows.count <= 3, "\(scheme): \(first)")
                #expect(first.columns.upperBound - first.columns.lowerBound > Self.width / 2, "\(scheme): \(first)")
                let second = try Self.bands(Self.drawn(OnboardingState(step: .days), scheme))
                #expect(
                    second.count == bands.count + 1 || second.count >= 4,
                    "control: step 2 draws Back above the bars"
                )
            }
        }
    }
#endif
