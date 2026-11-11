#if os(iOS) && DEBUG
    @testable import FeatureHistory
    import LedgerDesign
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F13 S3, N15 and criterion 8: the intended VoiceOver tree of each state, what each control sends, and 44 pt
    /// targets.
    @Suite("Edit sets accessibility", .serialized, .tags(.feature))
    struct EditSetsAccessibilityTests {
        nonisolated static let sizes = TestSweep.sizes([.xSmall, .large, .xxxLarge, .accessibility3, .accessibility5])

        /// The title, "Cancel", each exercise's name as a heading over its steppers, each one stop, then "Save".
        static func tree(_ preview: EditPreview) throws -> [ViewStop] {
            let model = try preview.model()
            let steppers = model.exercises.flatMap { exercise -> [ViewStop] in
                let fields = exercise.sets.flatMap { [$0.weight, $0.reps] }
                return [.heading(exercise.name)]
                    + fields.map { ViewStop.adjustable($0.label, value: $0.spokenValue) }
            }
            let problem = model.foot.problem.map { [ViewStop.text($0)] } ?? []
            let save: ViewStop = model.foot.action == nil ? .dimmedButton(model.foot.save) : .button(model.foot.save)
            return [.heading(model.title), .button(model.cancel)] + steppers + problem + [save]
        }

        @Test("Every state has exactly its intended tree, at every size", arguments: EditPreview.allCases, sizes)
        func tree_isExactlyTheTable(_ preview: EditPreview, _ size: DynamicTypeSize) throws {
            let found = EditParts(preview: preview).stops(SnapshotAppearance(.light, size))
            let difference = try firstDifference(found: found, expected: Self.tree(preview))
            #expect(difference == nil, "\(preview.rawValue) at \(size)")
        }

        @Test("N15. A stepper reads \"Set 2 weight, 190 pounds\" and \"Set 2 reps, 5\"")
        func steppers_readTheirWords() {
            let stops = EditParts(preview: .unchanged).stops()
            #expect(stops
                .contains { $0.kind == .adjustable && $0.label == "Set 2 weight" && $0.value.hasSuffix(" pounds") })
            #expect(stops.contains(.adjustable("Set 2 reps", value: "5")))
        }

        @Test("7. In kilograms the steppers read kilograms and no pound is left")
        func kilograms_read() {
            let stops = EditParts(preview: .kilograms).stops()
            #expect(stops.contains { $0.value.hasSuffix(" kilograms") })
            #expect(!stops.contains { $0.value.contains("pound") })
        }

        @Test("Each stepper's model sends its set, field and way; Save only once changed")
        func models_sendTheirActions() throws {
            let unchanged = try EditPreview.unchanged.model()
            let set = try #require(unchanged.exercises.first?.sets.first)
            #expect(set.weight.increment == .step(set.id, .weight, .upward))
            #expect(set.weight.decrement == .step(set.id, .weight, .downward))
            #expect(set.reps.increment == .step(set.id, .reps, .upward))
            #expect(unchanged.foot.action == nil)
            #expect(try EditPreview.changed.model().foot.action == .save)
        }

        @Test("Every button is a target of at least 44 by 44 points", arguments: EditPreview.allCases, sizes)
        func targets_areAtLeast44Points(_ preview: EditPreview, _ size: DynamicTypeSize) {
            let targets = EditParts(preview: preview).placedStops(SnapshotAppearance(.dark, size))
                .filter { $0.stop.kind == .button }
            #expect(!targets.isEmpty)
            for target in targets {
                #expect(
                    target.frame.width >= 44 - 0.001 && target.frame.height >= 44 - 0.001,
                    "\(target.stop) at \(size): \(target.frame.size)"
                )
            }
        }
    }

    /// F13 S3, criterion 8, by measurement: no stop is empty, outside the page, under 44 points or over another, in
    /// every
    /// state and setting; and N6: "Save" is the sheet's one orange.
    @Suite("Edit sets layout", .serialized, .tags(.feature))
    struct EditSetsLayoutTests {
        typealias Setting = HistoryLayoutTests.Setting

        @Test("In every state and setting the stops lay out sanely", arguments: EditPreview.allCases, Setting.all)
        func parts_layOutSanely(_ preview: EditPreview, _ setting: Setting) {
            let stops = HistoryLayoutTests.placed(EditParts(preview: preview), setting)
            #expect(!stops.isEmpty, "the parts were not read")
            let faults = HistoryLayoutTests.faults(in: stops)
            #expect(faults.isEmpty, "\(faults.prefix(4).joined(separator: "\n"))")
        }

        @Test(
            "N6. Save is orange once it can be tapped; the rest of the sheet is not",
            arguments: [ColorScheme.dark, .light]
        )
        func orange_isSavesAlone(_ theme: ColorScheme) throws {
            let changed = try EditPreview.changed.model()
            let page = EditSetsPage(model: changed, send: { _ in })
            #expect(try WorkoutDetailOrangeAuditTests.orangePixels(in: page, theme) == 0)
            let foot = EditSetsFoot(model: changed.foot, send: { _ in })
            #expect(try WorkoutDetailOrangeAuditTests.orangePixels(in: foot, theme) > 0)
        }
    }
#endif
