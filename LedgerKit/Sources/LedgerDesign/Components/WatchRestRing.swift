import SwiftUI

/// The watch's rest countdown (LedgerWatch "rest timer"; spec §8.8): `RestRing`'s arc and track at the
/// watch ring's proportions (`RestRingGeometry.watch`, 130.7 pt at the 46 mm default text size), with
/// the time left in the countdown numerals. `progress` is the fraction of the rest still to go,
/// clamped to 0…1. The ring grows and shrinks with its label's text size, so the label always fits;
/// a label too long for it shrinks, never below the 11 pt watch floor. With the wrist down (Always-On,
/// `isLuminanceReduced`) the arc dims to `WatchTokens.accentDimmed`; the track and the time stay as they are.
///
/// The label is a `Text`, so that a screen can hand it a live countdown (`Text(timerInterval:)`), which ticks
/// with no view update and keeps ticking with the wrist down. Under it, inside the track, the ring draws its
/// `footer` (the rest screen's heart rate and next set), each line its own VoiceOver element, in the narrower chord
/// the track leaves there.
///
/// VoiceOver reads the time as one element that updates frequently, named by `accessibilitySummary`, the time left
/// in words ("1 minute 15 seconds left"). It is required: a bare "1:15" can sound like a time
/// of day, so the ring never reads its label.
public struct WatchRestRing<Footer: View>: View {
    private let progress: Double
    private let label: Text
    private let summary: String
    private let footer: Footer?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    public init(
        progress: Double,
        label: Text,
        accessibilitySummary: String,
        @ViewBuilder footer: () -> Footer
    ) {
        self.init(progress: progress, label: label, summary: accessibilitySummary, footer: footer())
    }

    /// Without a footer (nil), the time alone is inside the ring.
    private init(progress: Double, label: Text, summary: String, footer: Footer?) {
        self.progress = progress
        self.label = label
        self.summary = summary
        self.footer = footer
    }

    /// The footer's width, as a share of the inside of the track: the chord the ring leaves under the time.
    static var footerShare: CGFloat {
        0.75
    }

    public var body: some View {
        let geometry = RestRingGeometry.watch
        let size = LedgerFont.scaledSize(.watchCountdown, dynamicTypeSize: dynamicTypeSize)
        let scale = size / LedgerFont.Role.watchCountdown.spec.size
        let lineWidth = geometry.lineWidth * scale
        ZStack {
            RestRingArc(progress: 1, geometry: geometry)
                .stroke(LedgerColor.watchTrack, lineWidth: lineWidth)
            RestRingArc(progress: progress, geometry: geometry)
                .stroke(
                    WatchTokens.accent(isLuminanceReduced: isLuminanceReduced),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            VStack(spacing: LedgerSpacing.xs) {
                label
                    .ledgerFont(.watchCountdown)
                    .foregroundStyle(LedgerColor.watchInk)
                    .lineLimit(1)
                    .minimumScaleFactor(LedgerFont.shrinkLimit(.watchCountdown, size: size))
                    .accessibilityLabel(Text(verbatim: summary))
                    .accessibilityAddTraits(.updatesFrequently)
                if let footer {
                    footer.frame(maxWidth: Self.footerShare * (2 * geometry.radius - geometry.lineWidth) * scale)
                }
            }
            .frame(maxWidth: (2 * geometry.radius - geometry.lineWidth) * scale) // inside the track
        }
        .frame(width: geometry.diameter * scale, height: geometry.diameter * scale)
    }
}

public extension WatchRestRing where Footer == EmptyView {
    /// The ring with `label` alone inside it.
    init(progress: Double, label: String, accessibilitySummary: String) {
        self.init(progress: progress, label: Text(verbatim: label), summary: accessibilitySummary, footer: nil)
    }
}

/// A full, a half and an empty ring, for the preview, the snapshot tests and the gallery.
struct WatchRestRingGallery: View {
    var body: some View {
        VStack(spacing: LedgerSpacing.l) {
            WatchRestRing(progress: 1, label: "2:30", accessibilitySummary: "2 minutes 30 seconds left")
            WatchRestRing(progress: 0.5, label: "1:15", accessibilitySummary: "1 minute 15 seconds left")
            WatchRestRing(progress: 0, label: "0:00", accessibilitySummary: "Rest over")
        }
        .frame(maxWidth: .infinity)
    }
}
