import Foundation
import LedgerDomain

/// What `ExerciseHistoryPresentation.make(_:)` reads: the store fills it from its sources, once each time one
/// changes.
nonisolated struct ExerciseHistoryInput: Sendable {
    var exercise: Exercise
    /// `StatsQueries.exerciseSessions(exerciseID:)`, newest first.
    var sessions: [ExerciseSession]
    /// The workouts that set a record of the exercise (`personalRecords(exerciseID:)`).
    var records: Set<WorkoutID>
    var units: Units
    var weekStart: Weekday
    var now: Date
    var calendar: Calendar
    var locale: Locale
}

/// Everything an exercise's history draws and speaks (F12 S2). Every string is final: the views draw the model
/// and decide nothing.
nonisolated struct ExerciseHistoryModel: Equatable, Sendable {
    /// "Barbell · Chest".
    let eyebrow: String
    /// The exercise's name: the screen's heading.
    let title: String
    /// "Edit", in the bar, for the lifter's own exercise (F12 S3, criterion 10); nil for a catalog one.
    let edit: String?
    /// "1RM est", "best set" and "sessions", in that order.
    let stats: [Stat]
    let chart: Chart
    let log: Log

    struct Stat: Equatable, Sendable, Identifiable {
        let id: Int
        /// "219", "195", "34", or "—".
        let value: String
        /// "×5" after the best set's weight.
        let unit: String?
        let caption: String
        /// What VoiceOver reads for the tile, "1 session", when the value and caption joined would not read well.
        let spoken: String?
        /// The estimate, in orange (Pete's question 3, A).
        let isAccented: Bool
    }

    struct Chart: Equatable, Sendable {
        /// "ESTIMATED 1RM · 8 WEEKS".
        let title: String
        /// "+22 lb": the last week's shown value less the first's, in orange; nil under two weeks with a value.
        let delta: String?
        /// The eight weeks, oldest first.
        let bars: [Bar]
        /// "Log a session to start the chart.", drawn in place of the bars when no week has a value.
        let empty: String?
        /// What VoiceOver's chart descriptor reads: the chart's name and its two axes' (criterion 12).
        let spokenTitle: String
        /// "Up 22 lb over 8 weeks", or `empty`: the chart's value and its descriptor's summary (F12-S2-4); nil
        /// when one week alone has a value.
        let spokenSummary: String?
        let weekAxis: String
        let valueAxis: String
    }

    struct Bar: Equatable, Sendable, Identifiable {
        let id: Int
        /// "W1" … "W8".
        let week: String
        /// The week's best estimate, a whole number in the lifter's units; nil for a week with no session.
        let number: Int?
        /// `number` as drawn, or "—".
        let value: String
        /// The bar's height, in hundredths of the chart's: 25 for the lowest week, 100 for the highest.
        let level: Int
        /// The current week's bar, in orange.
        let isAccented: Bool
    }

    struct Log: Equatable, Sendable {
        /// "SESSION LOG".
        let title: String
        let entries: [Entry]
        /// "No sessions yet.", when there is no entry.
        let empty: String?
    }

    /// One session, one button that opens its workout.
    struct Entry: Equatable, Sendable, Identifiable {
        let id: WorkoutID
        /// "Aug 12", or "Aug 12, 2025" in another year.
        let date: String
        /// "PR", "+5 lb" or "—".
        let tag: String
        /// PR is bolded, so the tag is never told by colour alone.
        let isRecord: Bool
        /// "180×5  180×5  180×5": every done set.
        let sets: String
        /// "PR, 180×5, 180×5, 180×5": the tag and the sets, as VoiceOver reads them after the date.
        let spokenValue: String
        let route: LibraryRoute
    }
}
