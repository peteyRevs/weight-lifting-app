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
    @State private var position = ScrollPosition(edge: .top)

    var body: some View {
        SheetChrome(model.title, cancel: model.cancel, cancelIdentifier: "library.create.cancel", onCancel: onCancel) {
            ScrollView {
                CreateExercisePage(model: model, send: send)
            }
            .scrollPosition($position)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            // A problem of the name is shown at the top, under the field: scrolled there when Save finds one, which at
            // large text sizes is many screens up (finding S3-6).
            .onChange(of: model.problemNumber) {
                if model.name.problem != nil {
                    position.scrollTo(edge: .top)
                }
            }
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
///
/// **Drawn whole (F15-S2-11), as Program's `NameField`.** A one-line field cuts a name longer than its line, and at
/// the accessibility sizes an ordinary name is longer ("Landmine Squ…"). So while the field has no focus its own
/// text is concealed, and the name is drawn as text that wraps onto as many lines as it needs, with the field over
/// its first line. With the focus the field draws its text itself, on its one line, and the box is one line high.
/// An empty name shows the field's placeholder; a name of only spaces shows it too, drawn here under the field, with
/// the focus and without it (`CreateExerciseModel.Name.showsPlaceholderOverBlank`). The field is the one thing
/// VoiceOver reads; the drawn text and the drawn placeholder are hidden from it.
struct CreateExerciseNameField: View {
    let model: CreateExerciseModel.Name
    let send: (CreateExerciseAction) -> Void
    @FocusState private var isEditing: Bool

    /// The placeholder's colour, the field's prompt and the one drawn over a blank name alike (as `NameField`'s).
    private static var placeholderColor: Color {
        LedgerColor.inkFaint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
            Eyebrow(model.label)
            box
            if let problem = model.problem {
                Text(problem)
                    .ledgerFont(.caption)
                    .foregroundStyle(LedgerColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The outlined box: the name drawn whole, the field over its first line.
    private var box: some View {
        ZStack(alignment: .topLeading) {
            // The label on one unseen line of no width: an empty name keeps the field's one line.
            Text(model.label)
                .ledgerFont(.body)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 0, alignment: .leading)
                .hidden()
            if model.showsPlaceholderOverBlank {
                Text(model.label)
                    .ledgerFont(.body)
                    // The colour of the field's own prompt, so a blank name reads as an empty one.
                    .foregroundStyle(Self.placeholderColor)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Text(model.text)
                .ledgerFont(.body)
                .foregroundStyle(isEditing ? LedgerColor.inkConcealed : LedgerColor.ink)
                .multilineTextAlignment(.leading)
                // With the focus the text keeps to one line, as the field over it does, and is not drawn.
                .fixedSize(horizontal: isEditing, vertical: false)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
        .overlay(alignment: .topLeading) {
            TextField(text: binding, prompt: Text(model.label).foregroundStyle(Self.placeholderColor)) {
                Text(model.label)
            }
            .ledgerFieldFont(.body)
            .multilineTextAlignment(strategy: .layoutBased)
            // Concealed ink while unfocused, never a clear colour: the audit reads the field's text colour.
            .foregroundStyle(isEditing ? LedgerColor.ink : LedgerColor.inkConcealed)
            .submitLabel(.done)
            .focused($isEditing)
            .accessibilityIdentifier("library.create.name")
        }
        .padding(.horizontal, LedgerSpacing.m)
        .padding(.vertical, LedgerSpacing.s)
        .ledgerHitTarget(alignment: .leading)
        .onTapGesture { isEditing = true }
        .background {
            RoundedRectangle(cornerRadius: LedgerRadius.row)
                .strokeBorder(LedgerColor.hairlineStrong, lineWidth: LedgerHairline.width)
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
