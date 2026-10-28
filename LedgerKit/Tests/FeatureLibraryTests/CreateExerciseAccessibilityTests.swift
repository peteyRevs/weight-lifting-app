#if os(iOS) && DEBUG
    @testable import FeatureLibrary
    import LedgerDesign
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F12 S3: the exercise sheet as VoiceOver reads it, pinned exactly at every text size of `sizes` (`TestSweep`,
    /// ruling R6), from its parts (`CreateParts`). The title is a heading, then "Cancel"; each field's heading; the
    /// chips of one choice are buttons, the chosen one selected; the secondary muscles are switches; the problem lines
    /// are text; "Save" is a button. The name field is a `UITextField`, which the hosted reader does not hand over
    /// (as F11's `ProgramTextFieldTests` say): it is found here as the one field it is, with its placeholder and text.
    @Suite("Exercise sheet accessibility", .serialized, .tags(.feature))
    struct CreateExerciseAccessibilityTests {
        nonisolated static let sizes = TestSweep.sizes([.xSmall, .large, .xxxLarge, .accessibility3, .accessibility5])

        /// The tree each state is written to have.
        static func tree(_ preview: CreatePreview) -> [ViewStop] {
            let model = preview.model()
            var stops: [ViewStop] = [.heading(model.title), .button("Cancel"), .heading("Name")]
            if let problem = model.name.problem {
                stops.append(.text(problem))
            }
            for group in model.groups {
                stops.append(.heading(group.title))
                stops += group.chips.map { chip in
                    group.allowsMany
                        ? ViewStop(kind: .toggle, label: chip.spokenLabel, value: chip.isSelected ? "1" : "0")
                        : .button(chip.spokenLabel, selected: chip.isSelected)
                }
            }
            if let problem = model.foot.problem {
                stops.append(.text(problem))
            }
            return stops + [.button("Save")]
        }

        @Test(
            "Every state has exactly its intended VoiceOver tree, at every text size",
            arguments: CreatePreview.allCases,
            sizes
        )
        func tree_isExactlyTheTable(_ preview: CreatePreview, _ size: DynamicTypeSize) {
            let found = CreateParts(preview).stops(SnapshotAppearance(.light, size))
            let difference = firstDifference(found: found, expected: Self.tree(preview))
            #expect(difference == nil, "\(preview.rawValue) at \(size)")
        }

        @Test("The secondary muscles are switches, on while chosen; no other chip is")
        func secondaryMuscles_areSwitches() {
            let stops = CreateParts(.filled).stops()
            let switches = stops.filter { $0.kind == .toggle }
            #expect(switches.count == MuscleGroup.allCases.count - 1)
            #expect(switches.filter { $0.value == "1" }.map(\.label) == [
                "Secondary muscles: Shoulders", "Secondary muscles: Triceps"
            ])
            #expect(stops.filter(\.isSelected).map(\.label) == [
                "Equipment: Barbell", "Primary muscle: Chest", "Movement pattern: Horizontal push"
            ])
        }

        @Test("Every chip and button sends the action its model carries, and Cancel closes")
        func controls_sendTheirActions() {
            var sent: [CreateExerciseAction] = []
            var cancelled = 0
            CreateParts(.filled, send: { sent.append($0) }, onCancel: { cancelled += 1 }).withAccessibilityElements {
                for element in $0 where !element.accessibilityTraits.isDisjoint(with: [.button, .toggleButton]) {
                    _ = element.accessibilityActivate()
                }
            }
            let model = CreatePreview.filled.model()
            #expect(cancelled == 1)
            #expect(sent == model.groups.flatMap(\.chips).map(\.action) + [.save])
        }

        @Test("While a save runs, Save is dimmed and sends nothing")
        func saving_dimsSave() {
            let model = CreateExercisePresentation.make(CreateExerciseInput(
                draft: CreatePreviewData.filled, isSaving: true, locale: Fixtures.locale
            ))
            var sent: [CreateExerciseAction] = []
            let stops = SheetChrome(model.title, cancel: model.cancel) {} content: {
                CreateExerciseFoot(model: model.foot) { sent.append($0) }
            }
            .stops()
            #expect(stops.last == .dimmedButton("Save"))
            #expect(sent.isEmpty)
        }

        @Test("Every button is a target of at least 44 by 44 points", arguments: CreatePreview.allCases, sizes)
        func targets_areAtLeast44Points(_ preview: CreatePreview, _ size: DynamicTypeSize) {
            let targets = CreateParts(preview).placedStops(SnapshotAppearance(.dark, size))
                .filter { $0.stop.kind == .button || $0.stop.kind == .toggle }
            #expect(targets.count >= 40)
            for target in targets {
                #expect(
                    target.frame.width >= 44 - 0.001 && target.frame.height >= 44 - 0.001,
                    "\(target.stop) at \(size): \(target.frame.size)"
                )
            }
        }

        @Test("The sheet has one text field, the name: its placeholder is Name, and it holds the name as typed")
        func nameField_isTheOneField() {
            #expect(Self.fields(of: .empty) == [["Name", ""]])
            #expect(Self.fields(of: .filled) == [["Name", LibraryPreviewData.customName]])
            #expect(Self.fields(of: .nameTaken) == [["Name", "Barbell bench press"]])
        }

        /// The placeholder and the text of each text field of a state's parts, found in the hosted view.
        static func fields(of preview: CreatePreview) -> [[String]] {
            let host = UIHostingController(rootView: CreateParts(preview))
            let window = SceneLessWindow.make(frame: CGRect(x: 0, y: 0, width: SnapshotConfig.phoneWidth, height: 874))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            func fields(in view: UIView) -> [UITextField] {
                ((view as? UITextField).map { [$0] } ?? []) + view.subviews.flatMap(fields(in:))
            }
            return fields(in: host.view).map { [$0.placeholder ?? "", $0.text ?? ""] }
        }
    }
#endif
