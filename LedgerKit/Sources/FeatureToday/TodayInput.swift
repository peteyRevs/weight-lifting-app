import Foundation
import LedgerDomain

/// Everything `TodayPresentation.make(_:)` reads. The store fills it; the presentation reaches for nothing else,
/// so the same input always gives the same model: no clock, calendar, locale or time zone but these.
nonisolated struct TodayInput: Sendable {
    /// The active program, or nil when there is none.
    var program: Program?
    /// The stored exercises by id. A slot holds only its exercise's id, so the preview rows' names and the
    /// prescriptions' start loads and steps come from here.
    var exercises: [ExerciseID: Exercise] = [:]
    var settings: Settings
    /// The finished workouts that started in the stats week of `now` (the strip's seven days) or in its program
    /// week, which differ when the block began on another weekday than the week starts on. They feed the strip's
    /// done marks, the Logged card, both tiles and the off-schedule list's "Logged" marks; one read, so those
    /// cannot disagree. A workout outside both weeks is not counted anywhere. Any order is accepted: the
    /// presentation orders them itself, so the same workouts give the same model however they are handed in.
    var weekWorkouts: [WorkoutState] = []
    /// The finished workouts that started last, newest first. The first five are shown.
    var recentWorkouts: [WorkoutState] = []
    /// The volume of the stats week before the one of `now`, or nil when it is not known. A zero volume and nil
    /// both leave the volume tile without a change.
    var previousWeekVolume: Volume?
    /// The session's workout: live, or finished or discarded in the one update that ends it; nil when there is
    /// none.
    var session: WorkoutState?
    var now: Date
    /// Its time zone decides which calendar day a moment falls on; dates are formatted with it and its zone.
    var calendar: Calendar
    var locale: Locale
}
