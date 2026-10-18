#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    import LedgerDesign
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F10 S7a, criteria 1, 4, 7, 10 and 40: the "End workout?" sheet as it is drawn. Its VoiceOver stops
    /// and what its controls send; that the real sheet is its pinned part over one scroll view; and its
    /// references. Trees and references are taken from `FinishSheetParts`. Its layout in every setting
    /// and where it is orange are `FinishSheetLayoutTests`'.
    /// (`SceneLessWindow` is internal to `LedgerSnapshotTesting`, hence the `@testable` import.)
    @Suite("End workout? sheet", .serialized, .tags(.feature))
    struct FinishSheetTests {
        nonisolated static let sizes = WorkoutPageLayoutTests.sizes

        /// The sheet's stops, in reading order. A control that does not answer is dimmed; while a save
        /// runs the whole sheet is, its two texts included.
        static func tree(_ summary: String, canSave: Bool = true, isEnabled: Bool = true) -> [Stop] {
            let off: UIAccessibilityTraits = isEnabled ? [] : .notEnabled
            return [
                Stop("End workout?", [.header, .staticText, off]),
                Stop("Keep lifting", [.button, off]),
                Stop(summary, [.staticText, off]),
                Stop("Save workout", canSave ? .button : [.button, .notEnabled]),
                Stop("Discard", [.button, off])
            ]
        }

        static let trees: [FinishSheetPreview: [Stop]] = [
            .withSets: tree("6 of 18 sets logged, 5,578 lb moved"),
            .zeroSets: tree("0 of 18 sets logged, 0 lb moved", canSave: false),
            .kilograms: tree("1 of 19 sets logged, 160 kg moved"),
            .saving: tree("6 of 18 sets logged, 5,578 lb moved", canSave: false, isEnabled: false)
        ]

        /// A sheet whose numbers are as long as they get.
        static func longWords() throws -> WorkoutFinishModel {
            var workout = try Fixtures.seedSession()
            workout.exercises[0].sets = (0 ..< 1250).map { index in
                LoggedSet(
                    id: .derived(from: workout.exercises[0].id, index: index),
                    weight: .pounds(200),
                    reps: Reps(clamping: 5),
                    kind: .working,
                    doneAt: index < 1234 ? workout.startedAt : nil
                )
            }
            return WorkoutPresentation.finishSheet(workout, isSaving: false, locale: Fixtures.locale)
        }

        static func models() throws -> [WorkoutFinishModel] {
            try FinishSheetPreview.allCases.map { try #require($0.model) } + [longWords()]
        }

        // MARK: Criterion 40: what it reads; criteria 1, 4, 7 and 10: what it sends

        @Test("Every state of the sheet has exactly its intended tree", arguments: FinishSheetPreview.allCases)
        func tree_isExactlyTheTable(_ preview: FinishSheetPreview) throws {
            for appearance in WorkoutAccessibilityTests.appearances {
                let found = try FinishSheetParts(preview).accessibilityElements(appearance).map {
                    Stop($0.label, value: $0.value, $0.traits)
                }
                let difference = try firstDifference(found: found, expected: #require(Self.trees[preview]))
                #expect(difference == nil, "\(preview.rawValue) at \(appearance)")
            }
        }

        @Test("The line is one stop, and VoiceOver hears a comma where the eye sees a dot")
        func line_isOneStop() throws {
            let model = try #require(FinishSheetPreview.withSets.model)
            #expect(model.summary == "6 of 18 sets logged · 5,578 lb moved")
            let spoken = FinishSheetParts(model: model).accessibilityElements().map(\.label)
            #expect(spoken.filter { $0.contains("sets logged") } == ["6 of 18 sets logged, 5,578 lb moved"])
        }

        /// What activating every button of the sheet sends, in reading order, then VoiceOver's escape.
        static func sent(by preview: FinishSheetPreview) throws -> (sent: [WorkoutAction], escaped: Bool) {
            var sent: [WorkoutAction] = []
            let escaped = try FinishSheetParts(preview) { sent.append($0) }.withAccessibilityElements { elements in
                for element in elements where element.accessibilityTraits.contains(.button) {
                    _ = element.accessibilityActivate()
                }
                return elements.first?.accessibilityPerformEscape() ?? false
            }
            return (sent, escaped)
        }

        @Test("Keep lifting, Save workout and Discard each send their own action, once; the escape is Keep lifting")
        func controls_sendTheirActions() throws {
            let withSets = try Self.sent(by: .withSets)
            #expect(withSets.sent == [.keepLifting, .save, .discard, .keepLifting])
            #expect(withSets.escaped)
        }

        @Test("With no set logged Save workout sends nothing; Discard and Keep lifting answer")
        func zeroSets_saveSendsNothing() throws {
            #expect(try Self.sent(by: .zeroSets).sent == [.keepLifting, .discard, .keepLifting])
        }

        @Test("While it saves no button of the sheet sends anything")
        func saving_buttonsSendNothing() throws {
            // The escape still reaches the store, which answers nothing while it saves (`WorkoutStoreSaveTests`).
            #expect(try Self.sent(by: .saving).sent.filter { $0 != .keepLifting } == [])
            #expect(try Self.sent(by: .saving).sent.count <= 1)
        }

        // MARK: Criterion 38: the real sheet scrolls

        @Test("The sheet itself is its title and Keep lifting pinned over one scroll view", arguments: [
            DynamicTypeSize.large, .accessibility5
        ])
        func sheet_isOneScrollViewUnderItsTitle(_ size: DynamicTypeSize) throws {
            let model = try #require(FinishSheetPreview.withSets.model)
            let sheet = FinishSheet(model: model) { _ in }.frame(height: 437)
            let pinned = sheet.accessibilityElements(SnapshotAppearance(.light, size), outsideScrollViews: true)
            #expect(pinned.map(\.label) == ["End workout?", "Keep lifting"])
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

        private func alone(_ preview: FinishSheetPreview) throws -> some View {
            try FinishSheetParts(preview).frame(width: SnapshotConfig.phoneWidth)
        }

        @Test("The sheet with sets logged matches its references")
        func sheet_withSets_matchesReferences() throws {
            try assertLedgerSnapshot(of: alone(.withSets), devices: [.phone], typeSizes: [.large, .xLarge])
        }

        @Test("The sheet with no set logged matches its references: Save workout is grey")
        func sheet_zeroSets_matchesReferences() throws {
            try assertLedgerSnapshot(of: alone(.zeroSets), devices: [.phone], typeSizes: [.large])
        }

        @Test("The sheet at the largest text size of the matrix: Keep lifting under the title, the line wrapped")
        func sheet_withSets_accessibility3_matchesReference() throws {
            try assertLedgerSnapshot(
                of: alone(.withSets),
                devices: [.phone],
                themes: [.dark],
                typeSizes: [.accessibility3]
            )
        }
    }
#endif
