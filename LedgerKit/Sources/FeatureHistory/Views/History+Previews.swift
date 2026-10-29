#if DEBUG
    import Foundation
    import LedgerDomain
    import LedgerFakes
    import SwiftUI

    /// Every preview in FeatureHistory, one case each: the states of the History list. Each is drawn from the model
    /// its presentation makes of a fixed input, so a preview shows the words the app would. `PreviewTests` render
    /// every case and fail on a `#Preview` that is not a case here; the snapshot and accessibility tests draw the same
    /// states' pages. None runs a task: the screen only draws.
    ///
    /// The workouts are the previews' history, `Seed.preview()`'s (`Fixtures.history`), over four weeks so the page
    /// stays a screenful or two, each holding the records `PersonalRecords.detect` finds in it.
    enum HistoryPreview: String, CaseIterable {
        case populated = "History"
        /// Criterion 7: the volumes in kilograms.
        case kilograms = "History in kilograms"
        /// No workout yet (F13 question 7, built to A).
        case empty = "No workouts yet"

        func model() throws -> HistoryModel {
            try HistoryPresentation.make(HistoryPreviewData.input(for: self))
        }

        /// The screen in this state. A fixture that does not build draws nothing, and fails `PreviewTests`.
        @ViewBuilder var content: some View {
            // `try?`: the fixture's own error is of no use to a preview.
            if let model = try? model() {
                HistoryScreen(model: model) { _ in }
            }
        }
    }

    /// The fixed inputs of the previews.
    nonisolated enum HistoryPreviewData {
        static func input(for preview: HistoryPreview) throws -> HistoryInput {
            try HistoryInput(
                entries: preview == .empty ? [] : entries(Fixtures.history(weeks: 4)),
                units: preview == .kilograms ? .kg : .lb,
                weekStart: Fixtures.settingsLb.weekStart,
                now: Fixtures.now,
                calendar: Fixtures.calendar,
                locale: Fixtures.locale
            )
        }

        /// `workouts` (oldest first) as the History list's entries, newest first, each with the records it set
        /// against the workouts before it (product decision #27).
        static func entries(_ workouts: [WorkoutState]) -> [HistoryEntry] {
            var bests = PersonalRecords.Bests()
            var entries: [HistoryEntry] = []
            for workout in workouts {
                let records = PersonalRecords.detect(workout: workout, against: bests, now: workout.startedAt)
                entries.append(HistoryEntry(workout, prCount: records.count))
                bests.include(workout)
            }
            return entries.reversed()
        }
    }

    #Preview("History") {
        HistoryPreview.populated.content
    }

    #Preview("History in kilograms") {
        HistoryPreview.kilograms.content
    }

    #Preview("No workouts yet") {
        HistoryPreview.empty.content
    }
#endif
