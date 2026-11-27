import LedgerDesign
import SwiftUI

/// STUB (F18 S5a): what the root shows for the summary until F18 S6 draws it; delete it then. It shows the first
/// lines of the summary's model and its "Done", so that a finished workout can go back to the screen before a
/// workout in the meantime.
struct WatchStubScreen: View {
    let lines: [String]
    /// The one pill, and the action it sends.
    var pill: (title: String, action: WatchAction)?
    var send: (WatchAction) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
            ForEach(lines.indices, id: \.self) { index in
                Text(verbatim: lines[index])
                    .ledgerFont(index == 0 ? .watchLabel : .watchTitle)
                    .foregroundStyle(index == 0 ? LedgerColor.accent : LedgerColor.watchInk)
            }
            Spacer(minLength: LedgerSpacing.m)
            if let pill {
                WatchPill(pill.title, style: .outlined, action: tap)
            }
        }
        .padding(LedgerSpacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The pill's tap.
    func tap() {
        pill.map { send($0.action) }
    }
}
