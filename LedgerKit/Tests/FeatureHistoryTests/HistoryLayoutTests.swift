#if os(iOS) && DEBUG
    @testable import FeatureHistory
    import LedgerDesign
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F13 S1, by measurement: at every text size, with Bold Text and laid out right to left, every stop of every
    /// state has a size, stands inside the page, is over no other stop and, when it can be tapped, is a 44 pt target;
    /// and (criterion 8) a row's name is never cut short: at every size its label is as tall as the name's own text
    /// at the page's width. What a frame cannot show is in the references, which were looked at. The sizes and
    /// settings go through `TestSweep` (ruling R6).
    @Suite("History layout", .serialized, .tags(.feature))
    struct HistoryLayoutTests {
        /// One way the system can be set.
        nonisolated struct Setting: Sendable, CustomTestStringConvertible {
            let size: DynamicTypeSize
            var isBold = false
            var isRightToLeft = false

            var testDescription: String {
                "\(size)" + (isBold ? ", Bold Text" : "") + (isRightToLeft ? ", right to left" : "")
            }

            /// On the hosted PR runner the representative sizes, each plain and bold right to left.
            static let all: [Setting] = TestSweep.sizes([.xSmall, .large, .xxxLarge, .accessibility3, .accessibility5])
                .flatMap { size in
                    TestSweep.subset([
                        Setting(size: size), Setting(size: size, isBold: true),
                        Setting(size: size, isRightToLeft: true),
                        Setting(size: size, isBold: true, isRightToLeft: true)
                    ]) { $0.isBold == $0.isRightToLeft }
                }
        }

        static func placed(_ view: some View, _ setting: Setting) -> [PlacedStop] {
            view
                .environment(\.legibilityWeight, setting.isBold ? .bold : .regular)
                .environment(\.layoutDirection, setting.isRightToLeft ? .rightToLeft : .leftToRight)
                .placedStops(SnapshotAppearance(.dark, setting.size))
        }

        /// What is wrong with the frames of `stops` on a page 402 points wide, a line each.
        nonisolated static func faults(in stops: [PlacedStop]) -> [String] {
            let width = SnapshotConfig.phoneWidth
            var lines: [String] = []
            for item in stops {
                let frame = item.frame
                if frame.width < 1 || frame.height < 1 {
                    lines.append("no size: \(item.stop) \(frame.size)")
                }
                if frame.minX < -0.5 || frame.maxX > width + 0.5 {
                    lines.append("outside the page: \(item.stop) x \(frame.minX)...\(frame.maxX)")
                }
                if item.stop.kind == .button, frame.height < 43.5 || frame.width < 43.5 {
                    lines.append("target under 44 pt: \(item.stop) \(frame.size)")
                }
            }
            for (index, first) in stops.enumerated() {
                for second in stops[(index + 1)...] {
                    let shared = first.frame.intersection(second.frame)
                    if !shared.isNull, shared.width > 2, shared.height > 2 {
                        lines.append("overlap \(shared.size): \(first.stop) and \(second.stop)")
                    }
                }
            }
            return lines
        }

        @Test(
            "In every state and setting no stop is empty, outside the page, under 44 points or over another",
            arguments: HistoryPreview.allCases, Setting.all
        )
        func parts_layOutSanely(_ preview: HistoryPreview, _ setting: Setting) {
            let stops = Self.placed(HistoryParts(preview: preview), setting)
            #expect(!stops.isEmpty, "the parts were not read")
            let faults = Self.faults(in: stops)
            #expect(faults.isEmpty, "\(faults.prefix(4).joined(separator: "\n"))")
        }

        /// A row as long as criterion 8 needs: a name of three lines or more at the phone's width, and no badge, so
        /// the name and the meta have the row's whole width at every size.
        static func longRow() throws -> HistoryModel.Row {
            let row = try #require(HistoryPreview.populated.model().rows.first)
            return HistoryModel.Row(
                id: row.id,
                name: "Upper A — Push focus, with the long accessory work, the extra finisher and a cool-down",
                meta: row.meta,
                badge: nil,
                spokenValue: row.spokenValue,
                route: row.route
            )
        }

        /// Whether `row`, drawn at the text column's width, is as tall as its whole name and its whole meta, each
        /// measured as its own `Text` at that width, with the row's spacing and padding (review R1-2): a name cut
        /// short leaves the row shorter than that at every size where it would wrap.
        static func holdsEveryLine(_ row: some View, of model: HistoryModel.Row, _ setting: Setting) throws -> Bool {
            let width = SnapshotConfig.phoneWidth - 2 * LedgerSpacing.screen
            let drawn = try #require(placed(row.frame(width: width), setting).first).frame
            let name = try #require(placed(Text(model.name).ledgerFont(.body).frame(width: width), setting).first)
            let meta = try #require(placed(Text(model.meta).ledgerFont(.label).frame(width: width), setting).first)
            let needed = name.frame.height + LedgerSpacing.xs + meta.frame.height + 2 * LedgerSpacing.l
            return drawn.height >= needed - 1
        }

        @Test(
            "8. A long name wraps and is never truncated: the row holds every line of its name and its meta",
            arguments: Setting.all
        )
        func longName_wrapsWhole(_ setting: Setting) throws {
            let row = try Self.longRow()
            let holds = try Self.holdsEveryLine(HistoryRow(row: row) { _ in }, of: row, setting)
            #expect(holds, "\(setting.testDescription)")
        }

        /// The guard's control (review R1-2): the same row with its name cut to one line fails it, at the default size
        /// and at the largest, both in the PR sweep.
        @Test("8. Control: a row whose text is cut to one line fails the guard", arguments: [
            Setting(size: .large), Setting(size: .accessibility5)
        ])
        func longName_cutToOneLine_failsTheGuard(_ setting: Setting) throws {
            let row = try Self.longRow()
            let holds = try Self.holdsEveryLine(HistoryRow(row: row) { _ in }.lineLimit(1), of: row, setting)
            #expect(!holds, "a one-line name must fail at \(setting.testDescription)")
        }
    }
#endif
