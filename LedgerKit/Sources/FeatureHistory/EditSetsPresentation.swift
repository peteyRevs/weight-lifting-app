import Foundation
import LedgerDomain

/// What `EditSetsPresentation.make(_:)` reads: the draft, the lifter's units and locale, and where a save stands.
nonisolated struct EditSetsInput: Sendable {
    var draft: WorkoutState
    /// Every weight is drawn and stepped in these (F13 question 5, built to A).
    var units: Units
    var locale: Locale
    var hasChanges: Bool
    var isSaving: Bool
    var saveFailed: Bool
    var workoutGone: Bool
}

/// The edit sheet as words (F13 S3, criterion 4 as C10, C11, C14 and Q2–Q5 restate it): every exercise of the workout,
/// each with a weight and a reps stepper for each logged set. A set is numbered among the logged sets of its exercise,
/// as the receipt's chips count them. Which steps are on is the Domain's (`SetEditing.canStep`).
nonisolated enum EditSetsPresentation {
    static func make(_ input: EditSetsInput) -> EditSetsModel {
        EditSetsModel(
            title: HistoryCopy.editSetsTitle,
            cancel: HistoryCopy.cancel,
            exercises: input.draft.exercises.map { exercise($0, input) },
            foot: EditSetsModel.Foot(
                problem: input.saveFailed ? HistoryCopy.saveFailed : nil,
                save: HistoryCopy.save,
                action: input.hasChanges && !input.isSaving ? .save : nil
            ),
            isEnabled: !input.isSaving,
            workoutGone: input.workoutGone
                ? EditSetsModel.WorkoutGone(
                    title: HistoryCopy.workoutGoneTitle,
                    message: HistoryCopy.workoutGoneBody,
                    okay: HistoryCopy.okay
                )
                : nil
        )
    }

    private static func exercise(_ exercise: WorkoutExercise, _ input: EditSetsInput) -> EditSetsModel.Exercise {
        let logged = SetEditing.editable(exercise)
        return EditSetsModel.Exercise(
            id: exercise.id,
            name: exercise.name,
            nothingLogged: logged.isEmpty ? HistoryCopy.spokenNothingLogged : nil,
            sets: logged.enumerated().map { place, set in
                row(set, number: place + 1, input)
            }
        )
    }

    private static func row(_ set: LoggedSet, number: Int, _ input: EditSetsInput) -> EditSetsModel.SetRow {
        let (units, locale) = (input.units, input.locale)
        let reps = IntegerFormatStyle<Int>(locale: locale).format(set.reps.value)
        return EditSetsModel.SetRow(
            id: set.id,
            weight: field(
                set,
                .weight,
                label: HistoryCopy.setWeight(number, locale: locale),
                value: HistoryCopy.volume(set.weight.formatted(in: units), units: units, locale: locale),
                spokenValue: set.weight.spoken(in: units, locale: locale.forCountedText)
            ),
            reps: field(
                set,
                .reps,
                label: HistoryCopy.setReps(number, locale: locale),
                value: reps,
                spokenValue: reps
            )
        )
    }

    private static func field(
        _ set: LoggedSet,
        _ field: SetEditing.Field,
        label: String,
        value: String,
        spokenValue: String
    ) -> EditSetsModel.Field {
        let action = { (direction: StepDirection) -> EditSetsAction? in
            SetEditing.canStep(set, field, direction) ? .step(set.id, field, direction) : nil
        }
        return EditSetsModel.Field(
            label: label,
            value: value,
            spokenValue: spokenValue,
            decrement: action(.downward),
            increment: action(.upward)
        )
    }
}
