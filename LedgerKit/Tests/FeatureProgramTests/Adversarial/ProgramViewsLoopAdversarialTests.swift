#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// What a store would hold for the builder, observed by the hosted page: each action the page sends is
    /// applied as `BuilderScreen` applies it, and the page draws the next model.
    @Observable
    final class BuilderLoop {
        var screen: BuilderScreen
        var sent: [ProgramBuilderAction] = []
        var refused = 0

        init(_ screen: BuilderScreen) {
            self.screen = screen
        }

        func take(_ action: ProgramBuilderAction) {
            sent.append(action)
            do {
                try screen.tap(action)
            } catch {
                refused += 1
            }
        }
    }

    /// The same for the exercise library.
    @Observable
    final class PickerLoop {
        var screen: PickerScreen
        var sent: [ExercisePickerAction] = []

        init(_ screen: PickerScreen) {
            self.screen = screen
        }

        func take(_ action: ExercisePickerAction) {
            sent.append(action)
            try? screen.tap(action)
        }
    }

    private struct LoopedBuilder: View {
        let loop: BuilderLoop

        var body: some View {
            ProgramPage(model: loop.screen.model, send: loop.take)
        }
    }

    private struct LoopedPicker: View {
        let loop: PickerLoop

        var body: some View {
            ExercisePickerParts(model: loop.screen.model, send: loop.take)
        }
    }

    /// F11 S9, gate G2, round 1, criterion 1 under change: the page with a store in the loop. A stop is
    /// activated, the action it sent is applied, the page is drawn from the next model, and its tree is read
    /// again: after every step it is the tree the new model asks for, and the next stop sends the new model's
    /// action, not one a view kept from the model before.
    @Suite("Adversarial F11 S9 · the pages with a store in the loop", .serialized, .tags(.feature))
    struct ProgramViewsLoopAdversarialTests {
        /// One walk over a hosted page: it reads the live elements, activates one, and compares what is read
        /// next with the tree the store's next model asks for.
        final class Walk {
            let read: () -> [NSObject]
            let expected: () -> [ViewStop]
            let sentCount: () -> Int
            private(set) var steps = 0

            init(
                read: @escaping () -> [NSObject],
                expected: @escaping () -> [ViewStop],
                sentCount: @escaping () -> Int
            ) {
                self.read = read
                self.expected = expected
                self.sentCount = sentCount
            }

            /// Lets the page draw the next model, and compares its tree.
            func settle(_ step: String) {
                RunLoop.main.run(until: Date())
                let found = read().map(ViewStop.init(reading:))
                let difference = firstDifference(found: found, expected: expected())
                #expect(difference == nil, "after \(step): \(difference ?? "")")
                steps += 1
            }

            /// Activates the button of this label, which must send `sending` actions (one, or none when dimmed).
            func tap(_ label: String, sending: Int = 1) {
                let before = sentCount()
                let button = read().first { $0.accessibilityLabel == label && $0.accessibilityTraits.contains(.button) }
                #expect(button != nil, "no button \(label)")
                _ = button?.accessibilityActivate()
                #expect(sentCount() == before + sending, "\(label) sent \(sentCount() - before) actions")
                settle(label)
            }

            /// A swipe up or down on the one adjustable element.
            func adjust(isUp: Bool) {
                let stepper = read().first { $0.accessibilityTraits.contains(.adjustable) }
                if isUp {
                    stepper?.accessibilityIncrement()
                } else {
                    stepper?.accessibilityDecrement()
                }
                settle(isUp ? "plus" : "minus")
            }
        }

        @Test("A walk through the builder: after every tap the page reads the next model's tree")
        func builder_walk_followsTheModel() throws {
            let loop = try BuilderLoop(BuilderScreen(ProgramFixtures.seedInput()))
            let steps = LoopedBuilder(loop: loop).withLiveAccessibilityElements { read in
                withoutActuallyEscaping(read) { read in Self.walkTheBuilder(read, loop) }
            }
            #expect(steps == 18)
            #expect(loop.refused == 0, "an action the page sent could not be applied")
            let model = loop.screen.model
            #expect(model.block.chips.count == 8 && model.days.cards.count == 5)
            #expect(loop.screen.routes.count == 1, "the new day's editor is asked for once")
        }

        static func walkTheBuilder(_ read: @escaping () -> [NSObject], _ loop: BuilderLoop) -> Int {
            do {
                let walk = Walk(
                    read: read,
                    expected: { ProgramViewsOracle.builder(loop.screen.model).map(\.stop) },
                    sentCount: { loop.sent.count }
                )
                walk.settle("the start")
                for label in ["Week 8", "Deload", "Tuesday", "Tuesday", "Copy week 7", "Week 1", "Sunday"] {
                    walk.tap(label)
                }
                walk.adjust(isUp: true)
                for label in ["Week 2", "Deload", "Apply to later weeks", "Week 3"] {
                    walk.tap(label)
                }
                walk.adjust(isUp: false)
                for label in ["+ Add training day", "Wednesday", "Week 1"] {
                    walk.tap(label)
                }
                walk.tap("First week", sending: 0)
                return walk.steps
            }
        }

        @Test("A walk through the library: after every tap the sheet reads the next model's tree")
        func library_walk_followsTheModel() throws {
            let loop = try PickerLoop(PickerScreen(ExercisePickerFixtures.input(muscle: .back, equipment: .cable)))
            let steps = LoopedPicker(loop: loop).withLiveAccessibilityElements { read in
                withoutActuallyEscaping(read) { read in Self.walkTheLibrary(read, loop) }
            }
            #expect(steps == 12)
            #expect(loop.screen.added.count == 1 && loop.screen.added.first?.count == 2)
            #expect(!loop.screen.isOpen)
        }

        static func walkTheLibrary(_ read: @escaping () -> [NSObject], _ loop: PickerLoop) -> Int {
            do {
                let walk = Walk(
                    read: read,
                    expected: { ProgramViewsOracle.library(loop.screen.model).map(\.stop) },
                    sentCount: { loop.sent.count }
                )
                walk.settle("the start")
                walk.tap("Select exercises to add", sending: 0)
                for label in ["Lat Pulldown", "Cable Shrug", "Lat Pulldown", "Seated Cable Row", "Equipment: All"] {
                    walk.tap(label)
                }
                // The picks are not listed any more; the foot still counts them.
                walk.tap("Muscle: Arms")
                walk.tap("Equipment: Bodyweight")
                loop.screen.input.query = "zzz"
                walk.settle("a query that matches nothing")
                walk.tap("Clear filters")
                walk.tap("Add 2 exercises")
                return walk.steps
            }
        }
    }
#endif
