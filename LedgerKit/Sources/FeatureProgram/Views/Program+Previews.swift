#if DEBUG
    import LedgerDomain
    import LedgerFakes
    import SwiftUI

    /// Every preview in FeatureProgram, one case each: the states of the builder and of the exercise library
    /// sheet. Each is drawn from the model its presentation makes of a fixed input, so a preview shows the
    /// words the app would. `PreviewTests` render every case and fail on a `#Preview` that is not a case here;
    /// the snapshot and accessibility tests draw the same states' pages. None runs a task: the screens only
    /// draw.
    ///
    /// The program is spec §6.4's (`Fixtures.seedProgram()`), the exercises the bundled catalog's.
    enum ProgramPreview: String, CaseIterable {
        case builder = "Program builder"
        case deloadWeek = "Deload week selected"
        /// A day just added and scheduled on Tuesday, with the notice that it has no exercise yet.
        case emptyDay = "A day with no exercise"
        /// "−" on a block of two weeks.
        case twoWeeks = "Two weeks, minus refused"
        case sixteenWeeks = "Sixteen weeks and a long name"
        /// Back and Cable chosen; the day being edited is Upper A, which holds one of the eight.
        case library = "Exercise library"
        case libraryPicked = "Three exercises picked"
        case libraryNothing = "Nothing matches"

        /// What a case draws: one of the two screens, with its model.
        enum Subject {
            case builder(ProgramBuilderModel)
            case library(ExercisePickerModel)
        }

        /// The model of the case, on its screen.
        func subject() throws -> Subject {
            switch self {
            case .builder, .deloadWeek, .emptyDay, .twoWeeks, .sixteenWeeks:
                try .builder(ProgramPresentation.make(ProgramPreviewData.builderInput(for: self)))
            case .library, .libraryPicked, .libraryNothing:
                try .library(ExercisePickerPresentation.make(ProgramPreviewData.libraryInput(for: self)))
            }
        }

        /// The screen in this state. A fixture that does not build draws nothing, and fails `PreviewTests`,
        /// which asks each case for its subject.
        @ViewBuilder var content: some View {
            // `try?`: the fixture's own error is of no use to a preview.
            switch try? subject() {
            case let .builder(model): ProgramScreen(model: model) { _ in }
            case let .library(model): ExercisePickerScreen(model: model) { _ in }
            case nil: EmptyView()
            }
        }
    }

    /// The fixed inputs of the previews.
    nonisolated enum ProgramPreviewData {
        static let longName = "Upper / Lower with an accessory day, autumn block before the meet"

        static func builderInput(for preview: ProgramPreview) throws -> ProgramBuilderInput {
            var input = try ProgramBuilderInput(
                program: Fixtures.seedProgram(),
                exercises: Dictionary(ExerciseCatalog.seed().map { ($0.id, $0) }) { first, _ in first },
                settings: Fixtures.settingsLb,
                selectedWeek: 0,
                calendar: Fixtures.calendar,
                locale: Fixtures.locale
            )
            switch preview {
            case .deloadWeek:
                input.selectedWeek = 7
            case .emptyDay:
                let day = DayTemplateID(Fixtures.uuid(900))
                try apply([
                    .addDay(day, name: ProgramCopy.newDay),
                    .setSchedule(week: 0, weekday: .tuesday, day: day)
                ], to: &input)
                input.notice = .dayHasNoExercises
            case .twoWeeks:
                try apply(Array(repeating: .removeLastWeek(loggedWeeks: []), count: 6), to: &input)
                input.notice = .minimumTwoWeeks
            case .sixteenWeeks:
                try apply((0 ..< 8).map { .addWeek(WeekID(Fixtures.uuid(900 + $0))) }, to: &input)
                try apply([.renameProgram(longName)], to: &input)
                input.selectedWeek = 11
            case .builder, .library, .libraryPicked, .libraryNothing:
                break
            }
            return input
        }

        private static func apply(_ edits: [ProgramBuilderEdit], to input: inout ProgramBuilderInput) throws {
            for edit in edits {
                input.program = try edit.applied(to: input.program)
            }
        }

        static func libraryInput(for preview: ProgramPreview) throws -> ExercisePickerInput {
            let exercises = try ExerciseCatalog.seed()
            // The list is in `ExerciseSearch`'s order, so the picks are the second, the fourth and the first
            // of the eight rows: picked in an order that is not the list's.
            let shown = ExerciseSearch.filtered(exercises, query: "", muscle: .back, equipment: .cable)
            let picks = [1, 3, 0].compactMap { shown.indices.contains($0) ? shown[$0].id : nil }
            return try ExercisePickerInput(
                exercises: exercises,
                dayExercises: Set(Fixtures.seedProgram().days.first?.slots.map(\.exerciseID) ?? []),
                query: preview == .libraryNothing ? "zzz" : "",
                muscle: .back,
                equipment: .cable,
                picks: preview == .libraryPicked ? picks : [],
                locale: Fixtures.locale
            )
        }
    }

    #Preview("Program builder") {
        ProgramPreview.builder.content
    }

    #Preview("Deload week selected") {
        ProgramPreview.deloadWeek.content
    }

    #Preview("A day with no exercise") {
        ProgramPreview.emptyDay.content
    }

    #Preview("Two weeks, minus refused") {
        ProgramPreview.twoWeeks.content
    }

    #Preview("Sixteen weeks and a long name") {
        ProgramPreview.sixteenWeeks.content
    }

    #Preview("Exercise library") {
        ProgramPreview.library.content
    }

    #Preview("Three exercises picked") {
        ProgramPreview.libraryPicked.content
    }

    #Preview("Nothing matches") {
        ProgramPreview.libraryNothing.content
    }

#endif
