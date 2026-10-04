@testable import LedgerAppKit
import LedgerSnapshotTesting
import SwiftUI
import Testing

/// Today's placeholder, light and dark, until F09 replaces the screen and these references with its own (F07 test
/// plan). Recorded on the PR plan's iPhone 17 (iOS 27.0); the Mac host draws none.
@Suite("Today placeholder snapshots")
struct TodaySnapshotTests {
    @Test("Today's placeholder matches its references, light and dark")
    func todayPlaceholder_matchesReferences() {
        assertLedgerSnapshot(
            of: TodayPlaceholder().frame(width: SnapshotConfig.phoneWidth),
            devices: [.phone],
            typeSizes: [.large]
        )
    }
}
