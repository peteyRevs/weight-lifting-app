#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    import LedgerDesign
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F10 S7b, criteria 26, 27 and 40: the receipt as it is drawn. Its VoiceOver stops and what "Done"
    /// sends; that the real screen is its header pinned over one scroll view; and its references. Trees and
    /// references are taken from `ReceiptParts`. Its layout in every setting and where it is orange are
    /// `ReceiptLayoutTests`'.
    @Suite("Receipt", .serialized, .tags(.feature))
    struct ReceiptTests {
        /// The receipt's stops, in reading order: the header, the tiles, the records line when there is one,
        /// "LOGGED", then each exercise. "Prescribed on the right" is no stop.
        static func tree(_ model: ReceiptScreenModel) -> [Stop] {
            [
                Stop(model.header.date, .staticText),
                Stop(model.header.title, [.header, .staticText]),
                Stop("Done", .button)
            ] + model.page.tiles.map { Stop($0.spoken, .staticText) }
                + (model.page.records.map { [Stop($0, .staticText)] } ?? [])
                + [Stop("LOGGED", [.header, .staticText])]
                + model.page.rows.map { Stop($0.spoken, .staticText) }
        }

        /// The tree of `withRecords` as criterion 40 writes it, word for word.
        static let withRecords: [Stop] = [
            Stop("Wednesday, September 16", .staticText),
            Stop("Upper A — Push focus", [.header, .staticText]),
            Stop("Done", .button),
            Stop("TIME, 24 minutes, 22 seconds", .staticText),
            Stop("6 of 18 sets logged", .staticText),
            Stop("5,578 lb moved", .staticText),
            Stop("1 new PR this session", .staticText),
            Stop("LOGGED", [.header, .staticText]),
            Stop("Barbell Bench Press, Prescribed 5 × 5 @ 200 lb, Logged 5 × 200×5", .staticText),
            Stop("Incline DB Press, Prescribed 3 × 11 @ 52.5 lb, Logged 52.5×11", .staticText),
            Stop("Chest-Supported Row, Prescribed 4 × 8 @ 75 lb, Nothing logged", .staticText),
            Stop("Lat Pulldown, Prescribed 3 × 13 @ 102.5 lb, Nothing logged", .staticText),
            Stop("Cable Lateral Raise, Prescribed 3 × 16 @ 15 lb, Nothing logged", .staticText)
        ]

        // MARK: Criterion 40: what it reads; criterion 26: what Done sends

        @Test("The receipt with a record reads exactly as criterion 40 writes it")
        func tree_withRecords_isCriterion40s() throws {
            for appearance in WorkoutAccessibilityTests.appearances {
                let found = try ReceiptParts(.withRecords).accessibilityElements(appearance).map {
                    Stop($0.label, value: $0.value, $0.traits)
                }
                #expect(firstDifference(found: found, expected: Self.withRecords) == nil, "\(appearance)")
            }
        }

        @Test("Every receipt has exactly its intended tree", arguments: ReceiptPreview.allCases)
        func tree_isExactlyTheTable(_ preview: ReceiptPreview) throws {
            let model = try #require(preview.model)
            for appearance in WorkoutAccessibilityTests.appearances {
                let found = ReceiptParts(model: model).accessibilityElements(appearance).map {
                    Stop($0.label, value: $0.value, $0.traits)
                }
                #expect(firstDifference(found: found, expected: Self.tree(model)) == nil, "\(preview) at \(appearance)")
            }
        }

        @Test("Done sends .done, once, and is the receipt's one control")
        func done_sendsDone() throws {
            var sent: [WorkoutAction] = []
            let buttons = try ReceiptParts(.withRecords) { sent.append($0) }.withAccessibilityElements { elements in
                let buttons = elements.filter { $0.accessibilityTraits.contains(.button) }
                for button in buttons {
                    _ = button.accessibilityActivate()
                }
                return buttons.count
            }
            #expect(buttons == 1)
            #expect(sent == [.done])
        }

        // MARK: Criterion 27: the real screen scrolls

        @Test("The receipt itself is its header pinned over one scroll view", arguments: [
            DynamicTypeSize.large, .accessibility5
        ])
        func screen_isOneScrollViewUnderItsHeader(_ size: DynamicTypeSize) throws {
            let model = try #require(ReceiptPreview.withRecords.model)
            let screen = WorkoutScreen(model: .receipt(model)) { _ in }.frame(height: 874)
            let pinned = screen.accessibilityElements(SnapshotAppearance(.light, size), outsideScrollViews: true)
            #expect(pinned.map(\.label) == ["Wednesday, September 16", "Upper A — Push focus", "Done"])
            let host = UIHostingController(rootView: screen.environment(\.dynamicTypeSize, size))
            let window = SceneLessWindow.make(frame: CGRect(x: 0, y: 0, width: SnapshotConfig.phoneWidth, height: 874))
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

        private func alone(_ preview: ReceiptPreview) throws -> some View {
            try ReceiptParts(preview).frame(width: SnapshotConfig.phoneWidth)
        }

        @Test("The receipt in each state matches its references", arguments: ReceiptPreview.allCases)
        func receipt_matchesReferences(_ preview: ReceiptPreview) throws {
            try assertLedgerSnapshot(
                of: alone(preview),
                named: preview.snapshotName,
                devices: [.phone],
                typeSizes: [.large, .xLarge]
            )
        }

        @Test("The receipt at the largest text size of the matrix: tiles one per row, Done under the name")
        func receipt_accessibility3_matchesReference() throws {
            try assertLedgerSnapshot(
                of: alone(.withRecords),
                devices: [.phone],
                themes: [.dark],
                typeSizes: [.accessibility3]
            )
        }
    }

    extension ReceiptPreview {
        /// The name of the case's references.
        var snapshotName: String {
            switch self {
            case .withRecords: "withRecords"
            case .noRecords: "noRecords"
            case .kilograms: "kilograms"
            }
        }
    }
#endif
