#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    import LedgerDesign
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F10 S8b, criteria 13, 14, 20 and 32: the swap sheet and the card's swap button as they are drawn. Their
    /// VoiceOver stops and what their controls send; that the real sheet is its pinned part over one scroll
    /// view; and the sheet's references. Trees and references are taken from `SwapSheetParts`. Its layout in
    /// every setting and where it is orange are `SwapSheetLayoutTests`'.
    /// (`SceneLessWindow` is internal to `LedgerSnapshotTesting`, hence the `@testable` import.)
    @Suite("Swap sheet", .serialized, .tags(.feature))
    struct SwapSheetTests {
        /// The bench press's eight alternatives as VoiceOver reads each row: one stop, a button.
        static let rows = [
            "Dumbbell Bench Press, Dumbbell · 15 lb, Use",
            "Smith Machine Bench Press, Machine · 40 lb, Use",
            "Weighted Dip, Bodyweight · 10 lb, Use",
            "Machine Chest Press, Machine · 40 lb, Use",
            "Barbell Floor Press, Barbell · 200 lb, Use",
            "Cable Chest Press, Cable · 30 lb, Use",
            "Decline Bench Press, Barbell · 200 lb, Use",
            "Decline Push-Up, Bodyweight, Use"
        ].map { Stop($0, .button) }

        /// The sheet's stops, in reading order: the title, "Cancel", the line, then what the state holds.
        static func tree(_ rest: [Stop]) -> [Stop] {
            [
                Stop("Swap exercise", [.header, .staticText]),
                Stop("Cancel", .button),
                Stop("Same movement pattern.", .staticText)
            ] + rest
        }

        /// "Also update program" as VoiceOver reads it: SwiftUI's own switch, its value "1" on and "0" off.
        static func toggle(isOn: Bool) -> Stop {
            Stop("Also update program", value: isOn ? "1" : "0", [.button, .toggleButton])
        }

        static let trees: [SwapSheetPreview: [Stop]] = [
            .rows: tree([toggle(isOn: false)] + rows),
            .updatingProgram: tree([toggle(isOn: true)] + rows),
            .loading: tree([]),
            .empty: tree([Stop("No alternatives for this exercise.", .staticText)]),
            .failed: tree([Stop("Couldn't load alternatives.", .staticText)])
        ]

        // MARK: Criterion 32: what it reads; criteria 18 and 20: what it sends

        @Test("Every state of the sheet has exactly its intended tree", arguments: SwapSheetPreview.allCases)
        func tree_isExactlyTheTable(_ preview: SwapSheetPreview) throws {
            for appearance in WorkoutAccessibilityTests.appearances {
                let found = try SwapSheetParts(preview).accessibilityElements(appearance).map {
                    Stop($0.label, value: $0.value, $0.traits)
                }
                let difference = try firstDifference(found: found, expected: #require(Self.trees[preview]))
                #expect(difference == nil, "\(preview.rawValue) at \(appearance)")
            }
        }

        @Test("Cancel, the switch and each row send their own action, once; the escape is Cancel")
        func controls_sendTheirActions() throws {
            let model = try #require(SwapSheetPreview.rows.model)
            var sent: [WorkoutAction] = []
            let escaped = SwapSheetParts(model: model) { sent.append($0) }.withAccessibilityElements { elements in
                for element in elements where element.accessibilityTraits.contains(.button) {
                    _ = element.accessibilityActivate()
                }
                return elements.first?.accessibilityPerformEscape() ?? false
            }
            let expected: [WorkoutAction] = [.cancelSwap, .updateProgram(true)]
                + model.rows.map { .edit($0.choose) } + [.cancelSwap]
            #expect(escaped)
            #expect(sent.count == expected.count)
            for (index, pair) in zip(sent, expected).enumerated() {
                #expect(pair.0 == pair.1, "control \(index + 1) in reading order")
            }
        }

        @Test("The card's Swap exercise follows the name, and sends openSwap; with a set logged it is not drawn")
        func cardButton_sendsOpenSwap() {
            var sent: [WorkoutAction] = []
            WorkoutParts(preview: .started) { sent.append($0) }.withAccessibilityElements { elements in
                let labels = elements.map(\.accessibilityLabel)
                let title = labels.firstIndex(of: "Barbell Bench Press")
                #expect(title.map { labels[$0 + 1] } == "Swap exercise")
                for element in elements where element.accessibilityLabel == "Swap exercise" {
                    _ = element.accessibilityActivate()
                }
            }
            #expect(sent == [.openSwap])
            let logging = WorkoutParts(preview: .logging).accessibilityElements().map(\.label)
            #expect(!logging.contains("Swap exercise"))
        }

        // MARK: Criterion 14: the real sheet scrolls

        @Test("The sheet itself is its title and Cancel pinned over one scroll view", arguments: [
            DynamicTypeSize.large, .accessibility5
        ])
        func sheet_isOneScrollViewUnderItsTitle(_ size: DynamicTypeSize) throws {
            let model = try #require(SwapSheetPreview.rows.model)
            let sheet = SwapSheet(model: model) { _ in }.frame(height: 437)
            let pinned = sheet.accessibilityElements(SnapshotAppearance(.light, size), outsideScrollViews: true)
            #expect(pinned.map(\.label) == ["Swap exercise", "Cancel"])
            let host = UIHostingController(rootView: sheet.environment(\.dynamicTypeSize, size))
            let window = SceneLessWindow.make(frame: CGRect(x: 0, y: 0, width: SnapshotConfig.phoneWidth, height: 437))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            func scrolls(in view: UIView) -> [UIScrollView] {
                ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrolls(in:))
            }
            let found = scrolls(in: host.view)
            #expect(found.count == 1)
            #expect(found.first.map { $0.contentSize.width <= $0.bounds.width + 0.5 } == true, "never sideways")
        }

        // MARK: References

        private func alone(_ preview: SwapSheetPreview) throws -> some View {
            try SwapSheetParts(preview).frame(width: SnapshotConfig.phoneWidth)
        }

        @Test("The sheet with its eight rows matches its references")
        func sheet_rows_matchesReferences() throws {
            try assertLedgerSnapshot(of: alone(.rows), devices: [.phone], typeSizes: [.large, .xLarge])
        }

        @Test("The sheet at the largest text size of the matrix: Cancel under the title, each Use under its line")
        func sheet_rows_accessibility3_matchesReference() throws {
            try assertLedgerSnapshot(of: alone(.rows), devices: [.phone], themes: [.dark], typeSizes: [.accessibility3])
        }

        @Test("The sheet with nothing to offer matches its reference")
        func sheet_empty_matchesReference() throws {
            try assertLedgerSnapshot(of: alone(.empty), devices: [.phone], themes: [.light], typeSizes: [.large])
        }
    }
#endif
