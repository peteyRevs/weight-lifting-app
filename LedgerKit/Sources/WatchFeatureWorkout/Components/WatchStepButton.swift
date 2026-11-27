import LedgerDesign
import SwiftUI

/// "−" or "+" for the reps: a round 44 px button in the 22 % rule, named for VoiceOver ("Decrease reps").
struct WatchStepButton: View {
    let icon: LedgerIcon
    let label: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            LedgerIconView(icon, sizedAs: .watchTitle)
                .foregroundStyle(isEnabled ? LedgerColor.watchInk : LedgerColor.watchInkMuted)
                .frame(minWidth: WatchTokens.stepButton, minHeight: WatchTokens.stepButton)
                .overlay { Circle().strokeBorder(LedgerColor.watchOutline, lineWidth: LedgerHairline.width) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
    }
}
