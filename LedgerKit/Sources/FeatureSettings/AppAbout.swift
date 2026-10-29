/// What the About line at the foot of Settings reads: the app's name, version and build, as the app's bundle gives
/// them (`CFBundleDisplayName`, `CFBundleShortVersionString`, `CFBundleVersion`). `LedgerAppKit` reads them from
/// the app's bundle and hands them to `SettingsRoot` (S1b), so no product name or version is written in a source,
/// and a test passes its own. A key the bundle lacks is nil.
public nonisolated struct AppAbout: Hashable, Sendable {
    public var name: String?
    public var version: String?
    public var build: String?

    public init(name: String?, version: String?, build: String?) {
        self.name = name
        self.version = version
        self.build = build
    }
}
