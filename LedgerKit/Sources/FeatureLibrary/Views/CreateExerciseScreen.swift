import LedgerDesign
import SwiftUI

/// The exercise sheet, drawn from its model and nothing else (F12 S3). A sheet whose content scrolls is a screen that
/// scrolls (the M1 convention): pinned are `SheetChrome`'s title and "Cancel" and, at the foot, "Save"; what scrolls
/// between them is `CreateExercisePage`, the name and the four fields of chips, which wrap onto many lines at large
/// text sizes. That is its one layout at every text size. A drag on the fields puts the keyboard away.
struct CreateExerciseScreen: View {
    let model: CreateExerciseModel
    let send: (CreateExerciseAction) -> Void
    let onCancel: () -> Void

    var body: some View {
        SheetChrome(model.title, cancel: model.cancel, cancelIdentifier: "library.create.cancel", onCancel: onCancel) {
            ScrollView {
                CreateExercisePage(model: model, send: send)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            CreateExerciseFoot(model: model.foot, send: send)
        }
    }
}

/// Everything the sheet scrolls, and never a scroll view: the name, then equipment, the primary muscle, the
/// secondary muscles and the movement pattern, each under its heading. The secondary muscles are switches to
/// VoiceOver; every other chip is selected while chosen.
struct CreateExercisePage: View {
    let model: CreateExerciseModel
    let send: (CreateExerciseAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xl) {
            CreateExerciseNameField(model: model.name, send: send)
            ForEach(model.groups) { group in
                VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                    Eyebrow(group.title)
                    FilterChipRow(
                        group.chips,
                        title: \.title,
                        spokenLabel: \.spokenLabel,
                        isSelected: \.isSelected,
                        allowsMany: group.allowsMany
                    ) { chip in
                        send(chip.action)
                    }
                }
            }
        }
        .padding(.vertical, LedgerSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The name: its heading over a one-line field in an outlined box, at least 44 pt high, whose placeholder and spoken
/// label are the heading's word; then the rule Save found it breaks. Each change is handed on as typed.
struct CreateExerciseNameField: View {
    let model: CreateExerciseModel.Name
    let send: (CreateExerciseAction) -> Void
    @FocusState private var isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
            Eyebrow(model.label)
            TextField(text: binding, prompt: Text(model.label).foregroundStyle(LedgerColor.inkFaint)) {
                Text(model.label)
            }
            .ledgerFieldFont(.body)
            .foregroundStyle(LedgerColor.ink)
            .submitLabel(.done)
            .focused($isEditing)
            .accessibilityIdentifier("library.create.name")
            .padding(.horizontal, LedgerSpacing.m)
            .padding(.vertical, LedgerSpacing.s)
            .ledgerHitTarget(alignment: .leading)
            .onTapGesture { isEditing = true }
            .background {
                RoundedRectangle(cornerRadius: LedgerRadius.row)
                    .strokeBorder(LedgerColor.hairlineStrong, lineWidth: LedgerHairline.width)
            }
            if let problem = model.problem {
                Text(problem)
                    .ledgerFont(.caption)
                    .foregroundStyle(LedgerColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The text as given, and a text that differs from it handed on as typed.
    private var binding: Binding<String> {
        Binding { model.text } set: {
            if $0 != model.text {
                send(.setName($0))
            }
        }
    }
}

/// The sheet's foot, pinned under the fields: a rule, the line of a save that failed, and "Save", the sheet's one use
/// of the accent. While a save runs the button is disabled.
struct CreateExerciseFoot: View {
    let model: CreateExerciseModel.Foot
    let send: (CreateExerciseAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.m) {
            HairlineRule()
            if let problem = model.problem {
                Text(problem)
                    .ledgerFont(.caption)
                    .foregroundStyle(LedgerColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PrimaryButton(model.title) {
                if let action = model.action {
                    send(action)
                }
            }
            .disabled(model.action == nil)
            .accessibilityIdentifier("library.create.save")
        }
    }
}
