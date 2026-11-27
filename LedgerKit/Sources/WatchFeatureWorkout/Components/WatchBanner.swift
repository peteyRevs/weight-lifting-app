import LedgerDesign
import SwiftUI

/// A line the watch's workout keeps at the top of the screen while it holds (spec §9's undesigned states): "Apple
/// Workout took over · logging continues". It takes the session list's orange 16 % fill and corners, and nothing in
/// it is a control; VoiceOver reads it where it stands, as the connection line is read (F17 criterion 12).
struct WatchBanner: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .ledgerFont(.watchTitle)
            .foregroundStyle(LedgerColor.watchInk)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, LedgerSpacing.s)
            .padding(.vertical, LedgerSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WatchTokens.accentFill, in: .rect(cornerRadius: WatchTokens.rowRadius))
    }
}

extension View {
    /// The screen with `banner` above it, pushing it down rather than covering it; the screen alone without one.
    func watchBanner(_ banner: String?) -> some View {
        safeAreaInset(edge: .top, spacing: LedgerSpacing.xs) {
            if let banner {
                WatchBanner(text: banner).padding(.horizontal, LedgerSpacing.s)
            }
        }
    }
}
