import Foundation
import LedgerDomain

/// Everything the History tab draws and speaks, as `HistoryPresentation.make(_:)` builds it. Every string is final
/// and every control carries the `HistoryRoute` its tap means: the views draw the model and decide nothing.
nonisolated struct HistoryModel: Equatable, Sendable {
    /// "History": the screen's heading.
    let title: String
    let content: Content

    enum Content: Equatable, Sendable {
        /// The weeks that hold a workout, newest first. Never empty.
        case weeks([Week])
        /// No workout is stored: "No workouts yet." with "Go to Today" (F13 question 7, built to A).
        case empty(Empty)
    }

    /// One stats week of the lifter's (decision #15), under its header.
    struct Week: Equatable, Sendable, Identifiable {
        /// The week's first instant.
        let id: Date
        /// "Sep 7 – 13", "Aug 31 – Sep 6", "Dec 28, 2025 – Jan 3, 2026": a heading.
        let title: String
        /// Never empty, newest first.
        let rows: [Row]
    }

    /// One workout, one button. To VoiceOver its label is `name` and its value `spokenValue`.
    struct Row: Equatable, Sendable, Identifiable {
        let id: WorkoutID
        /// The workout's name, as stored.
        let name: String
        /// "Wed · 58 min · 24,180 lb".
        let meta: String
        /// "1 PR", "3 PRs"; nil when the workout holds no record.
        let badge: String?
        /// "Wednesday, 58 minutes, 24,180 pounds, 1 PR": the meta's parts in words, then the badge.
        let spokenValue: String
        /// Opens the workout's detail.
        let route: HistoryRoute
    }

    struct Empty: Equatable, Sendable {
        let title: String
        let body: String
        let actionTitle: String
        let route: HistoryRoute
    }
}
