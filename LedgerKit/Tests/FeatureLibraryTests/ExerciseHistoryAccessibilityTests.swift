#if os(iOS) && DEBUG
    import Accessibility
    @testable import FeatureLibrary
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F12 S2, criterion 12 and N12: the VoiceOver tree of each history preview, pinned exactly at every size of
    /// `sizes` (cut to its representatives on the hosted PR runner, ruling R6), the 44 pt targets, what each
    /// session sends, and the chart's descriptor, read from `makeChartDescriptor()` (plan risk R3: the hosted
    /// reader does not hand the descriptor over).
    @Suite("Exercise history accessibility", .serialized, .tags(.feature))
    struct ExerciseHistoryAccessibilityTests {
        nonisolated static let sizes = TestSweep.sizes([.xSmall, .large, .xxxLarge, .accessibility3, .accessibility5])

        /// The tree each preview is written to have at `size`.
        static func tree(_ preview: HistoryPreview, _ size: DynamicTypeSize) throws -> [ViewStop] {
            let model = try preview.model()
            let stats = model.stats.map { ViewStop.text($0.spoken ?? "\($0.value)\($0.unit ?? ""), \($0.caption)") }
            let delta = model.chart.delta.map { [ViewStop.text($0)] } ?? []
            let chart: [ViewStop] = if let empty = model.chart.empty {
                [.text(empty)]
            } else if size.isAccessibilitySize {
                model.chart.bars.map { .text("\($0.week), \($0.value)") }
            } else {
                [ViewStop(kind: .field, label: model.chart.spokenTitle, value: model.chart.spokenSummary ?? "")]
            }
            let log = model.log.empty.map { [ViewStop.text($0)] } ?? model.log.entries.map {
                .button($0.date, value: $0.spokenValue)
            }
            return [.text(model.eyebrow), .heading(model.title)] + stats + [.heading(model.chart.title)] + delta
                + chart + [.heading(model.log.title)] + log
        }

        @Test(
            "12, N12. Every history has exactly its intended VoiceOver tree, at every size",
            arguments: HistoryPreview.allCases, sizes
        )
        func tree_isExactlyTheTable(_ preview: HistoryPreview, _ size: DynamicTypeSize) throws {
            let found = HistoryParts(preview: preview).stops(SnapshotAppearance(.light, size))
            let difference = try firstDifference(found: found, expected: Self.tree(preview, size))
            #expect(difference == nil, "\(preview.rawValue) at \(size)")
        }

        @Test("Every session is a target of at least 44 by 44 points", arguments: sizes)
        func targets_areAtLeast44Points(_ size: DynamicTypeSize) {
            let targets = HistoryParts(preview: .logged).placedStops(SnapshotAppearance(.dark, size))
                .filter { $0.stop.kind == .button }
            #expect(targets.count >= 5)
            for target in targets {
                let frame = target.frame
                #expect(frame.width >= 44 - 0.001 && frame.height >= 44 - 0.001, "\(target.stop) at \(size)")
            }
        }

        @Test("11. Each session sends its workout's route")
        func sessions_sendTheirRoutes() throws {
            var sent: [LibraryRoute] = []
            HistoryParts(preview: .logged, send: { sent.append($0) }).withAccessibilityElements { elements in
                for element in elements where element.accessibilityTraits.contains(.button) {
                    _ = element.accessibilityActivate()
                }
            }
            #expect(try sent == HistoryPreview.logged.model().log.entries.map(\.route))
        }

        @Test("12. The chart's descriptor reads every week with a value, by its label, and leaves out the empty weeks")
        func descriptor_readsTheWeeksValues() throws {
            let chart = try HistoryPreview.gaps.model().chart
            let descriptor = E1RMChartDescriptor(chart: chart).makeChartDescriptor()
            #expect(descriptor.title == "Estimated 1RM by week")
            let weeks = try #require(descriptor.xAxis as? AXCategoricalDataAxisDescriptor)
            #expect(weeks.title == "Week" && weeks.categoryOrder == chart.bars.map(\.week))
            #expect(descriptor.yAxis?.title == "Pounds")
            let points = try #require(descriptor.series.first?.dataPoints)
            let shown = chart.bars.filter { $0.number != nil }
            // A point's values are refined for Swift out of reach; its label is the week's value as drawn.
            #expect(points.count == 6 && shown.count == 6, "W3 and W6 have no point")
            #expect(points.map(\.label) == shown.map(\.value))
        }
    }
#endif
