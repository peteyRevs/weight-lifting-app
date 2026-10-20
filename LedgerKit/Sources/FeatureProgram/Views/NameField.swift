import LedgerDesign
import SwiftUI

/// A name the lifter edits in place, in the screen title's type: the program's name on the builder and the
/// day's name on the Day editor.
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
/// needs. The field stands over that text's first line, top on top by the guide `ledgerFieldFont` gives it,
/// so that the name stays where it is when the focus comes or goes (measured: the field draws its line 0.3
/// pt higher than the text at the default size, 1 pt at `.accessibility3` and 1.7 pt at `.accessibility5`,
/// and nothing moves sideways). The field's line is higher than the title's, so that its editor does not cut
/// the tails of g, j, p, q and y: its frame stands out of the name's first line by 4.7 pt above and 6.3 pt
/// below at the default size, and by 8.3 and 10.3 pt at `.accessibility5`, inside the room the two headers
/// keep around the name. With the focus the field draws its text itself, on its one line, which scrolls
/// sideways under the caret as every field's does, and what stands under the name moves up to that line.
/// An empty draft shows the field's placeholder, over an unseen line of the label, so that the name keeps one
/// line's height and nothing under it moves at the first letter typed; a draft of only spaces shows it too. The field
/// lines its text up by the
/// layout's direction, as the text that wraps does, so a name whose script runs against the layout does not
/// jump across when the focus comes.
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

    /// Pete's question 5, A: a draft of only spaces shows the placeholder, as an empty one does. The field
    /// draws its own only for an empty text, so this one is drawn for it, while the field has the focus (without
    /// it the draft is the stored name again).
    private var showsThePlaceholderOverABlankDraft: Bool {
        isEditing && !draft.isEmpty && draft.allSatisfy(\.isWhitespace)
    }

    /// The placeholder's colour, the field's prompt and the one drawn over a blank draft alike (review S14 SF-2:
    /// a token, not the system's placeholder style).
    private static var placeholderColor: Color {
        LedgerColor.inkFaint
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The label on one line, unseen and of no width: an empty draft keeps the name's one line, under
            // the placeholder, and a long label widens nothing the name wraps in.
            Text(label)
                .ledgerFont(.title)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 0, alignment: .leading)
                .hidden()
            if showsThePlaceholderOverABlankDraft {
                Text(label)
                    .ledgerFont(.title)
                    // The colour of the field's own prompt, so a blank draft reads as an empty one.
                    .foregroundStyle(Self.placeholderColor)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Text(draft)
                .ledgerFont(.title)
                .foregroundStyle(isEditing ? Color.clear : LedgerColor.ink)
                .multilineTextAlignment(.leading)
                // With the focus the text keeps to one line, as the field over it does, and is not drawn; a
                // line longer than the screen runs out of the frame, which keeps the width it is given.
                .fixedSize(horizontal: isEditing, vertical: false)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
        .overlay(alignment: .topLeading) {
            TextField(text: $draft, prompt: Text(label).foregroundStyle(Self.placeholderColor)) {
                Text(label)
            }
            .ledgerFieldFont(.title)
            // Where the text starts: at the layout's leading edge, whatever the name's script.
            .multilineTextAlignment(strategy: .layoutBased)
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
