import LedgerDesign
import SwiftUI

/// Everything the edit sheet scrolls, and never a scroll view: each exercise's name, a heading (N15), over a weight and
/// a reps stepper for each of its logged sets, or over "Nothing logged". VoiceOver reads each stepper as one adjustable
/// element, "Set 2 weight, 185 pounds"; at accessibility sizes `StepperField` stands its buttons under its words.
struct EditSetsPage: View {
    let model: EditSetsModel
    let send: (EditSetsAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xl) {
            ForEach(model.exercises) { exercise in
                VStack(alignment: .leading, spacing: LedgerSpacing.m) {
                    Text(exercise.name)
                        .ledgerFont(.subheading)
                        .foregroundStyle(LedgerColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let nothingLogged = exercise.nothingLogged {
                        Text(nothingLogged)
                            .ledgerFont(.bodyLight)
                            .foregroundStyle(LedgerColor.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(exercise.sets) { set in
                        HairlineRule()
                        stepper(set.weight)
                        stepper(set.reps)
                    }
                }
            }
        }
        .padding(.vertical, LedgerSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepper(_ field: EditSetsModel.Field) -> some View {
        StepperField(
            field.label,
            value: field.value,
            spokenValue: field.spokenValue,
            onDecrement: field.decrement.map { action in { send(action) } },
            onIncrement: field.increment.map { action in { send(action) } }
        )
    }
}
