import SwiftUI

/// One row of filter chips, pills that wrap: the chosen one filled with ink, which VoiceOver hears as selected,
/// the others outlined. Each chip is read by its spoken label ("Muscle: Chest"), since two rows of one screen
/// can both have an "All". String-only: the caller says, of each of its own chips, its title, its spoken label
/// and whether it is the chosen one, and is handed the chip a tap chose (F11's exercise library, F12's Library).
public struct FilterChipRow<Chip: Identifiable>: View {
    private let chips: [Chip]
    private let title: (Chip) -> String
    private let spokenLabel: (Chip) -> String
    private let isSelected: (Chip) -> Bool
    private let onTap: (Chip) -> Void

    public init(
        _ chips: [Chip],
        title: @escaping (Chip) -> String,
        spokenLabel: @escaping (Chip) -> String,
        isSelected: @escaping (Chip) -> Bool,
        onTap: @escaping (Chip) -> Void
    ) {
        self.chips = chips
        self.title = title
        self.spokenLabel = spokenLabel
        self.isSelected = isSelected
        self.onTap = onTap
    }

    public var body: some View {
        WrapLayout(lineSpacing: 0) {
            ForEach(chips) { chip in
                PillButton(title(chip), style: isSelected(chip) ? .filled : .outline) { onTap(chip) }
                    .accessibilityLabel(spokenLabel(chip))
            }
        }
    }
}

/// A muscle row with "Back" chosen over the search field, empty and holding a query, for the gallery.
struct FilterChipRowGallery: View {
    private struct Chip: Identifiable {
        let id: Int
        let title: String
    }

    private static let chips = ["All", "Chest", "Back", "Shoulders", "Legs", "Arms"].enumerated()
        .map { Chip(id: $0.offset, title: $0.element) }

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            SearchField("Search 224 exercises", short: "Search", text: "") { _ in }
            SearchField("Search 224 exercises", short: "Search", text: "row") { _ in }
            FilterChipRow(
                Self.chips,
                title: \.title,
                spokenLabel: { "Muscle: \($0.title)" },
                isSelected: { $0.id == 2 },
                onTap: { _ in }
            )
        }
    }
}
