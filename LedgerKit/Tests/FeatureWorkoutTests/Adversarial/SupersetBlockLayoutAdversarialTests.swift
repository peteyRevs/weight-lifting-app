#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    import LedgerDesign
    import LedgerDomain
    import LedgerFakes
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// G2, F10 S9 criteria 20 and 21 with a block of three: Upper A with its row, pulldown and raise joined as
    /// one block, long names, and B's first row chosen so that every member has its swap button. At the default
    /// size, at accessibility3 and at accessibility5, on both phones, plain and bold, both directions: nothing is
    /// cut, leaves the phone or lies over another stop; every control, each swap button by name, is 44 pt; and
    /// VoiceOver reads the eyebrow, the round (a heading), each legend row then its own swap button, the rest
    /// line, then each row (name first) followed by its check ("Log set A1") in display order.
    @Suite("Superset block of three, layout and VoiceOver (adversarial, F10 S9)", .serialized, .tags(.feature))
    struct SupersetBlockLayoutAdversarialTests {
        nonisolated static let sizes: [DynamicTypeSize] = [.large, .accessibility3, .accessibility5]

        static func threeMembers() throws -> WorkoutPageModel {
            var workout = try Fixtures.seedSession()
            workout.exercises[3].isSupersetWithPrevious = true
            workout.exercises[2].name = "Chest-Supported Dumbbell Row with a Three-Second Pause at the Top"
            workout.exercises[3].name = "Single-Arm Half-Kneeling Lat Pulldown"
            workout.exercises[4].name = "Cable Y-Raise Lateral Raise from a Low Pulley, Behind the Back"
            let chosen = WorkoutSelection(exerciseIndex: 3, setID: workout.exercises[3].sets[0].id)
            return WorkoutPresentation.page(
                workout,
                selection: chosen,
                isBusy: false,
                WorkoutPresentation.Context(locale: Fixtures.locale, calendar: Fixtures.calendar)
            )
        }

        @Test("The model is a block of three, every member with its swap button, B current")
        func model_isABlockOfThree() throws {
            let block = try #require(try Self.threeMembers().block)
            #expect(block.legend.map(\.letter) == ["A", "B", "C"])
            #expect(block.legend.map(\.isCurrent) == [false, true, false])
            #expect(block.legend.allSatisfy { $0.swap != nil })
            #expect(block.restLine.hasSuffix("after C"))
        }

        @Test(
            "No word of a 3-member block is cut, and no stop leaves the phone or lies over another",
            arguments: sizes
        )
        func threeMembers_noCutNoOverlap(_ size: DynamicTypeSize) throws {
            let model = try Self.threeMembers()
            let cut = WorkoutPageLayoutTests.cut(model, at: size)
            #expect(cut.isEmpty, "\(cut.count) cut: \(cut.prefix(3).joined(separator: "; "))")
            let misplaced = WorkoutPageLayoutTests.misplaced(model, at: size)
            #expect(misplaced.isEmpty, "\(misplaced.count): \(misplaced.prefix(3).joined(separator: "; "))")
        }

        @Test(
            "Each legend row and each of the three swap buttons is a 44 pt target, beside or under its row",
            arguments: sizes
        )
        func threeMembers_swapButtonsAre44Points(_ size: DynamicTypeSize) throws {
            let model = try Self.threeMembers()
            let block = try #require(model.block)
            let page = WorkoutPage(model: model) { _ in }
            for setting in LayoutSetting.everySetting(size) {
                let stops = setting.elements(of: page)
                for row in block.legend {
                    let legend = try #require(stops.first { $0.label == row.spoken }, "\(setting.testDescription)")
                    let swap = try #require(stops.first { $0.label == row.swap }, "\(setting.testDescription)")
                    for (name, frame) in [(row.spoken, legend.frame), (row.swap ?? "", swap.frame)] {
                        #expect(
                            frame.width >= 44 - 0.001 && frame.height >= 44 - 0.001,
                            "\(setting.testDescription): \(name) is \(frame.size)"
                        )
                    }
                    let isBeside = legend.frame.maxX <= swap.frame.minX + 0.5
                        || swap.frame.maxX <= legend.frame.minX + 0.5
                    let isBelow = swap.frame.minY >= legend.frame.maxY - 0.5
                    #expect(isBeside || isBelow, "\(setting.testDescription): \(row.letter)")
                    #expect(swap.traits.contains(.button))
                }
            }
        }

        @Test(
            "VoiceOver order: eyebrow, round, each legend row then its swap, the rest line, the rows by label",
            arguments: sizes
        )
        func threeMembers_voiceOverOrder(_ size: DynamicTypeSize) throws {
            let model = try Self.threeMembers()
            let block = try #require(model.block)
            let page = WorkoutPage(model: model) { _ in }
            let settings = [
                LayoutSetting(size: size), LayoutSetting(size: size, width: 375, isBold: true, isRightToLeft: true)
            ]
            for setting in settings {
                let stops = setting.elements(of: page)
                let labels = stops.map(\.label)
                var expected = [block.eyebrow, block.title]
                for row in block.legend {
                    expected += [row.spoken, row.swap ?? ""]
                }
                expected.append(block.restLineSpoken)
                let head = Array(labels.prefix(expected.count))
                #expect(head == expected, "\(setting.testDescription): \(head)")
                let title = stops.first { $0.label == block.title }
                #expect(title?.traits.contains(.header) == true, "\(setting.testDescription)")
                let current = stops.first { $0.label == block.legend[1].spoken }
                #expect(current?.traits.contains(.selected) == true, "\(setting.testDescription)")
                // Each row, name first, then its check, in display order.
                let rowStops = block.rows.flatMap { [$0.summary, $0.checkLabel] }
                let found = labels.filter { rowStops.contains($0) }
                #expect(found == rowStops, "\(setting.testDescription)")
                let names = block.legend.map(\.name)
                #expect(block.rows.allSatisfy { row in names.contains { row.summary.hasPrefix($0 + ", ") } })
                let checks = block.rows.map(\.checkLabel)
                #expect(checks.allSatisfy { $0.hasPrefix("Log set ") || $0.hasPrefix("Undo set ") })
            }
        }
    }
#endif
