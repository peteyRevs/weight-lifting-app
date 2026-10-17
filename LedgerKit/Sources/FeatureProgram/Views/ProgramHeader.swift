import LedgerDesign
import SwiftUI

/// The top of the builder: "MY PROGRAM" over the program's name, which is a field in the screen title's type.
///
/// The field shows a draft, not the model's name: the stored name is the cleaned one, so a field bound to it
/// would lose a trailing space while the lifter types and could not be emptied. The draft starts as the
/// stored name; each change that leaves it other than the stored name is sent as typed; when the field loses
/// focus, and whenever the stored name changes while it has none, the draft takes the stored name again (a
/// name typed blank goes back to the one that is stored).
///
/// The field's target is 44 pt high: a tap beside its one line of text puts the cursor in it too.
///
/// The field is one line. A name longer than the line is cut at its end while it is not being edited, as
/// every one-line field does; a field of several lines is a text view, which the hosted accessibility reader
/// cannot read (testing-strategy §2.6, the known limit).
struct ProgramHeader: View {
    let model: ProgramBuilderModel.Header
    let send: (ProgramBuilderAction) -> Void
    @State private var draft: String
    @FocusState private var isEditing: Bool

    init(model: ProgramBuilderModel.Header, send: @escaping (ProgramBuilderAction) -> Void) {
        self.model = model
        self.send = send
        _draft = State(initialValue: model.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
            Eyebrow(model.eyebrow)
            TextField(model.namePlaceholder, text: $draft)
                .ledgerFont(.title)
                .foregroundStyle(LedgerColor.ink)
                .submitLabel(.done)
                .focused($isEditing)
                .ledgerHitTarget(alignment: .leading)
                .onTapGesture { isEditing = true }
                .accessibilityLabel(model.namePlaceholder)
        }
        .onChange(of: draft) { _, text in
            if text != model.name {
                send(.rename(text))
            }
        }
        .onChange(of: isEditing) { _, isEditing in
            if !isEditing {
                draft = model.name
            }
        }
        .onChange(of: model.name) { _, name in
            if !isEditing {
                draft = name
            }
        }
    }
}
