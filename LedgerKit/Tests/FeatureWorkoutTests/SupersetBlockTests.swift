#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// F10 S9, criteria 7, 9, 10, 12 and 19 on screen: what each control of a superset's block sends, read
    /// through UIKit's accessibility tree as VoiceOver activates it. The tree itself is
    /// `WorkoutAccessibilityTests`' (`WorkoutTrees+Block`).
    @Suite("Superset block", .serialized, .tags(.feature))
    struct SupersetBlockTests {
        @Test(
            "Each legend row jumps to its member, its swap opens that member's sheet, and each row sends its own edit"
        )
        func controls_sendTheirActions() throws {
            let workout = try WorkoutPreview.dropSet.workout()
            let pulldown = workout.exercises[3]
            let raise = workout.exercises[4]
            let sent = WorkoutAccessibilityTests.sent(by: .dropSet)
            var expected: [WorkoutAction] = [
                .minimize, .finish,
                .edit(.jump(exerciseIndex: 3)),
                .swap(.open(exerciseIndex: 3, exerciseID: pulldown.exerciseID)),
                .edit(.jump(exerciseIndex: 4))
            ]
            // Display order: A1 B1 A2 B2 A3 B3 BD; B1 is logged.
            let order = [(3, 0), (4, 0), (3, 1), (4, 1), (3, 2), (4, 2), (4, 3)]
            for (exercise, row) in order {
                let set = workout.exercises[exercise].sets[row]
                expected.append(.edit(.select(exerciseIndex: exercise, setID: set.id)))
                expected.append(.edit(
                    set.isDone ? .unlog(exerciseIndex: exercise, setID: set.id) : .log(
                        exerciseIndex: exercise,
                        setID: set.id
                    )
                ))
            }
            expected.append(.edit(.addSet(exerciseIndex: 4)))
            expected += (0 ... 2).map { .edit(.jump(exerciseIndex: $0)) }
            #expect(sent.count == expected.count)
            for (index, pair) in zip(sent, expected).enumerated() {
                #expect(pair.0 == pair.1, "button \(index + 1) in reading order")
            }
            #expect(raise.sets[0].isDone)
        }

        @Test("The steppers change the shown row of its own member, B2 in kilograms")
        func steppers_actOnTheShownMembersRow() throws {
            let shown = try WorkoutPreview.dropSet.workout().exercises[4].sets[1].id
            var sent: [WorkoutAction] = []
            WorkoutAccessibilityTests.cover(.dropSet) { sent.append($0) }.withAccessibilityElements { elements in
                for element in elements where element.accessibilityTraits.contains(.adjustable) {
                    element.accessibilityIncrement()
                }
            }
            #expect(sent == [
                .edit(.stepWeight(exerciseIndex: 4, setID: shown, .increment)),
                .edit(.stepReps(exerciseIndex: 4, setID: shown, .increment))
            ])
        }
    }
#endif
