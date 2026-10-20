#if DEBUG
    import Foundation
    import LedgerDomain
    import LedgerFakes
    import SwiftUI

    /// The previews of the receipt (F10 S7b), one case each, drawn from the model the presentation makes of a
    /// `WorkoutPreview`'s workout, finished at that case's moment. `PreviewTests` render every case and fail on
    /// a `#Preview` of the receipt that is not a case here; the references and the VoiceOver trees draw the
    /// same states.
    enum ReceiptPreview: String, CaseIterable {
        case withRecords = "Receipt, with a record"
        case noRecords = "Receipt, past an hour"
        case kilograms = "Receipt, in kilograms"

        /// The cover's state whose workout is saved.
        var workout: WorkoutPreview {
            switch self {
            case .withRecords: .minutes
            case .noRecords: .hour
            case .kilograms: .dropSet
            }
        }

        /// The workout, finished at the case's moment; nil when the fixture does not build, which fails
        /// `PreviewTests`.
        var finished: WorkoutState? {
            let end = workout.now
            return (try? workout.workout()).flatMap { live in
                let envelope = EventEnvelope(
                    event: .finished(endedAt: end),
                    workoutID: live.id,
                    device: live.originDevice,
                    seq: 1000,
                    wallClock: end
                )
                return WorkoutEngine.reduce(live, envelope).0
            }
        }

        /// The records the receipt shows: with a record, the first exercise's estimate beats a best of one
        /// pound; otherwise none.
        func records(of finished: WorkoutState) -> [PersonalRecord] {
            guard self == .withRecords, let first = finished.exercises.first else {
                return []
            }
            let bests = PersonalRecords.Bests(e1RM: [first.exerciseID: .pounds(1)])
            return PersonalRecords.detect(workout: finished, against: bests, now: finished.startedAt)
        }

        /// The receipt's model; nil when the fixture does not build.
        var model: ReceiptScreenModel? {
            finished.map { finished in
                WorkoutPresentation.receipt(
                    finished,
                    records: records(of: finished),
                    locale: Fixtures.locale,
                    calendar: Fixtures.calendar
                )
            }
        }

        @ViewBuilder var content: some View {
            if let model {
                WorkoutScreen(model: .receipt(model)) { _ in }
            }
        }
    }

    #Preview("Receipt, with a record") {
        ReceiptPreview.withRecords.content
    }

    #Preview("Receipt, past an hour") {
        ReceiptPreview.noRecords.content
    }

    #Preview("Receipt, in kilograms") {
        ReceiptPreview.kilograms.content
    }
#endif
