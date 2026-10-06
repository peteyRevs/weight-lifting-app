#if DEBUG
    import SwiftUI

    /// Every preview in LedgerAppKit, one case each (F07 criterion 8): each `#Preview` below shows its case's
    /// content, its tests (`PreviewTests`) render every case and fail on a `#Preview` that is not
    /// a case here.
    enum AppPreview: String, CaseIterable {
        case tabs = "Tabs"
        case today = "Today"
        case placeholder = "Placeholder"
        case databaseUnavailable = "Database unavailable"

        @ViewBuilder var content: some View {
            switch self {
            case .tabs: AppTabs(router: AppRouter())
            case .today: TodayPlaceholder()
            case .placeholder: PlaceholderScreen(AppCopy.title(of: .program), identifier: "program.title")
            case .databaseUnavailable: DatabaseUnavailableView()
            }
        }
    }

    #Preview("Tabs") {
        AppPreview.tabs.content
    }

    #Preview("Today") {
        AppPreview.today.content
    }

    #Preview("Placeholder") {
        AppPreview.placeholder.content
    }

    #Preview("Database unavailable") {
        AppPreview.databaseUnavailable.content
    }

#endif
