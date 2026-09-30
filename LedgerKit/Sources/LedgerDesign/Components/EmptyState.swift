import SwiftUI

/// What a screen or list shows when it has nothing yet (v1 "No session today", "Nothing logged yet.",
/// "Nothing matches that filter." with "Clear filters"; v2 draws none, so this sets them in v2's
/// type): a title, a line or two of explanation and an optional outlined action, aligned to the
/// leading edge like the rest of v2.
///
/// VoiceOver reads the title as a heading, then the body, then the action. Strings are shown as
/// given; features pass copy from their catalog.
public struct EmptyState: View {
    private let title: String
    private let message: String
    private let action: (title: String, perform: () -> Void)?

    public init(_ title: String, body: String) {
        self.title = title
        message = body
        action = nil
    }

    public init(_ title: String, body: String, actionTitle: String, action: @escaping () -> Void) {
        self.title = title
        message = body
        self.action = (actionTitle, action)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
            Text(title)
                .ledgerFont(.subheading)
                .foregroundStyle(LedgerColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .ledgerFont(.bodyLight)
                .foregroundStyle(LedgerColor.inkMuted) // the prototype's .50–.55 on paper
            if let action {
                PillButton(action.title, action: action.perform)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, LedgerSpacing.xl)
    }
}

/// With and without an action, for the preview, the snapshot tests and the gallery.
struct EmptyStateGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EmptyState("No session today", body: "Nothing scheduled for Wednesday. Next up is Friday, Lower A.")
            EmptyState(
                "Nothing matches that filter",
                body: "Try another muscle or piece of equipment.",
                actionTitle: "Clear filters"
            ) {}
        }
    }
}
