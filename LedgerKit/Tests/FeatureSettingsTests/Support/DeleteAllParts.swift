#if DEBUG
    @testable import FeatureSettings
    import LedgerDesign
    import SwiftUI

    /// "Delete all data"'s sheet without its scroll view: `SheetChrome`'s title and "Cancel" over the page and the
    /// foot, as `CreateParts` stands for the exercise sheet. What the sheet's VoiceOver trees, layout checks and
    /// references are taken from (testing-strategy §2.6).
    struct DeleteAllParts: View {
        let model: DeleteAllSheetModel
        var send: (SettingsAction) -> Void = { _ in }

        var body: some View {
            DeleteAllChrome(model: model, send: send) {
                DeleteAllPage(model: model, send: send)
            }
        }
    }
#endif
