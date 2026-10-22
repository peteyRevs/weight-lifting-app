import LedgerDesign
import SwiftUI

/// Everything the Library scrolls, and never a scroll view (the M1 convention): what the VoiceOver trees and the
/// snapshot references are taken from. Top to bottom: the title with "New exercise", the search field, the muscle
/// chips and the equipment chips, then RECENTLY LOGGED and ALL EXERCISES as hairline rows, or a message with its
/// one button when no row is left.
///
/// v2's 22, 20 and 28 px between the title, the field, the chips and the first section are `xl` (24), the scale's
/// nearest step; its 30 px between sections is `xxl` (32), as on Today.
struct LibraryPage: View {
    let model: LibraryModel
    let send: (LibraryAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xl) {
            LibraryHeader(title: model.title, newExercise: model.newExercise, send: send)
            SearchField(model.search.placeholder, short: model.search.shortPlaceholder, text: model.search.query) {
                send(.setQuery($0))
            }
            VStack(alignment: .leading, spacing: LedgerSpacing.m) {
                chips(model.muscles)
                chips(model.equipment)
            }
            switch model.content {
            case let .sections(sections):
                VStack(alignment: .leading, spacing: LedgerSpacing.xxl) {
                    ForEach(sections) { LibrarySection(section: $0, send: send) }
                }
            case let .nothingMatches(message), let .noExercises(message):
                VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                    Text(message.text)
                        .ledgerFont(.bodyLight)
                        .foregroundStyle(LedgerColor.inkMuted)
                    PillButton(message.control.title) { send(message.control.action) }
                }
            }
        }
        .padding(LedgerSpacing.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chips(_ row: LibraryModel.ChipRow) -> some View {
        FilterChipRow(row.chips, title: \.title, spokenLabel: \.spokenLabel, isSelected: \.isSelected) { chip in
            send(chip.action)
        }
    }
}

/// The title, the screen's heading and the element the UI tests find (`library.title`), with "New exercise" at
/// its trailing edge; at accessibility text sizes the button stands under the title, so the title keeps its one
/// line. Tab roots hide the navigation bar, so the button is drawn here rather than in a toolbar.
private struct LibraryHeader: View {
    let title: String
    let newExercise: LibraryModel.Control
    let send: (LibraryAction) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LedgerSpacing.s))
            : AnyLayout(HStackLayout(alignment: .center, spacing: LedgerSpacing.m))
        layout {
            Text(title)
                .ledgerFont(.title)
                .foregroundStyle(LedgerColor.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("library.title")
                .frame(maxWidth: .infinity, alignment: .leading)
            PillButton(newExercise.title, flush: .trailing) { send(newExercise.action) }
        }
    }
}
