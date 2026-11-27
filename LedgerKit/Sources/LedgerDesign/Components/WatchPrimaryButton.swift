import SwiftUI

/// The watch's orange pill ("Start", "Done set", "Skip"; LedgerWatch): the one accent action on a
/// watch screen, `WatchPill`'s `.filled` button. Full width, a white 700 label, at least 44 pt tall (the HIG's default
/// watchOS control size; its minimum is 28 pt). A long title wraps and the pill grows. Disabled, it turns grey.
///
/// `title` is shown as given and is what VoiceOver reads; features pass copy from their catalog.
public struct WatchPrimaryButton: View {
    private let title: String
    private let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        WatchPill(title, style: .filled, action: action)
    }
}

/// Every state: the watch's two orange actions, one pressed, a long title and a disabled one, for
/// the preview, the snapshot tests and the gallery.
struct WatchPrimaryButtonGallery: View {
    var body: some View {
        VStack(spacing: LedgerSpacing.s) {
            WatchPrimaryButton("Start") {}
            WatchPrimaryButton("Done set") {}.environment(\.ledgerDrawsPressed, true)
            WatchPrimaryButton("Save workout and finish") {}
            WatchPrimaryButton("Skip") {}.disabled(true)
        }
    }
}
