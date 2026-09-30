import SwiftUI

/// The watch's rest countdown (LedgerWatch "rest timer"; spec §8.8): `RestRing`'s arc and track at the
/// watch ring's proportions (`RestRingGeometry.watch`, 130.7 pt at the 46 mm default text size), with
/// the time left in the countdown numerals. `progress` is the fraction of the rest still to go,
/// clamped to 0…1. The ring grows and shrinks with its label's text size, so the label always fits;
/// a label too long for it shrinks, never below the 11 pt watch floor.
///
/// VoiceOver reads one element that updates frequently, named by `accessibilitySummary`, the time left
/// in words ("1 minute 15 seconds left"). It is required: a bare "1:15" can sound like a time
/// of day, so the ring never reads its label.
public struct WatchRestRing: View {
    private let progress: Double
    private let label: String
    private let summary: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(progress: Double, label: String, accessibilitySummary: String) {
        self.progress = progress
        self.label = label
        summary = accessibilitySummary
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
                .stroke(LedgerColor.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Text(label)
                .ledgerFont(.watchCountdown)
                .foregroundStyle(LedgerColor.watchInk)
                .lineLimit(1)
                .minimumScaleFactor(LedgerFont.shrinkLimit(.watchCountdown, size: size))
                .frame(maxWidth: (2 * geometry.radius - geometry.lineWidth) * scale) // inside the track
        }
        .frame(width: geometry.diameter * scale, height: geometry.diameter * scale)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: summary))
        .accessibilityAddTraits(.updatesFrequently)
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
