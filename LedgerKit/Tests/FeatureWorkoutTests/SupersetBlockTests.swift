#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    import LedgerDesign
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
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

        /// A bench press, then two supersets: Lat Pulldown and Cable Lateral Raise, Chest-Supported Row and
        /// Barbell Curl.
        static let twoSupersets = EventBuilders.session([
            .init("Barbell Bench Press", .barbell, sets: 5, reps: 5, pounds: 185, restSeconds: 150),
            .init("Lat Pulldown", .cable, sets: 4, reps: 12, pounds: 100, restSeconds: 75),
            .init("Cable Lateral Raise", .cable, sets: 4, reps: 15, pounds: 15, restSeconds: 60, superset: true),
            .init("Chest-Supported Row", .machine, sets: 4, reps: 8, pounds: 70, restSeconds: 90),
            .init("Barbell Curl", .barbell, sets: 4, reps: 12, pounds: 75, restSeconds: 60, superset: true)
        ])

        /// The real screen of `twoSupersets` at the largest size of the matrix, in a window, showing what
        /// each `show` chooses.
        @MainActor
        final class Screen {
            let host = UIHostingController(rootView: WorkoutPageViewsAdversarialTests.screen(twoSupersets, nil))
            let window = SceneLessWindow.make(frame: CGRect(x: 0, y: 0, width: SnapshotConfig.phoneWidth, height: 874))

            init() {
                window.rootViewController = host
                window.isHidden = false
            }

            func close() {
                window.isHidden = true
                window.rootViewController = nil
            }

            /// The page's scroll view once `exercise`'s second row is chosen (nil: nothing chosen).
            func show(_ exercise: Int?) throws -> UIScrollView {
                let selection = exercise.map {
                    WorkoutSelection(exerciseIndex: $0, setID: twoSupersets.exercises[$0].sets[1].id)
                }
                host.rootView = WorkoutPageViewsAdversarialTests.screen(twoSupersets, selection)
                for _ in 0 ..< 5 {
                    host.view.setNeedsLayout()
                    host.view.layoutIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                }
                return try #require(WorkoutPageViewsAdversarialTests.scrollView(in: host.view))
            }
        }

        /// Review SF2: the page stands at its top again when another card or block is shown (card → block,
        /// block → block, block → card), and stays where it was when the current member changes inside a block.
        @Test("Another card or block scrolls the page to its top; another member of the same block does not")
        func scroll_followsTheShownPlace() throws {
            let screen = Screen()
            defer { screen.close() }
            // What is chosen next, and whether the page goes back to its top.
            let steps: [(exercise: Int?, toTop: Bool)] = [(1, true), (2, false), (3, true), (nil, true)]
            var scroll = try screen.show(nil)
            for (index, step) in steps.enumerated() {
                #expect(scroll.contentSize.height > scroll.bounds.height + 250, "step \(index): the page is too short")
                scroll.setContentOffset(CGPoint(x: 0, y: 250), animated: false)
                scroll = try screen.show(step.exercise)
                let offset = scroll.contentOffset.y
                #expect(step.toTop ? offset < 1 : abs(offset - 250) < 1, "step \(index): the page stands at \(offset)")
            }
        }
    }
#endif
