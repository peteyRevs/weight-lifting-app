import Foundation
import LedgerDomain

/// Everything `ProgramPresentation.make(_:)` reads. The store fills it; the presentation reaches for nothing
/// else, so the same input always gives the same model: no calendar and no locale but these.
nonisolated struct ProgramBuilderInput: Sendable {
    /// The program on screen: the stored one with the edits not stored yet.
    var program: Program
    /// The stored exercises by id. A slot holds only its exercise's id, so the cards' short names come from
    /// here; a slot whose exercise is missing is still counted and is named by a dash.
    var exercises: [ExerciseID: Exercise] = [:]
    /// Its week start orders the schedule strip's seven cells.
    var settings: Settings
    /// The selected week's place in the block, 0 for the first. A place outside the block is read as the
    /// nearest week, so a selection left behind by "−" needs no repair.
    var selectedWeek: Int
    /// The places of the weeks that hold a finished workout of this program: what "−" asks before it removes
    /// the last week.
    var loggedWeeks: Set<Int> = []
    /// The notice the store is showing, or nil.
    var notice: ProgramBuilderNotice?
    /// The weekday letters and names are this calendar's, in `locale`.
    var calendar: Calendar
    var locale: Locale
}
