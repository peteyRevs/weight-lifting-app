#if DEBUG
    @testable import FeatureSettings
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// F14 S1: Settings against its references. Each is the state's parts (`SettingsParts`) at the iPhone 17 width and
    /// their own height: the screen puts its page in a scroll view, which has no height of its own (testing-strategy
    /// §2.6). {lb, kg} × {light, dark} × {large, accessibility3}: eight references. Recorded on the PR plan's
    /// iPhone 17 (iOS 27.0); the Mac host draws none.
    @Suite("Settings snapshots", .serialized, .tags(.feature, .snapshot))
    struct SettingsSnapshotTests {
        private func parts(_ preview: SettingsPreview) -> some View {
            SettingsParts(preview: preview).frame(width: SnapshotConfig.phoneWidth)
        }

        @Test("Settings in pounds matches its references, at the default and an accessibility size")
        func pounds_matchesReferences() {
            assertLedgerSnapshot(of: parts(.pounds), devices: [.phone], typeSizes: [.large, .accessibility3])
        }

        @Test("Settings in kilograms matches its references, at the default and an accessibility size")
        func kilograms_matchesReferences() {
            assertLedgerSnapshot(of: parts(.kilograms), devices: [.phone], typeSizes: [.large, .accessibility3])
        }
    }
#endif
