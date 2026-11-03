#if DEBUG
    import Foundation
    import LedgerDomain
    import LedgerFakes
    import SwiftUI

    /// Every preview of a past workout's detail, one case each, drawn from the model its presentation makes of a fixed
    /// input, so a preview shows the words the app would. `PreviewTests` render every case and fail on a `#Preview`
    /// that is not a case here; the snapshot, accessibility and layout tests draw the same states' pages. None runs a
    /// task: the screen only draws.
    ///
    /// The workouts are the previews' history (`Fixtures.history(weeks: 4)`), each with the records
    /// `PersonalRecords.detect` finds in it against those before it: the newest holds records, the oldest none.
    enum DetailPreview: String, CaseIterable {
        case withRecords = "Workout detail"
        /// A first workout: every set a baseline, so no record and no records line.
        case noRecords = "Workout detail, no records"
        /// Criterion 7: the same workout in kilograms (F13 question 5, built to A).
        case kilograms = "Workout detail in kilograms"
        /// N10: a workout that can't be read.
        case unreadable = "Workout that can't be read"

        func model() throws -> WorkoutDetailModel {
            try WorkoutDetailPresentation.make(DetailPreviewData.input(for: self))
        }

        /// The screen in this state. A fixture that does not build draws nothing, and fails `PreviewTests`.
        @ViewBuilder var content: some View {
            if self == .unreadable {
                UnreadableWorkout(model: WorkoutDetailPresentation.unreadable) {}
            } else if let model = try? model() {
                // `try?`: the fixture's own error is of no use to a preview.
                WorkoutDetailScreen(model: model, send: { _ in }, onDelete: {})
            }
        }
    }

    /// The fixed inputs of the previews.
    nonisolated enum DetailPreviewData {
        static func input(for preview: DetailPreview) throws -> WorkoutDetailInput {
            let history = try HistoryPreviewData.recorded(Fixtures.history(weeks: 4))
            guard let recorded = preview == .noRecords ? history.first : history.last else {
                throw NoHistory()
            }
            return WorkoutDetailInput(
                recorded: recorded,
                units: preview == .kilograms ? .kg : .lb,
                calendar: Fixtures.calendar,
                locale: Fixtures.locale
            )
        }

        /// The previews' history held no workout.
        struct NoHistory: Error {}
    }

    #Preview("Workout detail") {
        DetailPreview.withRecords.content
    }

    #Preview("Workout detail, no records") {
        DetailPreview.noRecords.content
    }

    #Preview("Workout detail in kilograms") {
        DetailPreview.kilograms.content
    }

    #Preview("Workout that can't be read") {
        DetailPreview.unreadable.content
    }
#endif
