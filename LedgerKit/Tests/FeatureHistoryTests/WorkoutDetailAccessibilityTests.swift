#if os(iOS) && DEBUG
    @testable import FeatureHistory
    import LedgerDesign
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F13 S2, criteria 3 and 8: the intended VoiceOver tree of each state of a past workout's detail, pinned exactly
    /// (the stops, their order, labels and values, and which are headings), the 44 pt targets, and what each control
    /// sends. Read through UIKit's accessibility tree from the parts (`DetailParts`): the screen puts its page in a
    /// scroll view, which the hosted reader cannot see inside (testing-strategy §2.6).
    ///
    /// Each state is read at every text size of `sizes`, which the hosted PR runner cuts to its representatives
    /// (`TestSweep`, ruling R6).
    @Suite("Workout detail accessibility", .serialized, .tags(.feature))
    struct WorkoutDetailAccessibilityTests {
        nonisolated static let sizes = TestSweep.sizes([.xSmall, .large, .xxxLarge, .accessibility3, .accessibility5])

        /// The tree each state is written to have: the day, the name as a heading, each tile as one stop, the
        /// records line when there is one, "LOGGED" as a heading, each exercise as one button, then "Delete
        /// workout"; or the unreadable workout's line under its heading, then "Delete workout". "Prescribed on the
        /// right" is no stop.
        static func tree(_ preview: DetailPreview) throws -> [ViewStop] {
            guard preview != .unreadable else {
                return [
                    .heading("This workout can't be read."),
                    .text("It stays in your history. You can still delete it."),
                    .button("Delete workout")
                ]
            }
            let model = try preview.model()
            return [.text(model.date), .heading(model.title)]
                + model.receipt.tiles.map { .text($0.spoken) }
                + (model.receipt.records.map { [.text($0)] } ?? [])
                + [.heading("LOGGED")]
                + model.receipt.rows.map { .button($0.spoken) }
                + [.button("Delete workout")]
        }

        @Test(
            "3. Every state has exactly its intended VoiceOver tree, at every text size",
            arguments: DetailPreview.allCases, sizes
        )
        func tree_isExactlyTheTable(_ preview: DetailPreview, _ size: DynamicTypeSize) throws {
            let found = DetailParts(preview: preview).stops(SnapshotAppearance(.light, size))
            let difference = try firstDifference(found: found, expected: Self.tree(preview))
            #expect(difference == nil, "\(preview.rawValue) at \(size)")
        }

        @Test("3. The detail reads its weights in the lifter's units, in words where they are spoken")
        func tree_readsTheLiftersUnits() {
            let pounds = DetailParts(preview: .withRecords).stops()
            let kilograms = DetailParts(preview: .kilograms).stops()
            #expect(pounds.contains { $0.label.hasSuffix(" lb moved") })
            #expect(kilograms.contains { $0.label.hasSuffix(" kg moved") })
            #expect(!kilograms.contains { $0.label.contains(" lb") }, "no pound is left in kilograms")
        }

        @Test("Every button is a target of at least 44 by 44 points", arguments: DetailPreview.allCases, sizes)
        func targets_areAtLeast44Points(_ preview: DetailPreview, _ size: DynamicTypeSize) {
            let targets = DetailParts(preview: preview).placedStops(SnapshotAppearance(.dark, size))
                .filter { $0.stop.kind == .button }
            #expect(!targets.isEmpty)
            for target in targets {
                #expect(
                    target.frame.width >= 44 - 0.001 && target.frame.height >= 44 - 0.001,
                    "\(target.stop) at \(size): \(target.frame.size)"
                )
            }
        }

        @Test("Each row sends its exercise's history; Delete workout sends nothing until its alert is answered")
        func controls_sendTheirModelsRoutes() throws {
            var sent: [HistoryRoute] = []
            var deletes = 0
            let parts = DetailParts(preview: .withRecords, send: { sent.append($0) }, onDelete: { deletes += 1 })
            parts.withAccessibilityElements { elements in
                for element in elements where element.accessibilityTraits.contains(.button) {
                    _ = element.accessibilityActivate()
                }
            }
            let everyRow = try sent == DetailPreview.withRecords.model().rowRoutes
            #expect(everyRow, "\(sent.count) routes")
            #expect(deletes == 0, "the button only asks")
        }
    }
#endif
