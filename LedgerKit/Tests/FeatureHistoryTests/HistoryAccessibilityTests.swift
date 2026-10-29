#if os(iOS) && DEBUG
    @testable import FeatureHistory
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F13 S1, N7: the intended VoiceOver tree of each state of the History list, pinned exactly (the stops, their
    /// order, labels and values, and which are headings), the 44 pt targets, and what each control sends. Read through
    /// UIKit's accessibility tree, as VoiceOver reads it, from the parts (`HistoryParts`): the screen puts its page in
    /// a scroll view, which the hosted reader cannot see inside (testing-strategy §2.6).
    ///
    /// Each state is read at every text size of `sizes`, which the hosted PR runner cuts to its representatives
    /// (`TestSweep`, ruling R6).
    @Suite("History accessibility", .serialized, .tags(.feature))
    struct HistoryAccessibilityTests {
        nonisolated static let sizes = TestSweep.sizes([.xSmall, .large, .xxxLarge, .accessibility3, .accessibility5])

        /// The tree each state is written to have: the title, then each week's header, a heading, and its rows, each
        /// one button reading the name, with the meta and the badge as its value; or the empty state.
        static func tree(_ preview: HistoryPreview) throws -> [ViewStop] {
            let model = try preview.model()
            switch model.content {
            case let .weeks(weeks):
                return [.heading("History")] + weeks.flatMap { week in
                    [.heading(week.title)] + week.rows.map { .button($0.name, value: $0.spokenValue) }
                }
            case .empty:
                return [
                    .heading("History"), .heading("No workouts yet."), .text("Finish a workout and it shows up here."),
                    .button("Go to Today")
                ]
            }
        }

        @Test(
            "N7. Every state has exactly its intended VoiceOver tree, at every text size",
            arguments: HistoryPreview.allCases, sizes
        )
        func tree_isExactlyTheTable(_ preview: HistoryPreview, _ size: DynamicTypeSize) throws {
            let found = HistoryParts(preview: preview).stops(SnapshotAppearance(.light, size))
            let difference = try firstDifference(found: found, expected: Self.tree(preview))
            #expect(difference == nil, "\(preview.rawValue) at \(size)")
        }

        @Test("N7. A row reads as the criterion writes it: its weekday, minutes and pounds in words, its records last")
        func rows_readTheirWords() throws {
            let stops = HistoryParts(preview: .populated).stops()
            let rows = stops.filter { $0.kind == .button }
            let withRecords = try #require(rows.first { $0.value.hasSuffix(" PR") || $0.value.hasSuffix(" PRs") })
            #expect(
                withRecords.value.contains(" minutes, ") && withRecords.value.contains(" pounds, "),
                "\(withRecords)"
            )
            #expect(!stops.contains { $0.value.contains(" lb") || $0.value.contains(" · ") }, "no drawn abbreviation")
            #expect(try HistoryPreview.populated.model().weeks.allSatisfy { stops.contains(.heading($0.title)) })
        }

        @Test("Every button is a target of at least 44 by 44 points", arguments: HistoryPreview.allCases, sizes)
        func targets_areAtLeast44Points(_ preview: HistoryPreview, _ size: DynamicTypeSize) {
            let targets = HistoryParts(preview: preview).placedStops(SnapshotAppearance(.dark, size))
                .filter { $0.stop.kind == .button }
            #expect(!targets.isEmpty)
            for target in targets {
                #expect(
                    target.frame.width >= 44 - 0.001 && target.frame.height >= 44 - 0.001,
                    "\(target.stop) at \(size): \(target.frame.size)"
                )
            }
        }

        @Test("Each control sends the route its model carries: every row, and Go to Today")
        func controls_sendTheirModelsRoutes() throws {
            var sent: [HistoryRoute] = []
            HistoryParts(preview: .populated, send: { sent.append($0) }).withAccessibilityElements { elements in
                for element in elements where element.accessibilityTraits.contains(.button) {
                    _ = element.accessibilityActivate()
                }
            }
            let everyRow = try sent == HistoryPreview.populated.model().rows.map(\.route)
            #expect(everyRow, "\(sent.count) routes")
            var tapped: [HistoryRoute] = []
            HistoryParts(preview: .empty, send: { tapped.append($0) }).withAccessibilityElements { elements in
                _ = elements.last?.accessibilityActivate()
            }
            #expect(tapped == [.today])
        }
    }
#endif
