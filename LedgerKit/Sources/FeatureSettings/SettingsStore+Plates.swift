import Foundation
import LedgerDomain

/// "Bar and plates" (F14 S2, criterion 3, N12): the sheet's changes go to a draft of the current unit's inventory,
/// and "Done" saves the draft into that unit's inventory as any change is saved (N1), so a failed save puts it back
/// and says so. The other unit's inventory is left as it is.
extension SettingsStore {
    /// Applies `action` when it is the sheet's, and says whether it was.
    func sendToPlates(_ action: SettingsAction) -> Bool {
        switch action {
        case .editPlates:
            // The row does nothing while Plate math is off: its model carries no action then.
            guard let current = shown, current.plateMathEnabled else {
                return true
            }
            let inventory = PlatesPresentation.inventory(of: current)
            plates = PlatesDraft(units: current.units, inventory: inventory, opened: Set(inventory.plates))
        case let .setBar(bar):
            plates?.inventory.bar = bar
        case let .setPlate(size, isOn):
            if let inventory = plates?.inventory {
                let others = inventory.plates.filter { $0 != size }
                plates?.inventory = PlateInventory(bar: inventory.bar, plates: isOn ? others + [size] : others)
            }
        case .resetPlates:
            if let units = plates?.units {
                plates?.inventory = .standard(units)
            }
        case .savePlates:
            savePlates()
        case .cancelPlates:
            plates = nil
        case .setUnits, .setDefaultRest, .setWeekStart, .setPlateMath, .setAutoRest, .setWatchBuzz, .route, .deleteAll,
             .continueDeleteAll, .setDeleteText, .confirmDeleteAll, .cancelDeleteAll:
            return false
        }
        show()
        return true
    }

    /// Closes the sheet and saves its bar and plates into its unit's inventory.
    private func savePlates() {
        guard let draft = plates, var next = shown else {
            return
        }
        plates = nil
        next.plateInventory[draft.units] = draft.inventory
        change(to: next)
    }
}
