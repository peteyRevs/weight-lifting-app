@testable import LedgerAppKit
import LedgerSnapshotTesting
import SwiftUI
import Testing

/// References for the two screens the shell draws besides Today's placeholder (F9-S1-11; testing-strategy §2.6:
/// light and dark at three text sizes). The "Tabs" preview has none: the system tab bar's material is not a
/// stable reference, and what the shell shows is pinned by `AppTabsTests` (the hosted tree), `PreviewTests` (it
/// renders) and the `Tabs` and `TabsAdversarial` UI tests (the running app, the selected tab's colour included).
/// Recorded on the PR plan's iPhone 17 (iOS 27.0); the Mac host draws none.
@Suite("Shell snapshots")
struct ShellSnapshotTests {
    @Test("A placeholder screen matches its references")
    func placeholderScreen_matchesReferences() {
        assertLedgerSnapshot(
            of: PlaceholderScreen(AppCopy.title(of: .program), identifier: "program.title")
                .frame(width: SnapshotConfig.phoneWidth),
            devices: [.phone]
        )
    }

    @Test("The can't-open-your-data screen matches its references")
    func databaseUnavailable_matchesReferences() {
        assertLedgerSnapshot(
            of: DatabaseUnavailableView().frame(width: SnapshotConfig.phoneWidth),
            devices: [.phone]
        )
    }
}
