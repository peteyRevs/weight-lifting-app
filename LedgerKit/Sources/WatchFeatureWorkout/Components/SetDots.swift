import LedgerDesign
import SwiftUI

/// The set screen's dots (spec §4.3): one per set of the exercise, orange once logged and in the 22 % outline colour
/// until then. With the wrist down (Always-On, R1 §5.5) every dot is outlined, the logged ones in the dimmed orange,
/// so the screen lights fewer pixels; the dots keep their size, and nothing moves.
///
/// VoiceOver reads them as one element, `accessibilitySummary` ("2 of 5 sets logged").
struct SetDots: View {
    let dots: [Bool]
    let accessibilitySummary: String
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        HStack(spacing: WatchTokens.setDotGap) {
            ForEach(dots.indices, id: \.self) { index in
                dot(isDone: dots[index])
                    .frame(width: WatchTokens.setDot, height: WatchTokens.setDot)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilitySummary))
        .accessibilityAddTraits(.isStaticText)
    }

    @ViewBuilder private func dot(isDone: Bool) -> some View {
        let color = isDone ? WatchTokens.accent(isLuminanceReduced: isLuminanceReduced) : LedgerColor.watchOutline
        if isLuminanceReduced {
            Circle().strokeBorder(color, lineWidth: LedgerHairline.width)
        } else {
            Circle().fill(color)
        }
    }
}
