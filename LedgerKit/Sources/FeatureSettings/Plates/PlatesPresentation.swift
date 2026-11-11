import Foundation
import LedgerDomain

/// "Bar and plates" and its sheet in one pure step each (criterion 3, N12; Pete's question 6, A): the bar stepped
/// within its range, and the plates switched on or off from a fixed list per unit.
nonisolated enum PlatesPresentation {
    /// The common plate sizes the sheet lists, heaviest first.
    static func sizes(_ units: Units) -> [Weight] {
        switch units {
        case .lb: [55, 45, 35, 25, 15, 10, 5, 2.5, 1.25].map(Weight.pounds)
        case .kg: [25, 20, 15, 10, 5, 2.5, 1.25, 0.5].map(Weight.kilograms)
        }
    }

    /// The bar's step and its heaviest: 2.5 lb up to 100 lb, 1.25 kg up to 45 kg. Its lightest is no bar at all.
    static func barStep(_ units: Units) -> (step: Weight, heaviest: Weight) {
        switch units {
        case .lb: (.pounds(2.5), .pounds(100))
        case .kg: (.kilograms(1.25), .kilograms(45))
        }
    }

    /// The row of Settings: it opens the current unit's sheet while Plate math is on.
    static func row(_ settings: Settings, locale: Locale) -> PlatesRowModel {
        guard settings.plateMathEnabled else {
            return PlatesRowModel(title: SettingsCopy.barAndPlates, detail: SettingsCopy.turnOnPlateMath, action: nil)
        }
        let bar = inventory(of: settings).bar
        return PlatesRowModel(
            title: SettingsCopy.barAndPlates,
            detail: SettingsCopy.barDetail(weight(bar, settings.units, locale: locale), locale: locale),
            action: .editPlates
        )
    }

    /// The inventory stored for the settings' unit, else that unit's standard one.
    static func inventory(of settings: Settings) -> PlateInventory {
        settings.plateInventory[settings.units] ?? .standard(settings.units)
    }

    static func sheet(_ draft: PlatesDraft, locale: Locale) -> PlatesModel {
        let units = draft.units
        let inventory = draft.inventory
        // A size off the list (stored by a later version) is shown, so it can be kept or switched off, and stays shown
        // once off for the whole of the sheet's session (F14-S2-G2-1).
        let listed = Set(sizes(units)).union(draft.opened).union(inventory.plates).sorted(by: >)
        let plates = listed.enumerated().map { place, size in
            let isOn = inventory.plates.contains(size)
            return PlatesModel.Plate(
                id: place,
                title: weight(size, units, locale: locale),
                spokenLabel: size.spoken(in: units, locale: locale.forCountedText),
                isOn: isOn,
                action: .setPlate(size, isOn: !isOn)
            )
        }
        return PlatesModel(
            title: SettingsCopy.barAndPlates,
            cancel: SettingsCopy.cancel,
            bar: bar(inventory.bar, units, locale: locale),
            platesTitle: SettingsCopy.platesYouOwn,
            plates: plates,
            empty: inventory.plates.isEmpty ? SettingsCopy.noPlates : nil,
            reset: SettingsModel.Link(title: SettingsCopy.resetToStandard, action: .resetPlates),
            done: SettingsModel.Link(title: SettingsCopy.done, action: .savePlates)
        )
    }

    /// The bar with a step either way that stays within 0 and its heaviest; a bar off the grid (another version's)
    /// steps to the multiple next to it.
    static func bar(_ bar: Weight, _ units: Units, locale: Locale) -> PlatesModel.Bar {
        let (step, heaviest) = barStep(units)
        let lighter = bar.nextMultiple(of: step, .downward)
        let heavier = bar.nextMultiple(of: step, .upward)
        return PlatesModel.Bar(
            title: SettingsCopy.bar,
            value: weight(bar, units, locale: locale),
            spokenValue: bar.spoken(in: units, locale: locale.forCountedText),
            decrement: lighter < bar ? .setBar(lighter) : nil,
            increment: heavier <= heaviest ? .setBar(heavier) : nil
        )
    }

    /// "45 lb": the Domain's number with the unit.
    static func weight(_ weight: Weight, _ units: Units, locale: Locale) -> String {
        SettingsCopy.weight(weight.formatted(in: units), units: units, locale: locale)
    }
}
