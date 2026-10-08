import LedgerDesign
import SwiftUI

/// "Train off-schedule" (decision #18): a sheet to pick any day of the program and train it today. A sheet
/// whose content scrolls is a screen that scrolls: its pinned part is `SheetChrome`'s title and "Cancel", and
/// what scrolls is `OffSchedulePage`. `TodayScreen` presents it and takes it away.
struct OffScheduleSheet: View {
    let model: TodayModel.OffSchedule
    let onPick: (TodayRoute) -> Void
    let onCancel: () -> Void

    var body: some View {
        SheetChrome(model.title, cancel: model.cancel, onCancel: onCancel) {
            ScrollView {
                OffSchedulePage(model: model, onPick: onPick)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
