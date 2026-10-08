#if DEBUG
    @testable import FeatureToday
    import LedgerDesign
    import LedgerDomain
    import SwiftUI

    /// What Today scrolls, without the scroll view the screen puts it in: what the VoiceOver trees and the
    /// snapshot references are taken from (the M1 convention for a screen that scrolls, `docs/testing-strategy.md`
    /// §2.6). Today has no pinned part, so its parts are its page alone, on the screen's ground, with the resume
    /// time standing still at the state's own moment.
    struct TodayParts: View {
        let preview: TodayPreview
        var send: (TodayAction) -> Void = { _ in }

        var body: some View {
            TodayPage(state: preview.state, send: send)
                .background(LedgerColor.ground)
                .environment(\.todayTimerPause, preview.now)
        }
    }

    /// The off-schedule sheet's pinned part, `SheetChrome`'s title and "Cancel", over its page, without the scroll
    /// view the sheet puts the page in (§2.6: a sheet whose content scrolls is a screen that scrolls).
    struct OffScheduleParts: View {
        let model: TodayModel.OffSchedule
        var onPick: (TodayRoute) -> Void = { _ in }
        var onCancel: () -> Void = {}

        /// The sheet of the rest-day preview's card.
        static func ofTheRestDay(
            onPick: @escaping (TodayRoute) -> Void = { _ in },
            onCancel: @escaping () -> Void = {}
        ) throws -> OffScheduleParts {
            guard case let .restDay(card) = try TodayPreview.restDay.model().card else {
                throw TodayPreviewData.Unreadable()
            }
            return OffScheduleParts(model: card.offSchedule, onPick: onPick, onCancel: onCancel)
        }

        var body: some View {
            SheetChrome(model.title, cancel: model.cancel, onCancel: onCancel) {
                OffSchedulePage(model: model, onPick: onPick)
            }
        }
    }
#endif
