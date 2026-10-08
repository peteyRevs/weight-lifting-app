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

        var isButton: Bool {
            traits & UIAccessibilityTraits.button.rawValue != 0
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

    /// F10 S4, criteria 6 and 10: the cover's intended VoiceOver tree, as the implementation notes write it,
    /// pinned exactly (the stops, their order, labels, values and traits), and what each control sends. Read
    /// from the cover itself (`WorkoutScreen`, which holds no scroll view yet), through UIKit's accessibility
    /// tree, as VoiceOver reads it, at the default text size and at the largest of the snapshot matrix.
    @Suite("Workout accessibility", .serialized, .tags(.feature))
    struct WorkoutAccessibilityTests {
        nonisolated static let appearances = [
            SnapshotAppearance(.light, .large),
            SnapshotAppearance(.dark, .accessibility3)
        ]

        /// The cover's tree with a workout on it: the header's row, left to right, then the workout's name
        /// and its progress. The elapsed time is its name alone, with no time for VoiceOver to read stale.
        static func workout(progress: String, isEnabled: Bool = true) -> [Stop] {
            let button: UIAccessibilityTraits = isEnabled ? .button : [.button, .notEnabled]
            return [
                Stop("Minimize", button),
                Stop("Elapsed time", []),
                Stop("Finish", button),
                Stop("Upper A — Push focus", [.header, .staticText]),
                Stop("Workout progress", value: progress, [])
            ]
        }

        static let trees: [WorkoutPreview: [Stop]] = [
            .started: workout(progress: "Exercise 1 of 5"),
            .minutes: workout(progress: "Exercise 2 of 5"),
            .hour: workout(progress: "Exercise 5 of 5"),
            .discarding: workout(progress: "Exercise 2 of 5", isEnabled: false),
            .loading: [],
            .failed: [
                Stop("Couldn't open this workout", [.header, .staticText]),
                Stop("Close this screen and try again.", .staticText),
                Stop("Close", .button)
            ]
        ]

        private static func screen(
            _ preview: WorkoutPreview,
            send: @escaping (WorkoutAction) -> Void = { _ in }
        ) -> some View {
            WorkoutScreen(model: preview.model, send: send)
                .environment(\.workoutTimeline, .fixed(at: preview.now))
                .frame(height: 874)
        }

        @Test(
            "Every state of the cover has exactly its intended VoiceOver tree, at the default and the largest size",
            arguments: WorkoutPreview.allCases
        )
        func tree_isExactlyTheTable(_ preview: WorkoutPreview) throws {
            for appearance in Self.appearances {
                let found = Self.screen(preview).accessibilityElements(appearance).map {
                    Stop($0.label, value: $0.value, $0.traits)
                }
                let expected = try #require(Self.trees[preview], "no tree is written for this state")
                let difference = firstDifference(found: found, expected: expected)
                #expect(difference == nil, "\(preview.rawValue) at \(appearance)")
            }
        }

        @Test(
            "Every button's target is at least 44 by 44 points, and the header's row stays inside the screen",
            arguments: WorkoutPreview.allCases
        )
        func buttons_haveA44PointTarget(_ preview: WorkoutPreview) throws {
            for appearance in Self.appearances {
                let elements = Self.screen(preview).accessibilityElements(appearance)
                let buttons = elements.filter { $0.traits.contains(.button) }
                #expect(try buttons.count == #require(Self.trees[preview]).count(where: \.isButton))
                for button in buttons {
                    // UIKit's conversion to window coordinates can report 44 pt as 43.999999999999886.
                    #expect(
                        button.frame.width >= 44 - 0.001 && button.frame.height >= 44 - 0.001,
                        "\(button.label) at \(appearance): \(button.frame.size)"
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
        private static func sent(by preview: WorkoutPreview) -> [WorkoutAction] {
            var sent: [WorkoutAction] = []
            screen(preview) { sent.append($0) }.withAccessibilityElements { elements in
                for element in elements where element.accessibilityTraits.contains(.button) {
                    _ = element.accessibilityActivate()
                }
            }
            return sent
        }

        @Test("Minimize and Finish each send their own action, once")
        func header_buttons_sendTheirActions() {
            #expect(Self.sent(by: .minutes) == [.minimize, .finish])
        }

        @Test("While a discard runs neither button sends anything")
        func header_discarding_sendsNothing() {
            #expect(Self.sent(by: .discarding) == [])
        }

        @Test("The failed screen's Close minimizes: the cover closes and the session is left alone")
        func failed_close_minimizes() {
            #expect(Self.sent(by: .failed) == [.minimize])
        }
    }
#endif
