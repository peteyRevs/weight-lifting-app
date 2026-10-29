#if DEBUG
    @testable import FeatureSettings
    import LedgerDesign
    import SwiftUI

    /// What a state of the preview registry scrolls, without the scroll view its screen puts the page in: what the
    /// VoiceOver trees and the snapshot references are taken from (the M1 convention for a screen that scrolls,
    /// `docs/testing-strategy.md` §2.6). Settings has no pinned part, so its parts are its page alone, on the
    /// screen's ground.
    struct SettingsParts: View {
        let preview: SettingsPreview
        var send: (SettingsAction) -> Void = { _ in }

        var body: some View {
            SettingsPage(model: preview.model(), send: send)
                .background(LedgerColor.ground)
        }
    }
#endif
