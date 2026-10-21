#if DEBUG
    import LedgerDomain
    import LedgerFakes
    import SwiftUI

    /// Every preview in FeatureLibrary, one case each: the states of the Library. Each is drawn from the model its
    /// presentation makes of a fixed input, so a preview shows the words the app would. `PreviewTests` render
    /// every case and fail on a `#Preview` that is not a case here; the snapshot and accessibility tests draw the
    /// same states' pages. None runs a task: the screen only draws.
    ///
    /// The exercises are the seed program's (`Fixtures.seedProgram()`), the catalog's two chest-supported rows and
    /// one of the lifter's own, so the page stays a screenful or two; the history is `Fixtures.history(weeks: 8)`.
    enum LibraryPreview: String, CaseIterable {
        case populated = "Library"
        /// Criterion 2's filter: "row", Back and Machine leave Chest-Supported Row alone.
        case filtered = "Row, Back and Machine"
        case emptySearch = "Nothing matches"
        /// No finished workout yet: no RECENTLY LOGGED, and every PR is "—".
        case noHistory = "No history yet"
        /// No exercise stored at all (Pete's question 8, A).
        case noExercises = "No exercises yet"

        func model() throws -> LibraryModel {
            try LibraryPresentation.make(LibraryPresentation.rows(LibraryPreviewData.input(for: self)), filter: filter)
        }

        var filter: LibraryFilter {
            switch self {
            case .filtered: LibraryFilter(query: "row", muscle: .back, equipment: .machine)
            case .emptySearch: LibraryFilter(query: "zzz")
            case .populated, .noHistory, .noExercises: LibraryFilter()
            }
        }

        /// The screen in this state. A fixture that does not build draws nothing, and fails `PreviewTests`.
        @ViewBuilder var content: some View {
            // `try?`: the fixture's own error is of no use to a preview.
            if let model = try? model() {
                LibraryScreen(model: model) { _ in }
            }
        }
    }

    /// The fixed inputs of the previews.
    nonisolated enum LibraryPreviewData {
        static let customName = "Landmine Squeeze Press"

        static func input(for preview: LibraryPreview) throws -> LibraryInput {
            let workouts = preview == .populated || preview == .filtered ? try Fixtures.history(weeks: 8) : []
            var bests = PersonalRecords.Bests()
            var recent: [ExerciseID] = []
            var sessions: [ExerciseID: Int] = [:]
            for workout in workouts.reversed() {
                bests.include(workout)
                for id in Set(workout.exercises.map(\.exerciseID)) {
                    sessions[id, default: 0] += 1
                }
                let ids = workout.exercises.map(\.exerciseID).sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
                recent += ids.filter { !recent.contains($0) }
            }
            return try LibraryInput(
                exercises: preview == .noExercises ? [] : exercises(),
                recent: Array(recent.prefix(5)),
                sessions: sessions,
                bestSets: Dictionary(sessions.keys.compactMap { id in
                    bests.bestSet(of: id).map { (id, BestSet(weight: $0.weight, reps: $0.reps)) }
                }) { first, _ in first },
                units: .lb,
                locale: Fixtures.locale
            )
        }

        /// The seed program's exercises, the two chest-supported rows, and one of the lifter's own.
        static func exercises() throws -> [Exercise] {
            let program = try Set(Fixtures.seedProgram().days.flatMap(\.slots).map(\.exerciseID))
            let catalog = try ExerciseCatalog.seed().filter {
                program.contains($0.id) || $0.name.hasPrefix("Chest-Supported")
            }
            let custom = Exercise(
                id: ExerciseID(Fixtures.uuid(901)),
                name: customName,
                shortName: customName,
                equipment: .barbell,
                primaryMuscle: .chest,
                secondaryMuscles: [.shoulders, .triceps],
                pattern: .horizontalPush,
                defaultStartLoad: [:],
                isCustom: true
            )
            return catalog + [custom]
        }
    }

    #Preview("Library") {
        LibraryPreview.populated.content
    }

    #Preview("Row, Back and Machine") {
        LibraryPreview.filtered.content
    }

    #Preview("Nothing matches") {
        LibraryPreview.emptySearch.content
    }

    #Preview("No history yet") {
        LibraryPreview.noHistory.content
    }

    #Preview("No exercises yet") {
        LibraryPreview.noExercises.content
    }
#endif
