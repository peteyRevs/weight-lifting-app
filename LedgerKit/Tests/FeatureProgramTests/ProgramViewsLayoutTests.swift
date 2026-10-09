#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// F11 S9, criterion 7, by measurement: at the default size and at accessibility sizes, with Bold Text and
    /// laid out right to left, every stop of every state has a size, stands inside the page, is over no other
    /// stop and, when it can be tapped or adjusted, is a 44 pt target; and the rows that wrap do wrap. What a
    /// frame cannot show (a word cut short inside its frame) is in the references, which were looked at.
    /// Increase Contrast changes colours and no size: `ProgramSnapshotTests` draws it.
    @Suite("Program views layout", .serialized, .tags(.feature))
    struct ProgramViewsLayoutTests {
        /// One way the system can be set.
        nonisolated struct Setting: Sendable, CustomTestStringConvertible {
            let size: DynamicTypeSize
            var isBold = false
            var isRightToLeft = false

            var testDescription: String {
                "\(size)" + (isBold ? ", Bold Text" : "") + (isRightToLeft ? ", right to left" : "")
            }

            static let all: [Setting] = [DynamicTypeSize.large, .xxxLarge, .accessibility3, .accessibility5]
                .flatMap { size in
                    [
                        Setting(size: size), Setting(size: size, isBold: true),
                        Setting(size: size, isRightToLeft: true),
                        Setting(size: size, isBold: true, isRightToLeft: true)
                    ]
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
                let isTarget = item.stop.kind == .button || item.stop.kind == .adjustable || item.stop.kind == .field
                if isTarget, frame.height < 43.5 || frame.width < 43.5 {
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
            arguments: ProgramPreview.allCases, Setting.all
        )
        func parts_layOutSanely(_ preview: ProgramPreview, _ setting: Setting) {
            let stops = Self.placed(ProgramParts(preview: preview), setting)
            #expect(stops.count > 5, "the parts were not read")
            let faults = Self.faults(in: stops)
            #expect(faults.isEmpty, "\(faults.prefix(4).joined(separator: "\n"))")
        }

        @Test(
            "Whatever the setting, a state reads the same stops in the same order",
            arguments: ProgramPreview.allCases
        )
        func parts_everySetting_readTheSameStops(_ preview: ProgramPreview) {
            let reference = ProgramParts(preview: preview).stops()
            for setting in Setting.all {
                let found = Self.placed(ProgramParts(preview: preview), setting).map(\.stop)
                let difference = firstDifference(found: found, expected: reference)
                #expect(difference == nil, "\(setting.testDescription)")
            }
        }
    }

    // MARK: - The rows that wrap

    extension ProgramViewsLayoutTests {
        /// The stops of `stops` by the row they stand in, top to bottom: those whose middles are level.
        nonisolated static func rows(of stops: [PlacedStop]) -> [[PlacedStop]] {
            var rows: [[PlacedStop]] = []
            for stop in stops.sorted(by: { $0.frame.midY < $1.frame.midY }) {
                if let last = rows.last?.last, abs(last.frame.midY - stop.frame.midY) < 1 {
                    rows[rows.count - 1].append(stop)
                } else {
                    rows.append([stop])
                }
            }
            return rows
        }

        static func weekChips(
            _ preview: ProgramPreview,
            at size: DynamicTypeSize,
            width: CGFloat? = nil
        ) -> [PlacedStop] {
            ProgramParts(preview: preview).frame(width: width).placedStops(SnapshotAppearance(.light, size))
                .filter { $0.stop.kind == .button && $0.stop.label.hasPrefix("Week ") }
        }

        static func cells(_ preview: ProgramPreview, at size: DynamicTypeSize, width: CGFloat? = nil) -> [PlacedStop] {
            ProgramParts(preview: preview).frame(width: width).placedStops(SnapshotAppearance(.light, size))
                .filter { $0.stop.hint == "Double-tap to assign" }
        }

        @Test("Eight week chips make two rows of four, and sixteen four rows")
        func weekChips_wrapIntoRows() {
            #expect(Self.rows(of: Self.weekChips(.builder, at: .large)).map(\.count) == [4, 4])
            #expect(Self.rows(of: Self.weekChips(.sixteenWeeks, at: .large)).map(\.count) == [4, 4, 4, 4])
            let large = Self.rows(of: Self.weekChips(.sixteenWeeks, at: .accessibility3))
            #expect(large.count > 4 && large.map(\.count).reduce(0, +) == 16)
        }

        @Test("The seven weekdays share one row at the default size, each a 44 pt target, on a 375 pt phone too")
        func scheduleStrip_defaultSize_isOneRowOfEqualTargets() {
            for width in [nil, CGFloat(375)] {
                let cells = Self.cells(.builder, at: .large, width: width)
                #expect(Self.rows(of: cells).map(\.count) == [7], "\(width ?? SnapshotConfig.phoneWidth) pt")
                let widths = cells.map(\.frame.width)
                #expect(widths.allSatisfy { $0 >= 44 - 0.001 }, "\(widths)")
                #expect((widths.max() ?? 0) - (widths.min() ?? 0) < 1, "the cells share the width: \(widths)")
            }
        }

        @Test("When a seventh is too narrow for a cell's word the weekdays wrap into rows of equal cells, in order")
        func scheduleStrip_wraps_intoRowsOfEqualCells() {
            // One step above the default the row still holds on an iPhone 17; two steps above it does not.
            #expect(Self.rows(of: Self.cells(.builder, at: .xLarge)).map(\.count) == [7])
            for (size, width) in [(DynamicTypeSize.xxLarge, nil), (.xLarge, CGFloat(375)), (.accessibility3, nil)] {
                let cells = Self.cells(.builder, at: size, width: width)
                let rows = Self.rows(of: cells).map(\.count)
                #expect(rows.count > 1 && rows.reduce(0, +) == 7, "\(size): \(rows)")
                #expect(rows.dropLast().allSatisfy { $0 == rows[0] }, "every full row holds as many: \(rows)")
                let widths = cells.map(\.frame.width)
                #expect((widths.max() ?? 0) - (widths.min() ?? 0) < 1, "\(size): the cells are equal: \(widths)")
                #expect(cells.map(\.stop.label) == [
                    "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
                ])
            }
        }

        @Test("The library's chips wrap: five and one at the default size, more rows at an accessibility size")
        func filterChips_wrap() {
            func chipRows(at size: DynamicTypeSize, _ prefix: String) -> [Int] {
                let chips = ProgramParts(preview: .library).placedStops(SnapshotAppearance(.light, size))
                    .filter { $0.stop.label.hasPrefix(prefix) }
                return Self.rows(of: chips).map(\.count)
            }
            #expect(chipRows(at: .large, "Muscle: ") == [5, 1])
            #expect(chipRows(at: .large, "Equipment: ") == [5, 1])
            #expect(chipRows(at: .accessibility3, "Muscle: ") == [3, 2, 1])
            #expect(chipRows(at: .accessibility3, "Equipment: ") == [3, 2, 1])
        }
    }
#endif
