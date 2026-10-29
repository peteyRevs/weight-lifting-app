import Foundation
import LedgerDesign
import LedgerDomain

/// Everything a past workout's detail draws and speaks, as `WorkoutDetailPresentation.make(_:)` builds it: the day
/// it started over its name, F10's receipt in the lifter's units, and "Delete workout". Every string is final and
/// every control carries what its tap means: the views draw the model and decide nothing.
nonisolated struct WorkoutDetailModel: Equatable, Sendable {
    /// "Wednesday, September 16": the day the workout started.
    let date: String
    /// The workout's name, as stored: the screen's heading.
    let title: String
    /// The receipt (`LedgerDesign`'s `ReceiptLayout`), as F10's cover draws it after a save.
    let receipt: ReceiptLayout.Model
    /// What a tap on each of `receipt.rows` sends, in the same order: its exercise's history.
    let rowRoutes: [HistoryRoute]
    let delete: Deletion

    /// "Delete workout", and the alert it opens first (F13 question 8, built to A): "Delete this workout?", what it
    /// removes, "Delete" and "Cancel".
    struct Deletion: Equatable, Sendable {
        let title: String
        let question: String
        let message: String
        let confirm: String
        let cancel: String
    }

    /// N10: a workout this app can't read, said in place of the receipt, with "Delete workout" still offered.
    struct Unreadable: Equatable, Sendable {
        let title: String
        let body: String
        let delete: Deletion
    }
}
