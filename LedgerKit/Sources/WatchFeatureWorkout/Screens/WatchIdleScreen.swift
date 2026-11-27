import LedgerDesign
import SwiftUI

/// The screen before a workout (spec §4.3 "Watch — before workout"; F18 criteria 1 and 16), drawn from its model and
/// nothing else: the week's eyebrow in orange at the top, the day's name and the plan line in the middle, and at the
/// bottom the orange "Start" or, with nothing to start, the outlined line of the next session, which does nothing. With
/// no program on the watch it reads "No program on watch" over the outlined "Open Ledger on iPhone", a line too: the
/// watch cannot open the phone's app.
///
/// The page fills the screen and centres the middle, as the prototype does; text too large for the screen scrolls the
/// whole page instead (`ViewThatFits`), so nothing is cut.
///
/// The title is the screen's heading and the element the UI tests find (`today.title`); in Debug builds a long press
/// on it opens the debug menu (F07 criterion 7).
struct WatchIdleScreen: View {
    let model: WatchIdleModel
    let send: (WatchAction) -> Void
    var onTitleLongPress: () -> Void = {}

    var body: some View {
        ViewThatFits(in: .vertical) {
            page
            ScrollView { page }
        }
        .background(LedgerColor.watchGround)
    }

    /// The whole page, at its own height: what the screen shows, or scrolls.
    var page: some View {
        WatchIdlePage(content: WatchIdleContent(model), start: start, onTitleLongPress: onTitleLongPress)
    }

    /// What "Start" does: today's session (`WatchAction.start`). Nil when the screen shows no "Start".
    var start: (() -> Void)? {
        guard WatchIdleContent(model).pill?.isStart == true else {
            return nil
        }
        return { send(.start) }
    }
}

/// The model as the page lays it out: the two shapes of `WatchIdleModel` read as one page.
struct WatchIdleContent: Equatable {
    struct Pill: Equatable {
        let title: String
        /// The orange "Start"; otherwise an outlined line that does nothing.
        let isStart: Bool
    }

    let eyebrow: String?
    let title: String
    let line: String?
    let pill: Pill?

    init(_ model: WatchIdleModel) {
        switch model {
        case let .noProgram(title, open):
            (eyebrow, self.title, line, pill) = (nil, title, nil, Pill(title: open, isStart: false))
        case let .plan(plan):
            (eyebrow, title, line) = (plan.weekLabel, plan.dayName, plan.planLine)
            pill = plan.start.map { Pill(title: $0, isStart: true) }
                ?? plan.next.map { Pill(title: $0, isStart: false) }
        }
    }
}

/// The page itself. The prototype's 20 px inset is `m`; its 11 px between the name and the line is `s`.
struct WatchIdlePage: View {
    let content: WatchIdleContent
    let start: (() -> Void)?
    let onTitleLongPress: () -> Void
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let eyebrow = content.eyebrow {
                Text(verbatim: eyebrow)
                    .ledgerFont(.watchLabel)
                    .foregroundStyle(WatchTokens.accent(isLuminanceReduced: isLuminanceReduced))
            }
            Spacer(minLength: LedgerSpacing.m)
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                title
                if let line = content.line {
                    Text(verbatim: line)
                        .ledgerFont(.watchTitle)
                        .foregroundStyle(LedgerColor.watchInkSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: LedgerSpacing.m)
            if let pill = content.pill {
                if pill.isStart, let start {
                    WatchPill(pill.title, action: start).accessibilityIdentifier("today.start")
                } else {
                    WatchPill(pill.title, style: .outlined).accessibilityIdentifier("today.line")
                }
            }
        }
        .padding(LedgerSpacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var title: some View {
        Text(verbatim: content.title)
            .ledgerFont(.watchStat)
            .foregroundStyle(LedgerColor.watchInk)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("today.title")
        #if DEBUG
            .onLongPressGesture(perform: onTitleLongPress)
        #endif
    }
}
