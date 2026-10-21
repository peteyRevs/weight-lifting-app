#if os(iOS) && DEBUG
    @testable import FeatureLibrary
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F12 S1, N7: the intended VoiceOver tree of each state of the Library, pinned exactly (the stops, their
    /// order, labels, values, and which are headings and selected), the 44 pt targets, and what each control sends.
    /// Read through UIKit's accessibility tree, as VoiceOver reads it, from the parts (`LibraryParts`): the screen
    /// puts its page in a scroll view, which the hosted reader cannot see inside (testing-strategy §2.6). The
    /// search field is a `UITextField`, which the hosted reader does not hand over (F11's `ProgramTextFieldTests`);
    /// its label is pinned by the nightly UI test.
    ///
    /// Each state is read at every text size of `sizes`, which the hosted PR runner cuts to its representatives
    /// (`TestSweep`, ruling R6).
    @Suite("Library accessibility", .serialized, .tags(.feature))
    struct LibraryAccessibilityTests {
        nonisolated static let sizes = TestSweep.sizes([.xSmall, .large, .xxxLarge, .accessibility3, .accessibility5])

        /// The title and "New exercise", then the two rows of chips with `muscle` and `equipment` chosen.
        nonisolated static func top(muscle: String = "All", equipment: String = "All") -> [ViewStop] {
            [.heading("Library"), .button("New exercise")]
                + ["All", "Chest", "Back", "Shoulders", "Legs", "Arms"].map {
                    .button("Muscle: \($0)", selected: $0 == muscle)
                }
                + ["All", "Barbell", "Dumbbell", "Cable", "Machine", "Bodyweight"].map {
                    .button("Equipment: \($0)", selected: $0 == equipment)
                }
        }

        /// A section's heading, then each row as one button: the name, with the meta and the PR as its value.
        nonisolated static func section(_ section: LibraryModel.Section) -> [ViewStop] {
            [.heading(section.title)] + section.rows.map { .button($0.name, value: $0.spokenValue) }
        }

        /// The tree each state is written to have.
        static func tree(_ preview: LibraryPreview) throws -> [ViewStop] {
            switch preview {
            case .populated, .noHistory:
                try top() + preview.model().sections.flatMap(section)
            case .filtered:
                try top(muscle: "Back", equipment: "Machine") + preview.model().sections.flatMap(section)
            case .emptySearch:
                top() + [.text("Nothing matches that filter."), .button("Clear filters")]
            case .noExercises:
                top() + [.text("No exercises yet."), .button("New exercise")]
            }
        }

        @Test(
            "N7. Every state has exactly its intended VoiceOver tree, at every text size",
            arguments: LibraryPreview.allCases, sizes
        )
        func tree_isExactlyTheTable(_ preview: LibraryPreview, _ size: DynamicTypeSize) throws {
            let found = LibraryParts(preview: preview).stops(SnapshotAppearance(.light, size))
            let difference = try firstDifference(found: found, expected: Self.tree(preview))
            #expect(difference == nil, "\(preview.rawValue) at \(size)")
        }

        @Test("N7. The populated rows read as the criterion writes them, a PR in pounds last")
        func populatedRows_readTheirMetaAndPR() throws {
            let stops = LibraryParts(preview: .populated).stops()
            let recent = try #require(stops.firstIndex(of: .heading("RECENTLY LOGGED")))
            let first = stops[recent + 1]
            #expect(first.kind == .button)
            #expect(first.value.hasSuffix(" pounds") && first.value.contains(" sessions, PR "), "\(first)")
            #expect(!stops.contains { $0.label == "—" || $0.value.contains("—") }, "a dash is never read")
        }

        @Test("Every button is a target of at least 44 by 44 points", arguments: LibraryPreview.allCases, sizes)
        func targets_areAtLeast44Points(_ preview: LibraryPreview, _ size: DynamicTypeSize) {
            let targets = LibraryParts(preview: preview).placedStops(SnapshotAppearance(.dark, size))
                .filter { $0.stop.kind == .button }
            #expect(targets.count >= 13)
            for target in targets {
                #expect(
                    target.frame.width >= 44 - 0.001 && target.frame.height >= 44 - 0.001,
                    "\(target.stop) at \(size): \(target.frame.size)"
                )
            }
        }

        @Test("Each control sends the action its model carries: every chip, New exercise, a row, Clear filters")
        func controls_sendTheirModelsActions() throws {
            var sent: [LibraryAction] = []
            LibraryParts(preview: .emptySearch, send: { sent.append($0) }).withAccessibilityElements { elements in
                for element in elements where element.accessibilityTraits.contains(.button) {
                    _ = element.accessibilityActivate()
                }
            }
            let muscles = [nil] + ExerciseSearch.MuscleFilter.allCases.map(Optional.some)
            let equipment = [nil] + ExerciseSearch.equipmentFilters.map(Optional.some)
            #expect(sent == [.newExercise] + muscles.map(LibraryAction.setMuscle) + equipment
                .map(LibraryAction.setEquipment)
                + [.clearFilters])
            var tapped: [LibraryAction] = []
            LibraryParts(preview: .filtered, send: { tapped.append($0) }).withAccessibilityElements { elements in
                _ = elements.last?.accessibilityActivate()
            }
            let row = try LibraryFixtures.exercise(named: "Chest-Supported Row")
            #expect(tapped == [.route(.exercise(row.id))])
        }
    }
#endif
