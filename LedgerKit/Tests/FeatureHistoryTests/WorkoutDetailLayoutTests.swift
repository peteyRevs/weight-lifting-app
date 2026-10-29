#if os(iOS) && DEBUG
    @testable import FeatureHistory
    import LedgerDesign
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F13 S2, criterion 8, by measurement: at every text size, with Bold Text and laid out right to left, every stop
    /// of every state of a past workout's detail has a size, stands inside the page, is over no other stop and, when it
    /// can be tapped, is a 44 pt target; at accessibility sizes the receipt's tiles stand one per row, as
    /// `ReceiptLayout` stacks them; and a long name wraps whole. The settings are the list's (`HistoryLayoutTests`,
    /// through `TestSweep`); what a frame cannot show is in the references, which were looked at.
    @Suite("Workout detail layout", .serialized, .tags(.feature))
    struct WorkoutDetailLayoutTests {
        typealias Setting = HistoryLayoutTests.Setting

        @Test(
            "In every state and setting no stop is empty, outside the page, under 44 points or over another",
            arguments: DetailPreview.allCases, Setting.all
        )
        func parts_layOutSanely(_ preview: DetailPreview, _ setting: Setting) {
            let stops = HistoryLayoutTests.placed(DetailParts(preview: preview), setting)
            #expect(!stops.isEmpty, "the parts were not read")
            let faults = HistoryLayoutTests.faults(in: stops)
            #expect(faults.isEmpty, "\(faults.prefix(4).joined(separator: "\n"))")
        }

        /// The frames of the three tiles, read as the stops after the day and the name.
        static func tiles(_ setting: Setting) throws -> [CGRect] {
            let stops = HistoryLayoutTests.placed(DetailParts(preview: .withRecords), setting)
            let tiles = try DetailPreview.withRecords.model().receipt.tiles.map(\.spoken)
            return stops.filter { tiles.contains($0.stop.label) }.map(\.frame)
        }

        @Test("8. At accessibility sizes the tiles stand one per row; at the default size, side by side")
        func accessibilitySizes_stackTheTiles() throws {
            let large = try Self.tiles(Setting(size: .large))
            let stacked = try Self.tiles(Setting(size: .accessibility3))
            #expect(large.count == 3 && stacked.count == 3)
            let isSideBySide = Set(large.map { Int($0.minY.rounded()) }).count == 1
            let isOnePerRow = zip(stacked, stacked.dropFirst()).allSatisfy { $0.maxY <= $1.minY + 0.5 }
            #expect(isSideBySide && isOnePerRow)
        }

        /// The detail of the newest preview workout under a name of three lines or more at the phone's width.
        static func longNamed() throws -> WorkoutDetailModel {
            let model = try DetailPreview.withRecords.model()
            return WorkoutDetailModel(
                date: model.date,
                title: "Upper A — Push focus, with the long accessory work, the extra finisher and a cool-down",
                receipt: model.receipt,
                rowRoutes: model.rowRoutes,
                delete: model.delete
            )
        }

        @Test("8. A long name wraps and is never truncated: its heading is as tall as its whole text", arguments: [
            Setting(size: .large), Setting(size: .accessibility3)
        ])
        func longName_wrapsWhole(_ setting: Setting) throws {
            let model = try Self.longNamed()
            let page = WorkoutDetailPage(model: model, send: { _ in }, onDelete: {})
            let heading = try #require(HistoryLayoutTests.placed(page, setting).first { $0.stop.label == model.title })
            let width = SnapshotConfig.phoneWidth - 2 * LedgerSpacing.screen
            let text = Text(model.title).ledgerFont(.title).frame(width: width)
            let whole = try #require(HistoryLayoutTests.placed(text, setting).first)
            #expect(heading.frame.height >= whole.frame.height - 1, "\(setting.testDescription)")
            let line = try #require(HistoryLayoutTests.placed(Text(verbatim: "A").ledgerFont(.title), setting).first)
            #expect(whole.frame.height > 1.5 * line.frame.height, "the name runs over more than one line")
        }
    }
#endif
