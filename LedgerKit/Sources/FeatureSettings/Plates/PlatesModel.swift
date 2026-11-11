import LedgerDomain

/// The bar and plates the lifter is editing, for one unit (criterion 3): what the sheet's changes apply to until
/// "Done" saves it into that unit's inventory. The other unit's inventory is never touched.
nonisolated struct PlatesDraft: Hashable, Sendable {
    let units: Units
    var inventory: PlateInventory
    /// The sizes the sheet opened with, so one off the unit's list (another version's) stays listed, and can be
    /// switched on again, after it is switched off (F14-S2-G2-1).
    var opened: Set<Weight> = []
}

/// "Bar and plates", the row of Settings (criterion 3): it opens the sheet while Plate math is on, and is drawn
/// switched off, saying why, while it is off.
nonisolated struct PlatesRowModel: Equatable, Sendable {
    let title: String
    /// "45 lb bar", or "Turn on Plate math to edit".
    let detail: String
    /// Opens the sheet; nil while Plate math is off.
    let action: SettingsAction?
}

/// The "Bar and plates" sheet (N12), as `PlatesPresentation.sheet` makes it: every string final, every control with
/// the action its tap means.
nonisolated struct PlatesModel: Equatable, Sendable {
    let title: String
    let cancel: String
    let bar: Bar
    let platesTitle: String
    /// The unit's common sizes, heaviest first, with any other size the inventory holds among them.
    let plates: [Plate]
    /// "No plates: no plate line will show", while every plate is off; nil otherwise.
    let empty: String?
    let reset: SettingsModel.Link
    let done: SettingsModel.Link

    /// The bar, stepped: 0–100 lb by 2.5 lb, or 0–45 kg by 1.25 kg. To VoiceOver one adjustable element.
    struct Bar: Equatable, Sendable {
        let title: String
        /// "45 lb".
        let value: String
        /// "45 pounds".
        let spokenValue: String
        /// One step lighter; nil at the lightest.
        let decrement: SettingsAction?
        /// One step heavier; nil at the heaviest.
        let increment: SettingsAction?
    }

    /// A plate size, on or off. To VoiceOver a switch named by its spoken weight.
    struct Plate: Equatable, Sendable, Identifiable {
        /// The size's place in the list, from 0.
        let id: Int
        /// "45 lb".
        let title: String
        /// "45 pounds".
        let spokenLabel: String
        let isOn: Bool
        /// Switches it to the other state.
        let action: SettingsAction
    }
}
