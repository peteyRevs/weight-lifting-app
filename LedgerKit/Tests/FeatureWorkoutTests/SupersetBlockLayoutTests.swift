#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    @testable import LedgerDesign
    import LedgerDomain
    import LedgerFakes
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F10 S9, criterion 21: a superset's block in every setting. Nothing of it is cut, leaves the phone or lies
    /// over something else from the default size to the largest, on a 375 pt phone and an iPhone 17, with Bold
    /// Text and right to left (by measurement, `WorkoutLayoutProbe`, the cut check of
    /// `ProgramViewsCutAdversarialTests`' kind); "B10" and "BD" fit their column; a legend row's name never
    /// stands under its swap button; and every target, the legend rows and the swap buttons included, is 44 pt.
    @Suite("Superset block layout", .serialized, .tags(.feature))
    struct SupersetBlockLayoutTests {
        nonisolated static let sizes = WorkoutPageLayoutTests.sizes

        /// Upper A on its superset, B with ten working rows and a drop set, both members with long names and a
        /// last workout; B's row chosen, so that A's swap button is drawn.
        static func longWords() throws -> WorkoutPageModel {
            var workout = try Fixtures.seedSession()
            workout.exercises[3].name = "Single-Arm Half-Kneeling Lat Pulldown with a Three-Second Pause"
            workout.exercises[4].name = "Cable Y-Raise Lateral Raise from a Low Pulley, Behind the Back"
            let raise = workout.exercises[4]
            for index in raise.sets.count ..< 10 {
                workout.exercises[4].sets.append(LoggedSet(
                    id: .derived(from: raise.id, index: index), weight: .pounds(1247.5), reps: Reps(clamping: 25),
                    kind: .added
                ))
            }
            workout.exercises[4].sets.append(LoggedSet(
                id: .derived(from: raise.id, index: 10), weight: .pounds(1242.5), reps: Reps(clamping: 25), kind: .drop
            ))
            for index in [3, 4] {
                workout.exercises[index].lastPerformance = LastPerformance(
                    date: workout.startedAt.addingTimeInterval(-7 * 24 * 3600), sets: 12, reps: 25,
                    load: .pounds(1242.5)
                )
            }
            let chosen = WorkoutSelection(exerciseIndex: 4, setID: workout.exercises[4].sets[9].id)
            return WorkoutPresentation.page(
                workout,
                selection: chosen,
                isBusy: false,
                WorkoutPresentation.Context(locale: Fixtures.locale, calendar: Fixtures.calendar)
            )
        }

        static func models() throws -> [WorkoutPageModel] {
            try [WorkoutPageLayoutTests.page(.supersetRound2), WorkoutPageLayoutTests.page(.dropSet), longWords()]
        }

        // MARK: Nothing cut, nothing out of reach

        @Test("No word of the block or of the list is cut, in any setting", arguments: sizes)
        func block_noWordIsCut(_ size: DynamicTypeSize) throws {
            for model in try Self.models() {
                let cut = WorkoutPageLayoutTests.cut(model, at: size)
                #expect(cut.isEmpty, "\(cut.count) cut: \(cut.prefix(3).joined(separator: "; "))")
            }
        }

        @Test("Every stop of the block is inside the phone, and none lies over another", arguments: sizes)
        func block_nothingLeavesOrOverlaps(_ size: DynamicTypeSize) throws {
            for model in try Self.models() {
                let misplaced = WorkoutPageLayoutTests.misplaced(model, at: size)
                #expect(misplaced.isEmpty, "\(misplaced.count): \(misplaced.prefix(3).joined(separator: "; "))")
            }
        }

        @Test(
            "Every control of the block, the legend rows and the swap buttons included, is a 44 pt target",
            arguments: sizes
        )
        func block_controlsAre44Points(_ size: DynamicTypeSize) throws {
            let model = try Self.longWords()
            let block = try #require(model.block)
            let page = WorkoutPage(model: model) { _ in }
            for setting in LayoutSetting.sweep(size) {
                let controls = setting.elements(of: page).filter { !$0.traits.isDisjoint(with: [.button, .adjustable]) }
                let swaps = block.legend.count { $0.swap != nil }
                let expected = block.legend.count + swaps + 1 + block.rows.count * 2 + 2 + 1
                    + (model.remaining?.rows.count ?? 0)
                #expect(controls.count == expected, "\(setting.testDescription)")
                let small = controls.filter { $0.frame.width < 44 - 0.001 || $0.frame.height < 44 - 0.001 }
                #expect(small.isEmpty, "\(setting.testDescription): \(small.map(\.label))")
            }
        }

        /// A legend row and its swap button: side by side, or the button under the row, never the row under
        /// the button; at the accessibility sizes the button stands under the row.
        @Test("A legend row's name never stands under its swap button", arguments: sizes)
        func legend_nameNeverUnderTheSwapButton(_ size: DynamicTypeSize) throws {
            let model = try Self.longWords()
            let row = try #require(model.block?.legend.first { $0.swap != nil })
            let swap = try #require(row.swap)
            let page = WorkoutPage(model: model) { _ in }
            for setting in LayoutSetting.sweep(size) {
                let stops = setting.elements(of: page)
                let legend = try #require(stops.first { $0.label == row.spoken }).frame
                let button = try #require(stops.first { $0.label == swap }).frame
                let isBeside = legend.maxX <= button.minX + 0.5 || button.maxX <= legend.minX + 0.5
                let isBelow = button.minY >= legend.maxY - 0.5
                #expect(isBeside || isBelow, "\(setting.testDescription): \(legend) and \(button)")
                if size.isAccessibilitySize {
                    #expect(isBelow, "\(setting.testDescription): at an accessibility size the button is under the row")
                }
            }
        }

        /// The row labels of a block are a letter and digits: the widest a lifter meets, "B10" and "BD", stand
        /// on one line in the label column at every size, plain and bold.
        @Test("B10 and BD fit the label column on one line", arguments: sizes)
        func rowLabels_fitTheirColumn(_ size: DynamicTypeSize) {
            let column = LedgerFont.scaledSize(.caption, dynamicTypeSize: size) * SetColumns<Text, Text, Text>
                .labelColumnEms
            for label in ["B10", "BD", "A12"] {
                for weight in [LegibilityWeight.regular, .bold] {
                    let text = Text(label).ledgerFont(.caption)
                        .environment(\.dynamicTypeSize, size)
                        .environment(\.legibilityWeight, weight)
                    let width = UIHostingController(rootView: text).sizeThatFits(in: CGSize(width: 1000, height: 1000))
                        .width
                    #expect(width <= column + 0.5, "\(label) at \(size), \(weight): \(width) pt in \(column) pt")
                }
            }
        }
    }
#endif
