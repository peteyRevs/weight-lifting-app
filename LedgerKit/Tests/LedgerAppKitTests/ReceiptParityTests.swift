#if DEBUG
    @testable import FeatureHistory
    @testable import FeatureWorkout
    import Foundation
    import LedgerDomain
    import LedgerTestSupport
    import Testing

    /// F13 S2, N13 (ruling A3): FeatureHistory builds F10's receipt with its own copy of the keys, so for the same
    /// finished workout, records and units the two must say the same thing. A past workout's detail, in the lifter's
    /// units when those are the workout's, equals the receipt F10's cover showed after the save: the day and the name
    /// over it, every tile, the records line and every row, string for string, and each row opens the same exercise.
    /// The workouts are both features' previews: F10's receipts (one with a record, one past an hour, one in
    /// kilograms) and History's (the newest of the previews' history, with its records, and the oldest, with none).
    @Suite("Receipt parity (F10 and F13)")
    struct ReceiptParityTests {
        /// Each workout with its records, as both features' previews hold them.
        static func workouts() throws -> [(name: String, recorded: RecordedWorkout)] {
            let receipts = ReceiptPreview.allCases.compactMap { preview in
                preview.finished
                    .map { (preview.rawValue, RecordedWorkout(workout: $0, records: preview.records(of: $0))) }
            }
            let details = try [DetailPreview.withRecords, .noRecords].map { preview in
                try (preview.rawValue, DetailPreviewData.input(for: preview).recorded)
            }
            try #require(receipts.count == ReceiptPreview.allCases.count, "an F10 preview did not build")
            return receipts + details
        }

        @Test("For the same workout, records and units, the detail's receipt is F10's, string for string")
        func detail_isTheReceipt() throws {
            for (name, recorded) in try Self.workouts() {
                let workout = recorded.workout
                let receipt = WorkoutPresentation.receipt(
                    workout,
                    records: recorded.records,
                    locale: Fixtures.locale,
                    calendar: Fixtures.calendar
                )
                let detail = WorkoutDetailPresentation.make(WorkoutDetailInput(
                    recorded: recorded,
                    units: workout.units,
                    calendar: Fixtures.calendar,
                    locale: Fixtures.locale
                ))
                let isTheSamePage = detail.receipt == receipt.page
                #expect(isTheSamePage, "\(name): the tiles, the records line and the rows")
                #expect(detail.date == receipt.header.date && detail.title == receipt.header.title, "\(name)")
                let opensTheSame = detail.rowRoutes.map(Self.exercise(of:)) == receipt.rowActions
                    .map(Self.exercise(of:))
                #expect(opensTheSame, "\(name): each row opens the same exercise")
            }
        }

        static func exercise(of route: HistoryRoute) -> ExerciseID? {
            if case let .exercise(id) = route {
                return id
            }
            return nil
        }

        static func exercise(of action: WorkoutAction) -> ExerciseID? {
            if case let .openExercise(id) = action {
                return id
            }
            return nil
        }

        @Test("The parity covers a record, a workout past an hour, kilograms and a workout with none")
        func workouts_coverWhatTheReceiptShows() throws {
            let workouts = try Self.workouts().map(\.recorded)
            #expect(workouts.contains { !$0.records.isEmpty })
            #expect(workouts.contains { $0.records.isEmpty })
            #expect(workouts.contains { $0.workout.units == .kg })
            #expect(workouts.contains { ($0.workout.endedAt?.timeIntervalSince($0.workout.startedAt) ?? 0) > 3600 })
        }
    }
#endif
