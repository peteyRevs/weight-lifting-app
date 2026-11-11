#if DEBUG
    import LedgerDomain
    import LedgerFakes
    import SwiftUI

    /// Every preview of "Delete all data"'s sheet, one case each: drawn from the model its presentation makes of a
    /// fixed draft, as `PlatesPreview` draws the plates sheet. `PreviewTests` render every case; the snapshot and
    /// accessibility tests draw the same states' pages. The warning is the system's alert, which no preview draws.
    enum DeleteAllPreview: String, CaseIterable {
        /// Nothing typed yet: "Delete everything" is dimmed.
        case empty = "Delete all data"
        /// The word typed in lower case, with a space after it: it matches.
        case typed = "Delete all data, typed"
        /// The word typed and the erase failed: the sheet says nothing was deleted.
        case failed = "Delete all data, failed"

        var draft: DeleteAllDraft {
            switch self {
            case .empty:
                DeleteAllDraft(step: .typing)
            case .typed:
                DeleteAllDraft(step: .typing, text: "delete ")
            case .failed:
                DeleteAllDraft(step: .typing, text: "DELETE", failed: true)
            }
        }

        func model() -> DeleteAllSheetModel? {
            DeleteAllPresentation.sheet(draft, locale: Fixtures.locale)
        }

        /// The sheet in this state.
        @ViewBuilder var content: some View {
            if let model = model() {
                DeleteAllSheet(model: model) { _ in }
            }
        }
    }

    #Preview("Delete all data") {
        DeleteAllPreview.empty.content
    }

    #Preview("Delete all data, typed") {
        DeleteAllPreview.typed.content
    }

    #Preview("Delete all data, failed") {
        DeleteAllPreview.failed.content
    }
#endif
