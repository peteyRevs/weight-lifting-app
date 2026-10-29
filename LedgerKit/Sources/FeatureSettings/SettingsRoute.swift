/// Where Settings asks the app to go. A route is an intent, never a navigation call: `LedgerAppKit` resolves it
/// (architecture §4).
///
/// A Release build has no case: its Settings has nowhere to send the lifter yet (S2 and S3 add the export's share
/// sheet and "Delete all data", neither of which is a route).
public nonisolated enum SettingsRoute: Hashable, Sendable {
    #if DEBUG
        /// "Diagnostics": the Debug menu, as a long press on Today's title opens it (F07 criterion 7).
        case debugMenu
    #endif
}
