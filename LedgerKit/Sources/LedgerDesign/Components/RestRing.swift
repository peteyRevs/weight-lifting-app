import SwiftUI

/// The rest countdown (spec §8.8): an orange arc over a track, from 12 o'clock clockwise, with the
/// time left in the middle. `progress` is the fraction of the rest still to go (`rest / restTotal`),
/// clamped to 0…1; the arc covers that fraction of the circumference and drains back towards 12 as
/// it falls. The ring grows with its label's Dynamic Type size, so the label always fits.
public struct RestRing: View {
    private let progress: Double
    private let label: String
    private let size: RestRingGeometry
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(progress: Double, label: String, size: RestRingGeometry = .phone) {
        self.progress = progress
        self.label = label
        self.size = size
    }

    public var body: some View {
        let scale = LedgerFont.scaledSize(.numeralS, dynamicTypeSize: dynamicTypeSize)
            / LedgerFont.Role.numeralS.spec.size
        let lineWidth = size.lineWidth * scale
        ZStack {
            RestRingArc(progress: 1, geometry: size)
                .stroke(LedgerColor.hairlineStrong, lineWidth: lineWidth)
            RestRingArc(progress: progress, geometry: size)
                .stroke(LedgerColor.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Text(label)
                .ledgerFont(.numeralS)
                .foregroundStyle(LedgerColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5) // a clock string longer than "10:00" shrinks rather than wraps
        }
        .frame(width: size.diameter * scale, height: size.diameter * scale)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// A rest ring's proportions, from the prototype's SVG: a square `diameter` points wide holding a
/// circle of `radius`, stroked at `lineWidth`. The ring scales them together.
public nonisolated struct RestRingGeometry: Equatable, Sendable {
    public let diameter: CGFloat
    public let radius: CGFloat
    public let lineWidth: CGFloat

    /// The v2 rest card: a 64 pt ring, r 29, stroke 2.5 (`stroke-dasharray` 182).
    public static let phone = RestRingGeometry(diameter: 64, radius: 29, lineWidth: 2.5)

    /// `progress` as a fraction of the circle: clamped to 0…1, and 0 when it is not a number.
    static func fraction(_ progress: Double) -> Double {
        progress.isNaN ? 0 : min(max(progress, 0), 1)
    }

    /// The arc for `progress` in `rect`, the ring's frame: centred, with the radius scaled from
    /// `diameter` to the frame's width, from 12 o'clock clockwise over `fraction(progress)` of the
    /// circumference. The SVG draws the same arc as `stroke-dashoffset = C − C × progress` on a
    /// circle turned −90°.
    func arc(progress: Double, in rect: CGRect) -> Path {
        let fraction = Self.fraction(progress)
        var path = Path()
        guard fraction > 0 else { return path }
        let top = Angle.degrees(-90)
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: radius * rect.width / diameter,
            startAngle: top,
            endAngle: top + .degrees(360 * fraction),
            clockwise: false // y points down, so increasing angles run clockwise on screen
        )
        return path
    }
}

/// The arc as a shape; animating `progress` sweeps it smoothly.
nonisolated struct RestRingArc: Shape {
    var progress: Double
    let geometry: RestRingGeometry

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        geometry.arc(progress: progress, in: rect)
    }
}

/// A full, a half and an empty ring, for the preview, the snapshot tests and the gallery.
struct RestRingGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            RestRing(progress: 1, label: "2:30")
            RestRing(progress: 0.5, label: "1:15")
            RestRing(progress: 0, label: "0:00")
        }
    }
}
