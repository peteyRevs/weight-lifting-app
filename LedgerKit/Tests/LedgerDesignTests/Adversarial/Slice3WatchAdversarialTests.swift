#if os(watchOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// Rendering and pixel helpers for the slice-3 watch suites.
    enum WatchProbe {
        /// Series 12 42 mm, Series 12 46 mm, Ultra 1–2 and Ultra 3–4 49 mm, in points (the simulators'
        /// device profiles: 374 × 446, 416 × 496, 410 × 502 and 422 × 514 px at 2×).
        nonisolated static let screens: [CGSize] = [
            CGSize(width: 187, height: 223), CGSize(width: 208, height: 248),
            CGSize(width: 205, height: 251), CGSize(width: 211, height: 257)
        ]
        /// HIG, Typography, watchOS Dynamic Type sizes: xSmall … xxxLarge, AX1 … AX3.
        nonisolated static let textSizes: [DynamicTypeSize] = [
            .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
            .accessibility1, .accessibility2, .accessibility3
        ]
        static let inset = Int(LedgerSpacing.m)

        static func render(
            _ view: some View,
            width: CGFloat? = nil,
            size: DynamicTypeSize = .xLarge,
            bold: Bool = false,
            scale: CGFloat = 1
        ) throws -> PixelBuffer {
            let content = view.environment(\.legibilityWeight, bold ? .bold : .regular)
            let image = try #require(Probe.image(content.frame(width: width), scale: scale, dynamicTypeSize: size))
            return try #require(PixelBuffer(image))
        }

        /// Rows (or columns) where some pixel satisfies `isInk`, as runs.
        static func runs(
            _ buffer: PixelBuffer,
            columns: Bool = false,
            _ isInk: (Pixel) -> Bool
        ) -> [ClosedRange<Int>] {
            let (outer, inner) = columns ? (buffer.width, buffer.height) : (buffer.height, buffer.width)
            var runs: [ClosedRange<Int>] = []
            for index in 0 ..< outer {
                let inked = (0 ..< inner).contains { other in
                    isInk(columns ? buffer.pixel(column: index, row: other) : buffer.pixel(
                        column: other,
                        row: index
                    ))
                }
                guard inked else { continue }
                if let last = runs.last, last.upperBound == index - 1 {
                    runs[runs.count - 1] = last.lowerBound ... index
                } else {
                    runs.append(index ... index)
                }
            }
            return runs
        }

        static func notBlack(_ pixel: Pixel) -> Bool {
            pixel.differs(from: Pixel(hex: 0x000000), by: 24)
        }

        static func orange(_ pixel: Pixel) -> Bool {
            pixel.red > 200 && pixel.green < 140 && pixel.blue < 90
        }

        // MARK: The 11 pt floor, on rendered glyphs

        /// The height in pixels of the first run of rows with a grey or white pixel brighter than
        /// `level` in every channel: half the brightness of the text being measured.
        static func textHeight(_ buffer: PixelBuffer, above level: UInt8 = 127) -> Int {
            runs(buffer) { $0.red > level && $0.green > level && $0.blue > level }.first?.count ?? 0
        }

        /// `text` in Archivo at 11 pt at the given axes, on black, at 3×: the smallest a watch label
        /// may be (F06 criterion 4), built from the font file rather than from `LedgerFont`.
        static func floorHeight(
            _ text: String, weight: CGFloat, width: CGFloat, tabular: Bool, color: Color = .white,
            above level: UInt8 = 127
        ) throws -> Int {
            let font = try #require(ArchivoFile.swiftUIFont(
                size: 11,
                weight: weight,
                width: width,
                tabular: tabular
            ))
            let view = Text(verbatim: text).font(font).foregroundStyle(color).padding(8).background(Color.black)
            return try textHeight(render(view, scale: 3), above: level)
        }

        static func ring(_ progress: Double) throws -> PixelBuffer {
            try render(WatchRestRing(progress: progress, label: "1:15").background(LedgerColor.watchGround))
        }
    }

    extension RenderingSuites {
        /// F06 slice 3, adversarial round 1, on the watch simulator: criterion 4 at every watch text size
        /// (xSmall to AX3) with and without Bold Text, at 42, 46 and both 49 mm screens; the button's
        /// height; the ring's edges.
        @Suite("Slice 3 watch layout (adversarial, slice 3 round 1)", .tags(.design))
        struct Slice3WatchLayoutAdversarialTests {
            @Test(
                "Every watch gallery keeps its 12 pt inset at every watch text size, with and without Bold Text",
                arguments: WatchProbe.screens
            )
            func watchGalleries_everyTextSize_keepTheirInset(_ screen: CGSize) throws {
                let galleries: [(String, AnyView)] = [
                    ("WatchPrimaryButton", AnyView(WatchPrimaryButtonGallery())),
                    ("WatchRestRing", AnyView(WatchRestRingGallery())),
                    ("WatchStatBlock", AnyView(WatchStatBlockGallery()))
                ]
                for (name, gallery) in galleries {
                    for size in WatchProbe.textSizes {
                        for bold in [false, true] {
                            let pixels = try WatchProbe.render(
                                gallery.ledgerWatchPage(),
                                width: screen.width,
                                size: size,
                                bold: bold
                            )
                            let rows = WatchProbe.runs(pixels, WatchProbe.notBlack)
                            let columns = WatchProbe.runs(pixels, columns: true, WatchProbe.notBlack)
                            let cell = "\(name), \(Int(screen.width)) pt, \(size)\(bold ? ", Bold Text" : "")"
                            #expect(pixels.width == Int(screen.width), "\(cell): \(pixels.width) px wide")
                            #expect(
                                (columns.first?.lowerBound ?? 0) >= WatchProbe.inset - 1,
                                "\(cell): columns \(columns)"
                            )
                            #expect(
                                (columns.last?.upperBound ?? 0) <= pixels.width - WatchProbe.inset,
                                "\(cell): columns \(columns)"
                            )
                            #expect((rows.first?.lowerBound ?? 0) >= WatchProbe.inset - 1, "\(cell): rows \(rows)")
                            #expect(
                                (rows.last?.upperBound ?? 0) <= pixels.height - WatchProbe.inset,
                                "\(cell): rows \(rows)"
                            )
                        }
                    }
                }
            }

            @Test(
                "At the largest watch text the rest ring fits inside the inset of every 42–49 mm screen",
                arguments: WatchProbe.screens
            )
            func watchRestRing_largestText_fitsEveryScreen(_ screen: CGSize) throws {
                for bold in [false, true] {
                    let ring = try WatchProbe.render(
                        WatchRestRing(progress: 1, label: "10:00"),
                        size: .accessibility3,
                        bold: bold
                    )
                    #expect(CGFloat(ring.width) <= screen.width - 2 * LedgerSpacing.m, "\(screen): \(ring.width) pt")
                    #expect(CGFloat(ring.height) <= screen.height - 2 * LedgerSpacing.m, "\(screen): \(ring.height) pt")
                }
            }

            @Test("WatchPrimaryButton's pill is at least 44 pt tall and full width at every text size, enabled or not")
            func watchPrimaryButton_pill_meetsTheWatchDefault() throws {
                for size in WatchProbe.textSizes {
                    for enabled in [true, false] {
                        let button = WatchPrimaryButton("Go") {}.disabled(!enabled).ledgerWatchPage()
                        let pixels = try WatchProbe.render(button, width: 187, size: size)
                        let rows = WatchProbe.runs(pixels, WatchProbe.notBlack)
                        let columns = WatchProbe.runs(pixels, columns: true, WatchProbe.notBlack)
                        #expect(
                            rows.count == 1 && (rows.first?.count ?? 0) >= 44,
                            "\(size), enabled \(enabled): rows \(rows)"
                        )
                        let width = columns.count == 1 ? columns[0].count : 0
                        #expect(
                            abs(width - (187 - 2 * WatchProbe.inset)) <= 2,
                            "\(size), enabled \(enabled): \(columns)"
                        )
                    }
                }
            }

            @Test("WatchRestRing: out of range and non-finite progress draw as the nearest end, never a partial arc")
            func watchRestRing_outOfRange_drawsAsTheNearestEnd() throws {
                let full = try WatchProbe.ring(1)
                let empty = try WatchProbe.ring(0)
                #expect(full != empty)
                for progress in [1.5, 1e300, .greatestFiniteMagnitude, .infinity] {
                    #expect(try WatchProbe.ring(progress) == full, "\(progress) should draw the full ring")
                }
                for progress in [-0.5, -1e300, -.infinity, .nan, -Double.nan, -0.0, .signalingNaN] {
                    #expect(try WatchProbe.ring(progress) == empty, "\(progress) should draw no arc")
                }
                #expect(!empty.pixels.contains(where: WatchProbe.orange), "an empty ring has no orange")
                let half = try WatchProbe.ring(0.5)
                let orangeColumns = WatchProbe.runs(half, columns: true, WatchProbe.orange)
                let centre = half.width / 2
                let cap = Int((RestRingGeometry.watch.lineWidth / 2).rounded(.up)) + 1
                #expect(
                    (orangeColumns.first?.lowerBound ?? 0) >= centre - cap,
                    "half a ring is the right half (12 to 6 clockwise): orange columns \(orangeColumns)"
                )
            }
        }

        /// F06 criterion 4's 11 pt floor, measured on rendered glyphs rather than on `scaledSize`: a
        /// component that shrinks its text must stop at the floor.
        @Suite("Slice 3 watch type floor (adversarial, slice 3 round 1)", .tags(.design))
        struct Slice3WatchTypeFloorAdversarialTests {
            /// Too long for any screen: each view must shrink its text to the 11 pt floor and no further.
            @Test("A value or countdown too long to fit shrinks to 11 pt and no smaller, at every text size")
            func shrunkText_everyTextSize_neverBelowElevenPoints() throws {
                let digits = String(repeating: "8", count: 40)
                let value = try WatchProbe.floorHeight("8", weight: 700, width: 92, tabular: true)
                for size in WatchProbe.textSizes {
                    let stat = WatchStatBlock(digits, caption: "Sets").padding(8).background(Color.black)
                    let ring = WatchRestRing(progress: 0, label: digits).padding(8).background(Color.black)
                    for (name, view) in [
                        ("WatchStatBlock value", AnyView(stat)),
                        ("WatchRestRing label", AnyView(ring))
                    ] {
                        let height = try WatchProbe.textHeight(WatchProbe.render(
                            view,
                            width: 187,
                            size: size,
                            scale: 3
                        ))
                        #expect(height >= value - 1, "\(name), \(size): \(height) px at 3×, 11 pt is \(value) px")
                    }
                }
            }

            @Test("Captions and button titles are never drawn under 11 pt, at every text size")
            func labels_everyTextSize_neverBelowElevenPoints() throws {
                let muted = LedgerColor.watchInkMuted // 46 % white: 117 of 255
                let caption = try WatchProbe.floorHeight(
                    "SETS",
                    weight: 600,
                    width: 100,
                    tabular: false,
                    color: muted,
                    above: 58
                )
                let title = try WatchProbe.floorHeight("88", weight: 700, width: 100, tabular: false)
                for size in WatchProbe.textSizes {
                    let block = WatchStatBlock("", caption: "Sets").padding(8).background(Color.black)
                    let captionHeight = try WatchProbe.textHeight(
                        WatchProbe.render(block, width: 187, size: size, scale: 3),
                        above: 58
                    )
                    #expect(
                        captionHeight >= caption - 1,
                        "caption, \(size): \(captionHeight) px, 11 pt is \(caption) px"
                    )
                    let button = WatchPrimaryButton("88") {}.padding(8).background(Color.black)
                    let titleHeight = try WatchProbe.textHeight(WatchProbe.render(
                        button,
                        width: 187,
                        size: size,
                        scale: 3
                    ))
                    #expect(titleHeight >= title - 1, "button title, \(size): \(titleHeight) px, 11 pt is \(title) px")
                }
            }
        }
    }
#endif
