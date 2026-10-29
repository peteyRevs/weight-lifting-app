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
    /// A tap that asks the app to go somewhere: "Diagnostics", in Debug builds.
    case route(SettingsRoute)
}
