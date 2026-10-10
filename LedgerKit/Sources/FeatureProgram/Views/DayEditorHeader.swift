import LedgerDesign
import SwiftUI

/// The Day editor's pinned header: "Program", which goes back to the builder, and "Done" at the two ends of
/// one row; "DAY 1 OF 4" over the day's name, which is a field in the screen title's type, as "MY PROGRAM"
/// stands over the program's; and the day's tag before the line "Week 1 · 5 exercises · 18 sets · ~39 min".
/// The tag is drawn as the builder draws it, is not editable and is not read by VoiceOver; where it and the
/// line do not fit side by side the line stands under it. VoiceOver reads the header as it is drawn:
/// "Program", "Done", the heading, the field, the line.
///
/// The field shows a draft, by `ProgramHeader`'s rule: the stored name is the cleaned one, so a field bound
/// to it would lose a trailing space while the lifter types and could not be emptied. The draft starts as the
/// stored name; each change that leaves it other than the stored name is sent as typed, the one action a view
/// of this screen makes itself; when the field loses focus, and whenever the stored name changes while it has
/// none, the draft takes the stored name again. The field is one line and its target 44 pt high, as the
/// program's name is.
///
/// It takes the whole content, not the header alone: the action that renames the day names the day.
struct DayEditorHeader: View {
    let model: DayEditorModel.Content
    let send: (DayEditorAction) -> Void
    @State private var draft: String
    @FocusState private var isEditing: Bool

    init(model: DayEditorModel.Content, send: @escaping (DayEditorAction) -> Void) {
        self.model = model
        self.send = send
        _draft = State(initialValue: model.header.name)
    }

    private var header: DayEditorModel.Header {
        model.header
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
            HStack(spacing: LedgerSpacing.m) {
                PillButton(header.back.title, style: .ghost, flush: .leading) { send(header.back.action) }
                Spacer(minLength: 0)
                PillButton(header.done.title, flush: .trailing) { send(header.done.action) }
            }
            Eyebrow(header.position)
            TextField(header.nameLabel, text: $draft)
                .ledgerFont(.title)
                .foregroundStyle(LedgerColor.ink)
                .submitLabel(.done)
                .focused($isEditing)
                .ledgerHitTarget(alignment: .leading)
                .onTapGesture { isEditing = true }
                .accessibilityLabel(header.nameLabel)
            WrapLayout {
                DayTag(text: header.tag)
                    .accessibilityHidden(true)
                Text(header.meta)
                    .ledgerFont(.label)
                    .foregroundStyle(LedgerColor.inkMuted)
            }
        }
        .padding(.horizontal, LedgerSpacing.screen)
        .padding(.vertical, LedgerSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: draft) { _, text in
            if text != header.name {
                send(.rename(text, day: model.id))
            }
        }
        .onChange(of: isEditing) { _, isEditing in
            if !isEditing {
                draft = header.name
            }
        }
        .onChange(of: header.name) { _, name in
            if !isEditing {
                draft = name
            }
        }
    }
}
