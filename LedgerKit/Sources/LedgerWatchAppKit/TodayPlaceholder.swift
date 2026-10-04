import LedgerDesign
import SwiftUI

/// The watch's Today until F18 replaces it: the title alone. In Debug builds a long press on the title calls
/// `onTitleLongPress`, which opens the debug menu (F07 criterion 7). The UI tests find the title by its identifier,
/// `today.title`.
struct TodayPlaceholder: View {
    var onTitleLongPress: () -> Void = {}

    var body: some View {
        Text("Today")
            .ledgerFont(.watchTitle)
            .foregroundStyle(LedgerColor.watchInk)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("today.title")
        #if DEBUG
            .onLongPressGesture(perform: onTitleLongPress)
        #endif
            .padding(LedgerSpacing.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(LedgerColor.watchGround)
    }
}
