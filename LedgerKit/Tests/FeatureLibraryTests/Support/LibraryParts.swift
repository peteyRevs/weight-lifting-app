#if DEBUG
    @testable import FeatureLibrary
    import LedgerDesign
    import SwiftUI

    /// What a state of the preview registry scrolls, without the scroll view its screen puts the page in: what the
    /// VoiceOver trees and the snapshot references are taken from (the M1 convention for a screen that scrolls,
    /// `docs/testing-strategy.md` §2.6). The Library has no pinned part, so its parts are its page alone, on the
    /// screen's ground. A fixture that does not build draws nothing; `PreviewTests` fail on it.
    struct LibraryParts: View {
        let preview: LibraryPreview
        var send: (LibraryAction) -> Void = { _ in }

        var body: some View {
            // `try?`: the fixture's error is `PreviewTests`' to report.
            if let model = try? preview.model() {
                LibraryPage(model: model, send: send)
                    .background(LedgerColor.ground)
            }
        }
    }
#endif
