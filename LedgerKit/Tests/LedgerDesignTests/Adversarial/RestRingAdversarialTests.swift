import CoreGraphics
@testable import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

// F06 slice 2, adversarial round 1: `RestRing` against the v2 prototype's rest card
// (`design/prototype/Ledger v2.dc.html`): a 64 × 64 viewBox turned −90° by CSS, a track circle and an
// orange circle of r 29, stroke 2.5 with round caps, `stroke-dasharray` 182 and
// `stroke-dashoffset` = 182 − 182 × rest / max(1, restTotal). Expected values come from that markup,
// never from `RestRingGeometry`.

/// The prototype's ring, from its markup.
nonisolated enum PrototypeRing {
    static let viewBox: CGFloat = 64
    static let radius: CGFloat = 29
    static let strokeWidth: CGFloat = 2.5
    static let dashArray: CGFloat = 182

    /// The dash the browser shows: `dasharray − dashoffset`, within one dash.
    static func dashLength(progress: Double) -> CGFloat {
        let offset = dashArray - dashArray * CGFloat(progress)
        return min(max(dashArray - offset, 0), dashArray)
    }

    /// The point `length` units along the drawn circle, in a frame `side` points wide. SVG starts a
    /// `circle` at 3 o'clock and runs towards 6 o'clock (clockwise on screen, y down); `rotate(-90deg)`
    /// moves the start to 12 o'clock and keeps the direction.
    static func point(along length: CGFloat, side: CGFloat) -> CGPoint {
        let scale = side / viewBox
        let angle = length / radius
        return CGPoint(x: side / 2 + radius * scale * sin(angle), y: side / 2 - radius * scale * cos(angle))
    }
}

@Suite("RestRing geometry (adversarial, slice 2 round 1)", .tags(.design))
nonisolated struct RestRingGeometryAdversarialTests {
    static let frame = CGRect(x: 0, y: 0, width: 64, height: 64)

    static func points(_ path: Path) -> (start: CGPoint?, end: CGPoint?) {
        var elements: [Path.Element] = [] // Path is not a Sequence
        path.forEach { elements.append($0) }
        let start = elements.lazy.compactMap { element -> CGPoint? in
            if case let .move(point) = element {
                point
            } else {
                nil
            }
        }.first
        return (start, path.currentPoint)
    }

    @Test("For 500 seeded progress values the arc starts at 12 o'clock and ends where the prototype's dash ends")
    func seededProgress_arcEnd_matchesPrototypeDash() throws {
        var generator = SplitMix64(seed: 20_260_929)
        // The prototype's dash is 182 against a 182.21 circumference, so its end trails the true
        // fraction by up to 0.21 units of arc: 0.25 pt is the tolerance.
        for _ in 0 ..< 500 {
            let progress = Double.random(in: 0.000_1 ..< 1, using: &generator)
            let (start, end) = Self.points(RestRingGeometry.phone.arc(progress: progress, in: Self.frame))
            let expectedEnd = PrototypeRing.point(along: PrototypeRing.dashLength(progress: progress), side: 64)
            let actualStart = try #require(start, "progress \(progress): empty path")
            let actualEnd = try #require(end, "progress \(progress): empty path")
            #expect(hypot(actualStart.x - 32, actualStart.y - 3) < 0.01, "progress \(progress): start \(actualStart)")
            #expect(
                hypot(actualEnd.x - expectedEnd.x, actualEnd.y - expectedEnd.y) < 0.25,
                "progress \(progress): end \(actualEnd), prototype \(expectedEnd)"
            )
        }
    }

    @Test(
        "Progress too small to see draws at most a dot at 12 o'clock, never a full or reversed ring",
        arguments: [Double.leastNonzeroMagnitude, .leastNormalMagnitude, 1e-12, 1e-6]
    )
    func tinyProgress_arc_isADotAtTwelve(_ progress: Double) throws {
        let path = RestRingGeometry.phone.arc(progress: progress, in: Self.frame)
        let (start, end) = Self.points(path)
        let first = try #require(start)
        let last = try #require(end)
        #expect(hypot(first.x - 32, first.y - 3) < 0.01)
        #expect(hypot(last.x - first.x, last.y - first.y) < 0.01, "\(progress): ends at \(last)")
        #expect(path.boundingRect.width < 0.01, "\(progress): \(path.boundingRect)")
    }

    @Test(
        "Degenerate progress values: −0, signalling NaN and the largest finite value",
        arguments: [(-0.0, false), (Double.signalingNaN, false), (Double.greatestFiniteMagnitude, true)]
    )
    func degenerateProgress_arc_isEmptyOrFull(_ progress: Double, _ full: Bool) {
        let path = RestRingGeometry.phone.arc(progress: progress, in: Self.frame)
        #expect(path.isEmpty == !full, "\(progress)")
        if full {
            #expect(abs(path.boundingRect.width - 58) < 0.01 && abs(path.boundingRect.height - 58) < 0.01)
        }
    }

    @Test("Just under 1 the ring is open by a hair and ends just before 12 o'clock, not past it")
    func justUnderOne_arc_endsBeforeTwelve() throws {
        let (_, end) = Self.points(RestRingGeometry.phone.arc(progress: 1.0.nextDown, in: Self.frame))
        let last = try #require(end)
        #expect(hypot(last.x - 32, last.y - 3) < 0.01)
        let (_, nearly) = Self.points(RestRingGeometry.phone.arc(progress: 0.99, in: Self.frame))
        let almost = try #require(nearly)
        #expect(almost.x < 32, "0.99 ends left of 12 o'clock (clockwise): \(almost)")
    }

    @Test("The phone geometry keeps the stroke inside its square: r + half the stroke < half the side")
    func phoneGeometry_strokeInsideFrame() {
        let geometry = RestRingGeometry.phone
        #expect(geometry.diameter == PrototypeRing.viewBox)
        #expect(geometry.radius == PrototypeRing.radius)
        #expect(geometry.lineWidth == PrototypeRing.strokeWidth)
        #expect(geometry.radius + geometry.lineWidth / 2 < geometry.diameter / 2)
    }
}

#if os(iOS)
    extension RenderingSuites {
        /// The ring as drawn, at the text sizes it grows with, in both schemes.
        @Suite("RestRing rendering (adversarial, slice 2 round 1)", .tags(.design))
        struct RestRingRenderingAdversarialTests {
            nonisolated static let sizes: [DynamicTypeSize] = [
                .xSmall, .large, .xLarge, .xxxLarge, .accessibility3, .accessibility5
            ]

            static func buffer(
                _ view: some View,
                _ size: DynamicTypeSize,
                _ scheme: ColorScheme = .dark
            ) throws -> PixelBuffer {
                let image = try #require(
                    RenderedImage.render(
                        view.background(LedgerColor.ground),
                        colorScheme: scheme,
                        dynamicTypeSize: size
                    )
                )
                return try #require(PixelBuffer(image))
            }

            /// Orange: strong red, well above green (the accent is FF 5B 22; the inks are grey).
            static func isOrange(_ pixel: Pixel) -> Bool {
                pixel.red >= 0x80 && Int(pixel.red) - Int(pixel.green) >= 60
            }

            static func orangePoints(_ buffer: PixelBuffer) -> [(x: Double, y: Double)] {
                (0 ..< buffer.height).flatMap { row in
                    (0 ..< buffer.width).compactMap { column in
                        isOrange(buffer.pixel(column: column, row: row)) ? (Double(column) + 0.5, Double(row) + 0.5) :
                            nil
                    }
                }
            }

            @Test("Nothing is drawn outside the ring's frame, and the stroke keeps clear of its edge", arguments: sizes)
            func fullRing_ink_staysInsideItsFrame(size: DynamicTypeSize) throws {
                // The ring's frame is fractional above and below `.large` (69.8 pt at xLarge), so the
                // image's outermost pixels are partly transparent: ink is an opaque pixel unlike the
                // dark ground, and the padding must hold none of it.
                let inset = Int(LedgerSpacing.m)
                let buffer = try Self.buffer(RestRing(progress: 1, label: "").padding(LedgerSpacing.m), size)
                let ground = Pixel(hex: 0x0B0B0D)
                var columns: [Int] = []
                var rows: [Int] = []
                for row in 0 ..< buffer.height {
                    for column in 0 ..< buffer.width {
                        let pixel = buffer.pixel(column: column, row: row)
                        if pixel.alpha == 0xFF, pixel.differs(from: ground, by: 4) {
                            columns.append(column)
                            rows.append(row)
                        }
                    }
                }
                let left = try #require(columns.min(), "\(size): no ink")
                let right = buffer.width - 1 - (columns.max() ?? 0)
                let top = rows.min() ?? 0
                let bottom = buffer.height - 1 - (rows.max() ?? 0)
                let margins = [left, right, top, bottom]
                #expect(
                    margins.allSatisfy { $0 >= inset },
                    "\(size): ink in the \(inset) pt padding: margins \(margins)"
                )
                #expect(
                    (margins.max() ?? 0) - (margins.min() ?? 0) <= 1,
                    "\(size): the ring is off centre: margins \(margins)"
                )
            }

            @Test(
                "The label stays inside the ring and on one line at every text size",
                arguments: sizes
            )
            func label_atEveryTextSize_staysInsideTheTrack(size: DynamicTypeSize) throws {
                for label in ["2:30", "10:00", "0:05"] {
                    let buffer = try Self.buffer(RestRing(progress: 0, label: label), size)
                    let side = Double(buffer.width)
                    let inner = (Double(PrototypeRing.radius) - Double(PrototypeRing.strokeWidth) / 2) * side / 64
                    var farthest = 0.0
                    for row in 0 ..< buffer.height {
                        for column in 0 ..< buffer.width where buffer.pixel(column: column, row: row).red > 127 {
                            farthest = max(
                                farthest,
                                hypot(Double(column) + 0.5 - side / 2, Double(row) + 0.5 - side / 2)
                            )
                        }
                    }
                    #expect(farthest > 0, "\(size) \"\(label)\": no label ink")
                    #expect(
                        farthest < inner - 1,
                        "\(size) \"\(label)\": label ink \(farthest) pt from the centre, track inside \(inner)"
                    )
                    #expect(Probe.inkRuns(buffer).count == 1, "\(size) \"\(label)\": the label wraps")
                }
            }

            @Test(
                "A quarter is drawn in the top-right quadrant only; three quarters leave the top-left empty",
                arguments: [DynamicTypeSize.large, .accessibility3]
            )
            func quarterAndThreeQuarters_direction_isClockwiseFromTwelve(size: DynamicTypeSize) throws {
                for scheme in [ColorScheme.light, .dark] {
                    let quarter = try Self.buffer(RestRing(progress: 0.25, label: ""), size, scheme)
                    let side = Double(quarter.width)
                    let centre = side / 2
                    // A round cap reaches half the stroke past the arc's end, plus a pixel of anti-aliasing.
                    let cap = Double(PrototypeRing.strokeWidth) / 2 * side / 64 + 1
                    let quarterOrange = Self.orangePoints(quarter)
                    #expect(!quarterOrange.isEmpty, "\(size) \(scheme): no orange")
                    let outside = quarterOrange.filter { $0.x < centre - cap || $0.y > centre + cap }
                    #expect(outside.isEmpty, "\(size) \(scheme): \(outside.count) orange pixels outside the top-right")
                    #expect(quarterOrange.contains { $0.y < cap * 2 && abs($0.x - centre) < cap }, "starts at 12")
                    #expect(quarterOrange.contains { $0.x > side - cap * 2 && abs($0.y - centre) < cap }, "reaches 3")

                    let threeQuarters = try Self.orangePoints(Self.buffer(
                        RestRing(progress: 0.75, label: ""),
                        size,
                        scheme
                    ))
                    let topLeft = threeQuarters.filter { $0.x < centre - cap && $0.y < centre - cap }
                    #expect(topLeft.isEmpty, "\(size) \(scheme): \(topLeft.count) orange pixels in the top-left")
                    #expect(threeQuarters.contains { $0.x < cap * 2 && abs($0.y - centre) < cap }, "reaches 9")
                }
            }

            @Test(
                "Criterion 5 as drawn: half the progress is the right half, half the orange of a full ring",
                arguments: sizes
            )
            func halfProgress_orangeArea_isTheRightHalfOfTheFullRing(size: DynamicTypeSize) throws {
                for scheme in [ColorScheme.light, .dark] {
                    let halfBuffer = try Self.buffer(RestRing(progress: 0.5, label: ""), size, scheme)
                    let half = Self.orangePoints(halfBuffer)
                    let full = try Self.orangePoints(Self.buffer(RestRing(progress: 1, label: ""), size, scheme))
                    let ratio = Double(half.count) / Double(max(full.count, 1))
                    #expect(abs(ratio - 0.5) < 0.05, "\(size) \(scheme): \(half.count) / \(full.count) = \(ratio)")
                    let side = Double(halfBuffer.width)
                    let cap = Double(PrototypeRing.strokeWidth) / 2 * side / 64 + 1
                    let left = half.filter { $0.x < side / 2 - cap }
                    #expect(left.isEmpty, "\(size) \(scheme): \(left.count) orange pixels left of the centre line")
                }
            }
        }
    }
#endif
