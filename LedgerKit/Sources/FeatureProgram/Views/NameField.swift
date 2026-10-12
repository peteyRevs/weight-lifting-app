import LedgerDesign
import SwiftUI

/// A name the lifter edits in place, in the screen title's type: the day's name on the Day editor. (The
/// builder's `ProgramHeader` still holds its own one-line field; it takes this one in a queued chore.)
///
/// **A draft, not the stored name.** The stored name is the cleaned one, so a field bound to it would lose a
/// trailing space while the lifter types and could not be emptied. The draft starts as the stored name; each
/// change that leaves it other than the stored name is handed to `onRename` as typed; when the field loses
/// focus, and whenever the stored name changes while it has none, the draft takes the stored name again (a
/// name typed blank goes back to the one that is stored).
///
/// **Drawn whole.** The field is one line: a field of several lines is a text view, which the hosted
/// accessibility reader cannot read (testing-strategy §2.6, the known limit). A one-line field cuts a name
/// longer than its line, and at larger text sizes a day's ordinary name is longer. So while the field has no
/// focus its own text is not drawn, and the draft is drawn as text that wraps onto as many lines as it
/// needs. The field stands over that text's first line, top on top, so that the name stays where it is when
/// the focus comes or goes (measured: the field draws its line 0.7 pt higher than the text at the default
/// size and 1 pt higher at `.accessibility3`, and nothing moves sideways). With the focus the field draws its text
/// itself, on its one line, which scrolls
/// sideways under the caret as every field's does, and what stands under the name moves up to that line.
/// An empty draft shows the field's placeholder.
///
/// The field is the one thing VoiceOver reads, under `label`, which is its placeholder too; the drawn text
/// is hidden from it. The name's target is at least 44 pt high, with the name at its top whether it is one
/// line or several; a tap anywhere on it, on the further lines too, puts the cursor in the field.
struct NameField: View {
    let label: String
    let name: String
    let onRename: (String) -> Void
    @State private var draft: String
    @FocusState private var isEditing: Bool

    init(label: String, name: String, onRename: @escaping (String) -> Void) {
        self.label = label
        self.name = name
        self.onRename = onRename
        _draft = State(initialValue: name)
    }

    var body: some View {
        Text(draft)
            .ledgerFont(.title)
            .foregroundStyle(isEditing ? Color.clear : LedgerColor.ink)
            .multilineTextAlignment(.leading)
            // With the focus the text keeps to one line, as the field over it does, and is not drawn; a line
            // longer than the screen runs out of the frame, which keeps the width it is given.
            .fixedSize(horizontal: isEditing, vertical: false)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
            .overlay(alignment: .topLeading) {
                TextField(label, text: $draft)
                    .ledgerFont(.title)
                    .foregroundStyle(isEditing ? LedgerColor.ink : Color.clear)
                    .submitLabel(.done)
                    .focused($isEditing)
                    .accessibilityLabel(label)
            }
            .ledgerHitTarget(alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture { isEditing = true }
            .onChange(of: draft) { _, text in
                if text != name {
                    onRename(text)
                }
            }
            .onChange(of: isEditing) { _, isEditing in
                if !isEditing {
                    draft = name
                }
            }
            .onChange(of: name) { _, name in
                if !isEditing {
                    draft = name
                }
            }
    }
}
