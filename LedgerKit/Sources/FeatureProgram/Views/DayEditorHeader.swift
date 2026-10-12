import LedgerDesign
import SwiftUI

/// The top of the Day editor's page, which scrolls with it as the builder's header does: "DAY 1 OF 4" over
/// the day's name, as "MY PROGRAM" stands over the program's, and under the name the day's tag before the
/// line "Week 1 · 5 exercises · 18 sets · ~39 min". The name is a `NameField`: edited in place, and drawn
/// whole on as many lines as it needs while it is not. The tag is drawn as the builder draws it, is not
/// editable and is not read by VoiceOver; where it and the line do not fit side by side the line stands
/// under it.
///
/// The one action a view of this screen makes itself is here: the name as typed, for this day. So the header
/// takes the whole content, not its `header` alone: the action names the day.
struct DayEditorHeader: View {
    let model: DayEditorModel.Content
    let send: (DayEditorAction) -> Void

    var body: some View {
        let header = model.header
        VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
            Eyebrow(header.position)
            NameField(label: header.nameLabel, name: header.name) { send(.rename($0, day: model.id)) }
                // The title's lines are as high as its type is large, so the tails of the name's last line
                // hang under its frame: this is their room, clear of the tag.
                .padding(.bottom, LedgerSpacing.s)
            WrapLayout {
                DayTag(text: header.tag)
                    .accessibilityHidden(true)
                Text(header.meta)
                    .ledgerFont(.label)
                    .foregroundStyle(LedgerColor.inkMuted)
            }
        }
        .padding(.horizontal, LedgerSpacing.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
