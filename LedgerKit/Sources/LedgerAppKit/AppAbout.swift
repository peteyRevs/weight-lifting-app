import FeatureSettings
import Foundation

extension AppAbout {
    /// The app's own, from the app's bundle: Settings' About line (F14 S1, N6), so that no source names the product
    /// or its version. The name is `CFBundleDisplayName`, else `CFBundleName`. A value that is
    /// blank once trimmed counts as absent, so a blank display name falls back to the bundle name (F14-S1b-1).
    static let main = AppAbout(bundle: .main)

    init(bundle: Bundle) {
        let value = { (key: String) -> String? in
            guard let text = bundle.object(forInfoDictionaryKey: key) as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }
            return text
        }
        self.init(
            name: value("CFBundleDisplayName") ?? value("CFBundleName"),
            version: value("CFBundleShortVersionString"),
            build: value("CFBundleVersion")
        )
    }
}
