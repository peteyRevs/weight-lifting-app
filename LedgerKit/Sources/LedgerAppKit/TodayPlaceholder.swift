import LedgerDesign
import SwiftUI

/// Today until F09 replaces it with `FeatureToday`'s screen: the title alone. In Debug builds a long press on the
/// title calls `onTitleLongPress`, which opens the debug menu (F07 criterion 7). The UI tests find the title by
/// its identifier, `today.title`.
struct TodayPlaceholder: View {
    var onTitleLongPress: () -> Void = {}

    var body: some View {
        Text(AppCopy.title(of: .today))
            .ledgerFont(.display)
            .foregroundStyle(LedgerColor.ink)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("today.title")
        #if DEBUG
            .onLongPressGesture(perform: onTitleLongPress)
        #endif
            .padding(LedgerSpacing.screen)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(LedgerColor.ground)
    }
}
