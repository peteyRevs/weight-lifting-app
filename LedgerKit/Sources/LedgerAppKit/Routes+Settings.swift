import FeatureSettings

extension AppRouter {
    /// Where Settings' routes go (architecture §4). "Diagnostics", in Debug builds, raises the Debug menu, the sheet a
    /// long press on Today's title raises (F07 criterion 7); the sheet is `MainRoot`'s, which hands its opener here.
    /// A Release build has no route to resolve.
    func resolve(_ route: SettingsRoute, showDebugMenu: () -> Void) {
        switch route {
        #if DEBUG
            case .debugMenu:
                showDebugMenu()
        #endif
        }
    }
}
