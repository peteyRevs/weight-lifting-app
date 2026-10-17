#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// One VoiceOver stop, as the notes' table writes it: label, value and traits, compared exactly.
    nonisolated struct Stop: Equatable, Sendable, CustomStringConvertible {
        let label: String
        let value: String
        let traits: UInt64

        init(_ label: String, value: String = "", _ traits: UIAccessibilityTraits) {
            self.label = label
            self.value = value
            self.traits = traits.rawValue
        }

        /// A button or an adjustable stop: what must be a 44 pt target.
        var isControl: Bool {
            traits & (UIAccessibilityTraits.button.rawValue | UIAccessibilityTraits.adjustable.rawValue) != 0
        }

        var description: String {
            "\"\(label)\" value \"\(value)\" traits \(traits)"
        }
    }

    /// The first place two trees differ, as one short line, or nil when they are the same. A test expects this
    /// to be nil and so never hands a whole tree to `#expect`.
    nonisolated func firstDifference(found: [Stop], expected: [Stop]) -> String? {
        for (index, pair) in zip(found, expected).enumerated() where pair.0 != pair.1 {
            return "stop \(index + 1): found \(pair.0), expected \(pair.1)"
        }
        guard found.count != expected.count else {
            return nil
        }
        let extra = found.count > expected.count ? found[expected.count] : expected[found.count]
        return "found \(found.count) stops, expected \(expected.count); the first one more is \(extra)"
    }

    /// F10 S4 criteria 6 and 10, S5 criteria 1, 9 and 10: the cover's intended VoiceOver tree, as the
    /// implementation notes write it (`WorkoutTrees`), pinned exactly (the stops, their order, labels, values
    /// and traits), and what each control sends. A live workout is read from its parts, the header over the
    /// page without the scroll view (`WorkoutParts`); loading and the failed screen, which hold no scroll
    /// view, from the screen itself. Read through UIKit's accessibility tree, as VoiceOver reads it, at the
    /// default text size and at the largest of the snapshot matrix.
    @Suite("Workout accessibility", .serialized, .tags(.feature))
    struct WorkoutAccessibilityTests {
        nonisolated static let appearances = [
            SnapshotAppearance(.light, .large),
            SnapshotAppearance(.dark, .accessibility3)
        ]

        @ViewBuilder
        static func cover(
            _ preview: WorkoutPreview,
            send: @escaping (WorkoutAction) -> Void = { _ in }
        ) -> some View {
            if case .workout = preview.model {
                WorkoutParts(preview: preview, send: send)
            } else {
                WorkoutScreen(model: preview.model, send: send).frame(height: 874)
            }
        }

        @Test(
            "Every state of the cover has exactly its intended VoiceOver tree, at the default and the largest size",
            arguments: WorkoutPreview.allCases
        )
        func tree_isExactlyTheTable(_ preview: WorkoutPreview) throws {
            for appearance in Self.appearances {
                let found = Self.cover(preview).accessibilityElements(appearance).map {
                    Stop($0.label, value: $0.value, $0.traits)
                }
                let expected = try #require(WorkoutTrees.all[preview], "no tree is written for this state")
                let difference = firstDifference(found: found, expected: expected)
                #expect(difference == nil, "\(preview.rawValue) at \(appearance)")
            }
        }

        @Test(
            "Every button and every stepper is a target of at least 44 by 44 points, inside the screen",
            arguments: WorkoutPreview.allCases
        )
        func controls_haveA44PointTarget(_ preview: WorkoutPreview) throws {
            for appearance in Self.appearances {
                let elements = Self.cover(preview).accessibilityElements(appearance)
                let controls = elements.filter { !$0.traits.isDisjoint(with: [.button, .adjustable]) }
                let expected = try #require(WorkoutTrees.all[preview]).count(where: \.isControl)
                #expect(controls.count == expected)
                for control in controls {
                    // UIKit's conversion to window coordinates can report 44 pt as 43.999999999999886.
                    #expect(
                        control.frame.width >= 44 - 0.001 && control.frame.height >= 44 - 0.001,
                        "\(control.label) at \(appearance): \(control.frame.size)"
                    )
                }
                for element in elements {
                    #expect(
                        element.frame.minX >= -0.5 && element.frame.maxX <= SnapshotConfig.phoneWidth + 0.5,
                        "\(element.label) at \(appearance): \(element.frame)"
                    )
                }
            }
        }

        /// What activating every button of `preview`, in reading order, sends.
        static func sent(by preview: WorkoutPreview) -> [WorkoutAction] {
            var sent: [WorkoutAction] = []
            cover(preview) { sent.append($0) }.withAccessibilityElements { elements in
                for element in elements where element.accessibilityTraits.contains(.button) {
                    _ = element.accessibilityActivate()
                }
            }
            return sent
        }

        @Test("Minimize and Finish each send their own action, once, and every control of the page sends its own edit")
        func buttons_sendTheirActions() throws {
            let workout = try WorkoutPreview.logging.workout()
            let bench = workout.exercises[0].sets.map(\.id)
            var expected: [WorkoutAction] = [.minimize, .finish, .edit(.repeatLast(exerciseIndex: 0))]
            for (index, id) in bench.enumerated() {
                expected.append(.edit(.select(exerciseIndex: 0, setID: id)))
                expected.append(.edit(
                    index < 2 ? .unlog(exerciseIndex: 0, setID: id) : .log(exerciseIndex: 0, setID: id)
                ))
            }
            expected.append(.edit(.addSet(exerciseIndex: 0)))
            expected += (1 ... 4).map { .edit(.jump(exerciseIndex: $0)) }
            let sent = Self.sent(by: .logging)
            #expect(sent.count == expected.count)
            for (index, pair) in zip(sent, expected).enumerated() {
                #expect(pair.0 == pair.1, "button \(index + 1) in reading order")
            }
        }

        @Test("Each stepper is adjustable: up adds a step to the shown row, down takes one away")
        func steppers_adjustTheShownRow() throws {
            let shown = try WorkoutPreview.logging.workout().exercises[0].sets[2].id
            var sent: [WorkoutAction] = []
            Self.cover(.logging) { sent.append($0) }.withAccessibilityElements { elements in
                for element in elements where element.accessibilityTraits.contains(.adjustable) {
                    element.accessibilityIncrement()
                    element.accessibilityDecrement()
                }
            }
            #expect(sent == [
                .edit(.stepWeight(exerciseIndex: 0, setID: shown, .increment)),
                .edit(.stepWeight(exerciseIndex: 0, setID: shown, .decrement)),
                .edit(.stepReps(exerciseIndex: 0, setID: shown, .increment)),
                .edit(.stepReps(exerciseIndex: 0, setID: shown, .decrement))
            ])
        }

        @Test("While a discard runs no control of the header or of the page sends anything")
        func discarding_sendsNothing() {
            var sent: [WorkoutAction] = []
            Self.cover(.discarding) { sent.append($0) }.withAccessibilityElements { elements in
                for element in elements {
                    _ = element.accessibilityActivate()
                    element.accessibilityIncrement()
                    element.accessibilityDecrement()
                }
            }
            #expect(sent == [])
        }

        @Test("The failed screen's Close minimizes: the cover closes and the session is left alone")
        func failed_close_minimizes() {
            #expect(Self.sent(by: .failed) == [.minimize])
        }
    }
#endif
