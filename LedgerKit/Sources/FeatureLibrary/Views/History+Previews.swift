#if DEBUG
    import LedgerDomain
    import LedgerFakes
    import SwiftUI

    /// The previews of an exercise's history, one case each, drawn from the model the presentation makes of a
    /// fixed input: Barbell Bench Press over `Fixtures.history(weeks: 8)`, its records detected as the store reads
    /// them. `PreviewTests` render every case; the snapshot and accessibility tests draw the same pages.
    enum HistoryPreview: String, CaseIterable {
        case logged = "Exercise history"
        /// Criterion 5: no session in W3 and W6.
        case gaps = "Exercise history, two weeks off"
        case noData = "Exercise history, never logged"
        case kilograms = "Exercise history in kilograms"

        func model() throws -> ExerciseHistoryModel {
            try ExerciseHistoryPresentation.make(HistoryPreviewData.input(for: self))
        }

        @ViewBuilder var content: some View {
            // `try?`: the fixture's own error is of no use to a preview.
            if let model = try? model() {
                NavigationStack {
                    ExerciseHistoryScreen(model: model) { _ in }
                }
            }
        }
    }

    nonisolated enum HistoryPreviewData {
        static let bench = "Barbell Bench Press"

        /// The preview's exercise is not among the fixture's.
        struct Missing: Error {}

        static func input(for preview: HistoryPreview) throws -> ExerciseHistoryInput {
            let exercise = try LibraryPreviewData.exercises().first { $0.name == bench }
            guard let exercise else {
                throw Missing()
            }
            let skipped = [
                Fixtures.date(2026, 8, 10) ..< Fixtures.date(2026, 8, 17),
                Fixtures.date(2026, 8, 31) ..< Fixtures.date(2026, 9, 7)
            ]
            let workouts = preview == .noData ? [] : try Fixtures.history(weeks: 8).filter { workout in
                preview != .gaps || !skipped.contains { $0.contains(workout.startedAt) }
            }
            var bests = PersonalRecords.Bests()
            var records: Set<WorkoutID> = []
            for workout in workouts {
                let found = PersonalRecords.detect(workout: workout, against: bests, now: workout.startedAt)
                if found.contains(where: { $0.exerciseID == exercise.id }) {
                    records.insert(workout.id)
                }
                bests.include(workout)
            }
            let sessions = workouts.reversed().compactMap { workout in
                let sets = workout.exercises.filter { $0.exerciseID == exercise.id }.flatMap(\.sets).filter(\.isDone)
                return sets.isEmpty
                    ? nil : ExerciseSession(workoutID: workout.id, startedAt: workout.startedAt, sets: sets)
            }
            return ExerciseHistoryInput(
                exercise: exercise,
                sessions: sessions,
                records: records,
                units: preview == .kilograms ? .kg : .lb,
                weekStart: .monday,
                now: Fixtures.now,
                calendar: Fixtures.calendar,
                locale: Fixtures.locale
            )
        }
    }

    #Preview("Exercise history") {
        HistoryPreview.logged.content
    }

    #Preview("Exercise history, two weeks off") {
        HistoryPreview.gaps.content
    }

    #Preview("Exercise history, never logged") {
        HistoryPreview.noData.content
    }

    #Preview("Exercise history in kilograms") {
        HistoryPreview.kilograms.content
    }
#endif
