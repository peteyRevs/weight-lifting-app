import LedgerSnapshotTesting
import SwiftUI
import Testing

/// `assertLedgerSnapshot`'s cells (F07): by default exactly F06's phone and watch matrices, narrowed by its
/// arguments. What each cell draws is `assertPhoneSnapshot`'s and `assertWatchSnapshot`'s, tested with F06.
@Suite("Snapshot matrix", .tags(.design))
struct SnapshotMatrixTests {
    @Test("By default the cells are F06's phone matrix, then its watch matrix")
    func defaultMatrix_isF06s() {
        let expected = SnapshotAppearance.phoneMatrix.map(\.description) + WatchAppearance.matrix.map(\.description)
        #expect(SnapshotCell.matrix().map(\.description) == expected)
    }

    @Test("devices, themes and typeSizes narrow the matrix; the watch ignores themes")
    func arguments_narrowTheMatrix() {
        let phoneDark = SnapshotCell.matrix(devices: [.phone], themes: [.dark], typeSizes: [.xLarge])
        let watch = SnapshotCell.matrix(devices: [.watch(.mm42)], themes: [.light])
        let both = SnapshotCell.matrix(devices: [.phone, .watch(.mm49)], themes: [.light], typeSizes: [.large])
        #expect(phoneDark.map(\.description) == ["dark-xLarge"])
        #expect(watch.map(\.description) == ["mm42-large", "mm42-accessibility3"])
        #expect(both.map(\.description) == ["light-large", "mm49-large"])
    }

    @Test("Each platform draws its own cells: phone cells on iOS, watch cells on watchOS, none on the Mac host")
    func isDrawnHere_matchesThePlatform() {
        let drawn = SnapshotCell.matrix().filter(\.isDrawnHere).map(\.description)
        #if os(iOS)
            #expect(drawn == SnapshotAppearance.phoneMatrix.map(\.description))
        #elseif os(watchOS)
            #expect(drawn == WatchAppearance.matrix.map(\.description))
        #else
            #expect(drawn.isEmpty)
        #endif
    }

    #if os(iOS) || os(watchOS)
        @Test("F7-9: arguments that leave this simulator no cell fail the test instead of comparing nothing")
        func noCellHere_failsTheTest() {
            withKnownIssue {
                assertLedgerSnapshot(of: EmptyView(), devices: [])
            } matching: { issue in
                issue.description.contains("no cell to draw")
            }
        }
    #endif
}
