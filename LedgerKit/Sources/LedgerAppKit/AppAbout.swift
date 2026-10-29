import FeatureSettings
import Foundation

extension AppAbout {
    /// The app's own, from the app's bundle: Settings' About line (F14 S1, N6), so that no source names the product
    /// or its version. The name is `CFBundleDisplayName`, else `CFBundleName`.
    static let main = AppAbout(bundle: .main)

    init(bundle: Bundle) {
        let value = { (key: String) in bundle.object(forInfoDictionaryKey: key) as? String }
        self.init(
            name: value("CFBundleDisplayName") ?? value("CFBundleName"),
            version: value("CFBundleShortVersionString"),
            build: value("CFBundleVersion")
        )
    }
}
