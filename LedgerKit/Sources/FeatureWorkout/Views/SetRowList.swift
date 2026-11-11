import LedgerDesign
import SwiftUI

/// The exercise's sets (v2 set rows): the column headings, one `SetRow` per set, and the two steppers under
/// the shown row. A tap on a row's body selects it; its check logs the set, or un-logs it once logged; a
/// stepper changes the shown row by the exercise's step, or by one rep.
///
/// VoiceOver reads each row as the design system's set row does: the row, then its check; and each stepper
/// as one adjustable stop whose value is the row's weight or reps.
///
/// Each row names its own exercise, so a superset's block (F10 S9) draws its members' rows in one list.
struct SetRowList: View {
    let rows: [SetRowModel]
    let columns: ExerciseCardModel.Columns
    let steppers: SteppersModel?
    let send: (WorkoutEdit) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SetRowHeader(number: columns.number, weight: columns.weight, reps: columns.reps)
            HairlineList {
                ForEach(rows) { row in
                    SetRow(
                        number: row.label,
                        weight: row.weight,
                        reps: row.reps,
                        state: row.state,
                        checkLabel: row.checkLabel,
                        accessibilitySummary: row.summary,
                        onSelect: { send(.select(exerciseIndex: row.exerciseIndex, setID: row.id)) },
                        onCheck: { send(row.check) }
                    )
                    if let steppers, steppers.setID == row.id {
                        SetRowSteppers(
                            weightStep: steppers.weightStep,
                            repStep: steppers.repStep,
                            weight: steppers.weight,
                            reps: steppers.reps,
                            onWeight: { send(.stepWeight(exerciseIndex: steppers.exerciseIndex, setID: row.id, $0)) },
                            onReps: { send(.stepReps(exerciseIndex: steppers.exerciseIndex, setID: row.id, $0)) }
                        )
                    }
                }
            }
        }
    }
}
