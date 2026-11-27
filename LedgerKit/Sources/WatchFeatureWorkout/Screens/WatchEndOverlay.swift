import LedgerDesign
import SwiftUI

/// The end of a workout (spec §4.3 "Watch — end workout"; F18 criterion 10), over the live workout in its place, as
/// the prototype draws it: "End workout?" and the sets and the weight logged so far, then the orange "Save workout",
/// which shows the summary, or the outlined "Discard", which returns to the screen before a workout, and the muted
/// "Keep lifting", which goes back to the session list. "Save workout" shows once a set is logged, and "Discard" only
/// while none is (`WatchEndModel.offersDiscard`), so the two are never offered together.
///
/// It stays up through a change of mode (spec §4.2). With the wrist down its orange dims, as every pill's does. Text
/// too large for the screen scrolls the whole page.
struct WatchEndOverlay: View {
    let model: WatchEndModel
    let send: (WatchAction) -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            page
            ScrollView { page }
        }
        .background(LedgerColor.watchGround)
    }

    var page: some View {
        WatchEndPage(screen: self)
    }

    /// "Save workout", while a set is logged; nil when it is not drawn.
    var save: (() -> Void)? {
        model.canSave ? { send(.save) } : nil
    }

    /// "Discard", while no set is logged; nil when it is not drawn.
    var discard: (() -> Void)? {
        model.offersDiscard ? { send(.discard) } : nil
    }

    func keepLifting() {
        send(.keepLifting)
    }
}

/// The page itself, at the prototype's measures ÷ 1.5: its 20 px inset is `m`, its 9 px between the title and the
/// line `s`, its 8 px between the buttons `s`. The words sit in the spare height above the buttons.
private struct WatchEndPage: View {
    let screen: WatchEndOverlay

    private var model: WatchEndModel {
        screen.model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                Text(verbatim: model.title)
                    .ledgerFont(.watchStat)
                    .foregroundStyle(LedgerColor.watchInk)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: model.line)
                    .ledgerFont(.watchTitle)
                    .foregroundStyle(LedgerColor.watchInkSecondary)
                    .accessibilityLabel(Text(verbatim: model.spokenLine))
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: LedgerSpacing.m)
            VStack(spacing: LedgerSpacing.s) {
                if let save = screen.save {
                    WatchPill(model.save, action: save)
                }
                if let discard = screen.discard {
                    WatchPill(model.discard, style: .outlined, action: discard)
                }
                Button(action: screen.keepLifting) {
                    Text(verbatim: model.keepLifting)
                        .ledgerFont(.watchTitle)
                        .foregroundStyle(LedgerColor.watchInkMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: WatchTokens.stepButton)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(LedgerSpacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
