import LedgerDomain

/// What a tap on Settings means, as a value: the store applies it and decides nothing. Every change says what
/// becomes true, not what changes, so one applied twice gives what one application gives.
nonisolated enum SettingsAction: Hashable, Sendable {
    case setUnits(Units)
    /// A step of "Default rest": the rest it lands on, which the presentation has held to 30–300 s.
    case setDefaultRest(RestDuration)
    case setWeekStart(Weekday)
    case setPlateMath(Bool)
    case setAutoRest(Bool)
    case setWatchBuzz(Bool)
    /// "Bar and plates": opens its sheet over the current unit's inventory (criterion 3).
    case editPlates
    /// The sheet's bar, stepped to this weight.
    case setBar(Weight)
    /// A plate size of the sheet switched on or off.
    case setPlate(Weight, isOn: Bool)
    /// "Reset to standard": the unit's standard bar and plates, in the sheet.
    case resetPlates
    /// "Done": the sheet's bar and plates saved, as any change is saved, and the sheet closed.
    case savePlates
    /// "Cancel", or the sheet swiped away: closed, nothing saved.
    case cancelPlates
    /// A tap that asks the app to go somewhere: "Diagnostics", in Debug builds.
    case route(SettingsRoute)
}
