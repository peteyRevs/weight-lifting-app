#if DEBUG
    import SwiftUI

    /// Every preview in LedgerAppKit, one case each (F07 criterion 8): each `#Preview` below shows its case's
    /// content, its tests (`PreviewTests`) render every case and fail on a `#Preview` that is not
    /// a case here.
    enum AppPreview: String, CaseIterable {
        case today = "Today"
        case databaseUnavailable = "Database unavailable"

        @ViewBuilder var content: some View {
            switch self {
            case .today: TodayPlaceholder()
            case .databaseUnavailable: DatabaseUnavailableView()
            }
        }
    }

    #Preview("Today") {
        AppPreview.today.content
    }

    #Preview("Database unavailable") {
        AppPreview.databaseUnavailable.content
    }

#endif
