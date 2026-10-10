import LedgerDesign
import SwiftUI

/// The exercise's sets (v2 set rows): the column headings, one `SetRow` per set, and the two steppers under
/// the shown row. A tap on a row's body selects it; its check logs the set, or un-logs it once logged; a
/// stepper changes the shown row by the exercise's step, or by one rep.
///
/// VoiceOver reads each row as the design system's set row does: the row, then its check; and each stepper
/// as one adjustable stop whose value is the row's weight or reps.
struct SetRowList: View {
    let model: ExerciseCardModel
    let send: (WorkoutEdit) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SetRowHeader(number: model.columns.number, weight: model.columns.weight, reps: model.columns.reps)
            HairlineList {
                ForEach(model.rows) { row in
                    SetRow(
                        number: row.label,
                        weight: row.weight,
                        reps: row.reps,
                        state: row.state,
                        checkLabel: row.checkLabel,
                        accessibilitySummary: row.summary,
                        onSelect: { send(.select(exerciseIndex: model.exerciseIndex, setID: row.id)) },
                        onCheck: { send(row.check) }
                    )
                    if let steppers = model.steppers, steppers.setID == row.id {
                        SetRowSteppers(
                            weightStep: steppers.weightStep,
                            repStep: steppers.repStep,
                            weight: steppers.weight,
                            reps: steppers.reps,
                            onWeight: { send(.stepWeight(exerciseIndex: model.exerciseIndex, setID: row.id, $0)) },
                            onReps: { send(.stepReps(exerciseIndex: model.exerciseIndex, setID: row.id, $0)) }
                        )
                    }
                }
            }
        }
    }
}
