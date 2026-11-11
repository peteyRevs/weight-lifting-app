#if DEBUG
    @testable import FeatureSettings
    import LedgerDesign
    import SwiftUI

    /// What a state of the plates sheet shows, without its scroll view: the page, then the foot with "Done", at the
    /// sheet's side margins on its surface. What the VoiceOver trees and the snapshot references are taken from (the
    /// M1 convention, `docs/testing-strategy.md` §2.6); the sheet's title and "Cancel" are `SheetChrome`'s, pinned
    /// by its own tests.
    struct PlatesParts: View {
        let preview: PlatesPreview
        var send: (SettingsAction) -> Void = { _ in }

        var body: some View {
            let model = preview.model()
            VStack(alignment: .leading, spacing: 0) {
                PlatesPage(model: model, send: send)
                PlatesFoot(done: model.done, send: send)
            }
            .padding(.horizontal, LedgerSpacing.xl)
            .padding(.vertical, LedgerSpacing.l)
            .background(LedgerColor.surface)
        }
    }
#endif
