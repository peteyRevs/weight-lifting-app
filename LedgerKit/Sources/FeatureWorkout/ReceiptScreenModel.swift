import Foundation
import LedgerDesign

/// The receipt of the workout this cover saved (F10 S7b): its pinned header, and the page that scrolls
/// under it, which is `LedgerDesign`'s `ReceiptLayout`. Built by `WorkoutPresentation.receipt`, drawn by
/// `ReceiptScreen`; every string is final.
nonisolated struct ReceiptScreenModel: Equatable, Sendable {
    let header: ReceiptHeaderModel
    let page: ReceiptLayout.Model
    /// What a tap on each of `page.rows` sends, in the same order: its exercise's history (F12 S3, N18).
    let rowActions: [WorkoutAction]
}

/// The receipt's header: the day the workout started, its name and "Done".
nonisolated struct ReceiptHeaderModel: Equatable, Sendable {
    /// "Wednesday, September 16".
    let date: String
    /// The workout's name, as stored: data, not copy.
    let title: String
    let done: String
}
