import CoreGraphics
@testable import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

/// F06 criterion 5: `RestRing(progress: 0.5)` draws its arc over exactly half the circumference.
/// The ring strokes `RestRingGeometry.arc(progress:in:)` in its frame, so these tests measure that
/// path, flattened, in the frames the ring renders at; `RestRingRenderTests` checks the pixels.
///
/// "Exactly half" is the half arc against the full ring the same code draws (equal to 1e-9).
/// Against the ideal circle, 2π·r, a path is only as exact as Core Graphics' arcs: cubic Béziers,
/// one per quarter turn or less, whose length is 0.014 % off the true arc's (measured), so those
/// comparisons allow 0.03 % (`bezier`).
@Suite("RestRingGeometry", .tags(.design))
nonisolated struct RestRingGeometryTests {
    /// The v2 ring: r 29 in a 64 pt frame, `stroke-dasharray` 182.
    static let frame = CGRect(x: 0, y: 0, width: 64, height: 64)
    static let circumference = 2 * CGFloat.pi * 29
    /// The relative length error a Bézier arc may have (see above).
    static let bezier: CGFloat = 0.0003

    @Test("progress 0.5 covers exactly half the circumference")
    func halfProgress_arcLength_isHalfTheCircumference() {
        // The shape `RestRing` strokes, at the frame it renders at (review R2-N9).
        let half = Measured(RestRingArc(progress: 0.5, geometry: .phone).path(in: Self.frame))
        let full = Measured(RestRingArc(progress: 1, geometry: .phone).path(in: Self.frame))
        #expect(abs(half.length / full.length - 0.5) < 1e-9)
        #expect(abs(half.length - Self.circumference / 2) < Self.circumference / 2 * Self.bezier)
    }

    @Test("progress 0.5 runs clockwise from 12 o'clock to 6 o'clock")
    func halfProgress_arcEnds_twelveToSixClockwise() {
        let half = Measured(RestRingGeometry.phone.arc(progress: 0.5, in: Self.frame))
        let quarter = Measured(RestRingGeometry.phone.arc(progress: 0.25, in: Self.frame))
        #expect(half.start.isClose(to: CGPoint(x: 32, y: 3)))
        #expect(half.end.isClose(to: CGPoint(x: 32, y: 61)))
        #expect(
            quarter.end.isClose(to: CGPoint(x: 61, y: 32)),
            "a quarter ends at 3 o'clock, so the sweep is clockwise"
        )
    }

    @Test(
        "The arc covers the fraction of the circumference it is given",
        arguments: [0.1, 0.25, 1.0 / 3, 0.5, 0.62, 0.75, 0.9, 0.999]
    )
    func fraction_arcLength_isProportional(_ progress: Double) {
        let arc = Measured(RestRingGeometry.phone.arc(progress: progress, in: Self.frame))
        #expect(abs(arc.length - Self.circumference * progress) < Self.circumference * Self.bezier)
    }

    @Test("The ring's circumference is the prototype's stroke-dasharray, 182")
    func circumference_matchesPrototypeDashArray() {
        let full = Measured(RestRingGeometry.phone.arc(progress: 1, in: Self.frame))
        #expect(abs(full.length - Self.circumference) < Self.circumference * Self.bezier)
        #expect(Int(full.length.rounded()) == 182)
        #expect(full.end.isClose(to: full.start), "a full ring closes at 12 o'clock")
    }

    @Test("Nothing is drawn at 0, below 0 or for NaN", arguments: [0, -0.001, -0.5, -Double.infinity, Double.nan])
    func emptyOrBelowRange_arc_isEmpty(_ progress: Double) {
        let arc = RestRingGeometry.phone.arc(progress: progress, in: Self.frame)
        #expect(arc.isEmpty)
        #expect(RestRingGeometry.fraction(progress) == 0)
    }

    @Test("Above 1 the ring is full", arguments: [1, 1.0001, 1.5, 30, Double.infinity])
    func aboveRange_arc_isTheFullRing(_ progress: Double) {
        let arc = Measured(RestRingGeometry.phone.arc(progress: progress, in: Self.frame))
        #expect(abs(arc.length - Self.circumference) < Self.circumference * Self.bezier)
        #expect(RestRingGeometry.fraction(progress) == 1)
    }

    /// The ring grows with its label's Dynamic Type size: its frame is 64 pt at `.large` and about
    /// 70, 137 and 186 pt at `.xLarge`, `.accessibility3` and `.accessibility5` (measured in the
    /// references). The radius scales with it, so half is still half.
    @Test("Half is half at every rendered size", arguments: [64.0, 69.8, 137.5, 186.2])
    func scaledFrame_halfProgress_isHalfTheCircumference(_ side: Double) {
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        let half = Measured(RestRingGeometry.phone.arc(progress: 0.5, in: rect))
        let full = Measured(RestRingGeometry.phone.arc(progress: 1, in: rect))
        let scaled = 2 * .pi * 29 * side / 64
        #expect(abs(full.length - scaled) < scaled * Self.bezier)
        #expect(abs(half.length / full.length - 0.5) < 1e-9)
    }
}

/// The watch ring (F06 slice 3), `WatchRestRing`'s geometry: LedgerWatch's SVG ring, r 88 and stroke 9
/// in a 200-unit box, drawn 196 px across at 1.5× a 46 mm display.
@Suite("WatchRestRingGeometry", .tags(.design))
nonisolated struct WatchRestRingGeometryTests {
    static let watch = RestRingGeometry.watch
    static let frame = CGRect(x: 0, y: 0, width: watch.diameter, height: watch.diameter)

    @Test("The watch ring has the prototype's proportions and is 196 px ÷ 1.5 across")
    func watchGeometry_proportions_matchThePrototypeSVG() {
        #expect(abs(Self.watch.diameter - 196 / 1.5) < 1e-9)
        #expect(abs(Self.watch.radius / Self.watch.diameter - 88.0 / 200) < 1e-12)
        #expect(abs(Self.watch.lineWidth / Self.watch.diameter - 9.0 / 200) < 1e-12)
    }

    @Test("The watch ring's circumference, in the SVG's units, is its stroke-dasharray, 553")
    func watchCircumference_inSVGUnits_matchesPrototypeDashArray() {
        let full = Measured(RestRingArc(progress: 1, geometry: Self.watch).path(in: Self.frame))
        #expect(Int((full.length * 200 / Self.watch.diameter).rounded()) == 553)
        #expect(full.end.isClose(to: full.start), "a full ring closes at 12 o'clock")
    }

    @Test("Half the watch ring is half its circumference, from 12 o'clock to 6 clockwise")
    func watchHalf_arc_isHalfTheCircumference() {
        let half = Measured(RestRingArc(progress: 0.5, geometry: Self.watch).path(in: Self.frame))
        let full = Measured(RestRingArc(progress: 1, geometry: Self.watch).path(in: Self.frame))
        let centre = Self.watch.diameter / 2
        #expect(abs(half.length / full.length - 0.5) < 1e-9)
        #expect(half.start.isClose(to: CGPoint(x: centre, y: centre - Self.watch.radius)))
        #expect(half.end.isClose(to: CGPoint(x: centre, y: centre + Self.watch.radius)))
    }
}

/// A path's length (curves flattened into 256 chords each), start and end.
private nonisolated struct Measured {
    var length: CGFloat = 0
    var start = CGPoint.zero
    var end = CGPoint.zero

    init(_ path: Path) {
        var elements: [Path.Element] = [] // Path is not a Sequence
        path.forEach { elements.append($0) }
        var subpathStart = CGPoint.zero
        for element in elements {
            switch element {
            case let .move(point):
                if length == 0 {
                    start = point
                }
                (subpathStart, end) = (point, point)
            case let .line(point):
                add([end, point])
            case let .quadCurve(point, control):
                add(Self.flatten([end, control, point]))
            case let .curve(point, control1, control2):
                add(Self.flatten([end, control1, control2, point]))
            case .closeSubpath:
                add([end, subpathStart])
            }
        }
    }

    private mutating func add(_ points: [CGPoint]) {
        for (from, next) in zip(points, points.dropFirst()) {
            length += hypot(next.x - from.x, next.y - from.y)
        }
        end = points.last ?? end
    }

    /// 257 points along the Bézier curve with these control points.
    private static func flatten(_ controls: [CGPoint]) -> [CGPoint] {
        (0 ... 256).map { point(on: controls, at: CGFloat($0) / 256) }
    }

    /// De Casteljau: interpolate between neighbouring control points until one point is left.
    private static func point(on controls: [CGPoint], at fraction: CGFloat) -> CGPoint {
        var points = controls
        while points.count > 1 {
            points = zip(points, points.dropFirst()).map { from, next in
                CGPoint(x: from.x + (next.x - from.x) * fraction, y: from.y + (next.y - from.y) * fraction)
            }
        }
        return points.first ?? .zero
    }
}

private nonisolated extension CGPoint {
    func isClose(to other: CGPoint) -> Bool {
        hypot(x - other.x, y - other.y) < 0.01
    }
}

extension RenderingSuites {
    /// Criterion 5 on the rendered ring: at progress 0.5 the orange arc fills the right half,
    /// 12 o'clock to 6 o'clock through 3, and nothing orange is drawn left of the centre line.
    @Suite("RestRingRender", .tags(.design))
    struct RestRingRenderTests {
        @Test("A half-full ring is orange on its right half only")
        func halfProgress_rendered_isOrangeOnTheRightHalfOnly() throws {
            let image = try #require(RenderedImage.render(RestRing(progress: 0.5, label: "1:15")))
            let pixels = try #require(PixelBuffer(image))
            #expect((pixels.width, pixels.height) == (64, 64))
            let orange = Pixel(hex: 0xFF5B22)
            func orangeCount(columns: Range<Int>, rows: Range<Int>) -> Int {
                columns.reduce(0) { count, column in
                    count + rows.count(where: { row in
                        let pixel = pixels.pixel(column: column, row: row)
                        return pixel.alpha == 0xFF && !pixel.differs(from: orange, by: 24)
                    })
                }
            }
            // The round caps reach 1.25 pt past the centre line at 12 and 6 o'clock.
            #expect(orangeCount(columns: 0 ..< 30, rows: 0 ..< 64) == 0)
            #expect(orangeCount(columns: 34 ..< 64, rows: 0 ..< 32) > 20, "3 o'clock side, upper quarter")
            #expect(orangeCount(columns: 34 ..< 64, rows: 32 ..< 64) > 20, "3 o'clock side, lower quarter")
        }
    }
}
