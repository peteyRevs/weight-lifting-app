#if DEBUG
    import LedgerDomain
    import LedgerFakes
    import SwiftUI

    /// Every preview of "Bar and plates"' sheet, one case each: drawn from the model its presentation makes of a fixed
    /// draft, as `SettingsPreview` draws Settings. `PreviewTests` render every case; the snapshot and accessibility
    /// tests draw the same states' pages.
    enum PlatesPreview: String, CaseIterable {
        /// Pounds' standard bar and plates.
        case pounds = "Bar and plates"
        /// Kilograms, with a lighter bar, 25 kg plates on, 1.25 kg off, and a 0.25 kg plate no list has.
        case kilograms = "Bar and plates in kilograms"
        /// Every plate off, and the bar at its lightest, whose "−" is switched off.
        case noPlates = "No plates"

        var draft: PlatesDraft {
            switch self {
            case .pounds:
                PlatesDraft(units: .lb, inventory: .standard(.lb))
            case .kilograms:
                PlatesDraft(units: .kg, inventory: PlateInventory(
                    bar: .kilograms(15),
                    plates: [25, 20, 15, 10, 5, 2.5, 0.25].map(Weight.kilograms)
                ))
            case .noPlates:
                PlatesDraft(units: .lb, inventory: PlateInventory(bar: .zero, plates: []))
            }
        }

        func model() -> PlatesModel {
            PlatesPresentation.sheet(draft, locale: Fixtures.locale)
        }

        /// The sheet in this state.
        var content: some View {
            PlateInventorySheet(model: model()) { _ in }
        }
    }

    #Preview("Bar and plates") {
        PlatesPreview.pounds.content
    }

    #Preview("Bar and plates in kilograms") {
        PlatesPreview.kilograms.content
    }

    #Preview("No plates") {
        PlatesPreview.noPlates.content
    }
#endif
