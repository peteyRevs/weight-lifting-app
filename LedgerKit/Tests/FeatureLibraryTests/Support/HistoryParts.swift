#if DEBUG
    @testable import FeatureLibrary
    import LedgerDesign
    import SwiftUI

    /// What a history preview scrolls, without its scroll view (testing-strategy §2.6): the page on the ground.
    struct HistoryParts: View {
        let preview: HistoryPreview
        var send: (LibraryRoute) -> Void = { _ in }

        var body: some View {
            // `try?`: the fixture's error is `PreviewTests`' to report.
            if let model = try? preview.model() {
                ExerciseHistoryPage(model: model, send: send)
                    .background(LedgerColor.ground)
            }
        }
    }
#endif
