import LedgerDesign
import SwiftUI

/// The top of the builder: "MY PROGRAM" over the program's name, which is a `NameField`: edited in place, and
/// drawn whole on as many lines as it needs while it is not, as the day's name is on the Day editor.
///
/// The one action a view of this screen makes itself is here: the name as typed.
struct ProgramHeader: View {
    let model: ProgramBuilderModel.Header
    let send: (ProgramBuilderAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
            Eyebrow(model.eyebrow)
            NameField(label: model.namePlaceholder, name: model.name) { send(.rename($0)) }
                // The room of the tails of the name's last line, as under the day's name.
                .padding(.bottom, LedgerSpacing.s)
        }
    }
}
