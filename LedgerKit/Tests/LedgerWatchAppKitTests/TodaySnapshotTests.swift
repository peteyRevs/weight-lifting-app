import LedgerSnapshotTesting
@testable import LedgerWatchAppKit
import SwiftUI
import Testing

/// The watch's Today placeholder at 46 mm, until F18 replaces the screen and this reference (F07 test plan). The
/// watch has one, dark, appearance. Recorded on the PR-Watch plan's Apple Watch Series 12 (46mm), watchOS 27.0; the
/// Mac host draws none.
@Suite("Watch Today placeholder snapshots")
struct TodaySnapshotTests {
    @Test("The watch's Today placeholder matches its reference")
    func todayPlaceholder_matchesReference() {
        assertLedgerSnapshot(
            of: TodayPlaceholder().frame(height: WatchSize.mm46.size.height),
            devices: [.watch(.mm46)],
            typeSizes: [WatchSize.mm46.dynamicTypeSize]
        )
    }
}
