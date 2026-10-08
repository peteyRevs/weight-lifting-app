import Foundation
import LedgerDomain

/// Everything `DayEditorPresentation.make(_:)` reads. The store fills it; the presentation reaches for nothing
/// else, so the same input always gives the same model.
nonisolated struct DayEditorInput: Sendable {
    /// The program on screen: the stored one with the edits not stored yet.
    var program: Program
    /// The day being edited. A program that does not hold it gives `DayEditorModel.dayIsGone`.
    var day: DayTemplateID
    /// The stored exercises by id. A slot whose exercise is missing is still listed, under a dash, and can be
    /// moved and removed.
    var exercises: [ExerciseID: Exercise]
    /// Its units are the ones every load is shown and stepped in.
    var settings: Settings
    /// The week shown, as its place in the block, 0 for the first: the week the builder had selected. A place
    /// outside the block is read as the nearest week.
    var weekIndex: Int
    /// The slot whose panel is open, or nil. A slot the day does not hold is read as none open.
    var openSlot: SlotID?
    var locale: Locale
}
