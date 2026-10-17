#if canImport(UIKit)
    @testable import FeatureWorkout
    import Foundation
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// G2, F10 S4 criteria 6 and 10: the cover as VoiceOver meets it, and the elapsed time as it is drawn.
    /// The tree below was written by the tester from the specification before the cover was hosted:
    ///
    /// | # | Label | Value | Is a button |
    /// |---|---|---|---|
    /// | 1 | Minimize | | yes |
    /// | 2 | Elapsed time | (none: no time that could be stale) | no |
    /// | 3 | Finish | | yes |
    /// | 4 | the workout's name, as stored | | no |
    /// | 5 | Workout progress | Exercise 1 of 5 | no |
    @MainActor
    @Suite("Workout cover's VoiceOver tree (adversarial)", .tags(.feature))
    struct WorkoutCoverTreeAdversarialTests {
        private static let start = EventBuilders.start

        private func model(isBusy: Bool = false) -> WorkoutScreenModel {
            var state = EventBuilders.seedSession()
            state.name = "Upper A — Push focus"
            return WorkoutPresentation.screen(
                .loaded(state),
                isBusy: isBusy,
                locale: Fixtures.locale,
                calendar: Fixtures.calendar
            )
        }

        private func screen(
            _ model: WorkoutScreenModel,
            after seconds: TimeInterval = 0,
            send: @escaping (WorkoutAction) -> Void = { _ in }
        ) -> some View {
            // F10 S5: the real screen again (G2, round 1). The sanctioned edit drew the header alone, without
            // the screen's insets, so `tree_fitsAtEverySize` measured it 32 pt wider than the cover draws it.
            // Every test here reads the stops outside the scroll view (`outside`): the pinned header, in place.
            WorkoutScreen(model: model, send: send)
                .environment(\.workoutTimeline, .fixed(at: Self.start.addingTimeInterval(seconds)))
                .frame(height: 400)
        }

        private func rows(_ elements: [AccessibilityElementSnapshot]) -> [String] {
            elements.map { "\($0.label)|\($0.value)|\($0.traits.contains(.button) ? "button" : "-")" }
        }

        @Test(
            "A live workout reads Minimize, Elapsed time, Finish, its name, its progress, in that order",
            arguments: [0.0, 1462, 3665]
        )
        func tree_liveWorkout(seconds: TimeInterval) {
            let elements = screen(model(), after: seconds).accessibilityElements(outsideScrollViews: true)
            #expect(rows(elements) == [
                "Minimize||button",
                "Elapsed time||-",
                "Finish||button",
                "Upper A — Push focus||-",
                "Workout progress|Exercise 1 of 5|-"
            ])
            let spoken = elements.map { $0.label + $0.value }.joined()
            #expect(!spoken.contains(":"), "criterion 6: nothing VoiceOver reads carries a time")
        }

        @Test("Each stop is on screen, the buttons are at least 44 points, and nothing overlaps", arguments: [
            DynamicTypeSize.large, .xxxLarge, .accessibility3, .accessibility5
        ])
        func tree_fitsAtEverySize(size: DynamicTypeSize) {
            let elements = screen(model(), after: 3665).accessibilityElements(
                SnapshotAppearance(.light, size),
                outsideScrollViews: true
            )
            #expect(elements.count == 5)
            let width = SnapshotConfig.phoneWidth
            for element in elements {
                let frame = element.frame
                #expect(frame.minX >= 0 && frame.maxX <= width + 0.5, "\(element.label) leaves the screen: \(frame)")
                #expect(frame.width > 0 && frame.height > 0, "\(element.label) has no area")
                if element.traits.contains(.button) {
                    #expect(frame.height >= 44 && frame.width >= 44, "\(element.label) is \(frame.size)")
                }
            }
            for (index, first) in elements.enumerated() {
                for second in elements.dropFirst(index + 1) {
                    let overlap = first.frame.intersection(second.frame)
                    #expect(
                        overlap.isNull || overlap.width < 1 || overlap.height < 1,
                        "\(first.label) overlaps \(second.label)"
                    )
                }
            }
        }

        @Test("While a discard runs, both buttons say they are not enabled, and activating them sends nothing")
        func tree_busy_buttonsAreDisabled() {
            var sent: [WorkoutAction] = []
            let view = screen(model(isBusy: true)) { sent.append($0) }
            let disabled = view.accessibilityElements(outsideScrollViews: true)
                .filter { $0.traits.contains(.notEnabled) }.map(\.label)
            #expect(disabled == ["Minimize", "Finish"])
            view.withAccessibilityElements(outsideScrollViews: true) { elements in
                for element in elements {
                    _ = element.accessibilityActivate()
                }
            }
            #expect(sent.isEmpty)
        }

        @Test("Activating Minimize and Finish sends exactly those")
        func tree_activation() {
            var sent: [WorkoutAction] = []
            screen(model()) { sent.append($0) }.withAccessibilityElements(outsideScrollViews: true) { elements in
                for element in elements where element.accessibilityTraits.contains(.button) {
                    _ = element.accessibilityActivate()
                }
            }
            #expect(sent == [.minimize, .finish])
        }

        @Test("While the session has not said, the cover reads nothing")
        func tree_loading() {
            #expect(screen(.loading).accessibilityElements(outsideScrollViews: true).isEmpty)
        }

        @Test("A cover that cannot show the workout says so and has one button, which closes it")
        func tree_failed() {
            let failed = WorkoutPresentation.screen(
                .failed(WorkoutStoreError.updatesEnded),
                isBusy: false,
                locale: Fixtures.locale,
                calendar: Fixtures.calendar
            )
            var sent: [WorkoutAction] = []
            let view = screen(failed) { sent.append($0) }
            let elements = view.accessibilityElements(outsideScrollViews: true)
            let spoken = elements.map(\.label).joined(separator: " ")
            #expect(spoken.contains("Couldn't open this workout"))
            #expect(spoken.contains("Close this screen and try again."))
            let buttons = elements.filter { $0.traits.contains(.button) }.map(\.label)
            #expect(buttons == ["Close"])
            view.withAccessibilityElements(outsideScrollViews: true) { elements in
                for element in elements where element.accessibilityTraits.contains(.button) {
                    _ = element.accessibilityActivate()
                }
            }
            #expect(sent == [.minimize])
        }

        /// The time alone, hosted without the header's label over it: what the timeline draws.
        private func drawn(start: Date, at moment: Date) -> String {
            let text = WorkoutTimeline.fixed(at: moment).elapsed(since: start)
            return text.accessibilityElements(outsideScrollViews: true).map(\.label).joined(separator: "¦")
        }

        @Test("The elapsed time is drawn as the brief writes it", arguments: [
            (0.0, "0:00"), (1, "0:01"), (59, "0:59"), (60, "1:00"), (1462, "24:22"), (3599, "59:59"),
            (3600, "1:00:00"), (3665, "1:01:05"), (36000, "10:00:00"), (360_000, "100:00:00")
        ])
        func elapsed_isDrawnAsTheBriefWritesIt(seconds: TimeInterval, wanted: String) {
            #expect(drawn(start: Self.start, at: Self.start.addingTimeInterval(seconds)) == wanted)
            #expect(ClockText.elapsed(.seconds(seconds)) == wanted, "the one formatter agrees")
        }

        @Test("A start in the future (a clock set back) reads 0:00", arguments: [1.0, 59, 3600, 86400])
        func elapsed_startInTheFuture_readsZero(ahead: TimeInterval) {
            #expect(drawn(start: Self.start.addingTimeInterval(ahead), at: Self.start) == "0:00")
        }

        @Test("A start no calendar holds reads 0:00 and does not trap", arguments: [
            Date.distantPast.addingTimeInterval(-1e12), Date.distantFuture.addingTimeInterval(1e12),
            Date(timeIntervalSinceReferenceDate: .infinity), Date(timeIntervalSinceReferenceDate: -.infinity),
            Date(timeIntervalSinceReferenceDate: .greatestFiniteMagnitude)
        ])
        func elapsed_uncountableStart_readsZero(start: Date) {
            #expect(drawn(start: start, at: Self.start) == "0:00")
        }

        /// Finding F10-S4-2. **Until it is fixed this test does not fail, it traps**, inside SwiftUI's
        /// `Text(timerInterval:)` (`Duration.init`: "Double value cannot be converted to _Int128"), and takes
        /// the hosted test process with it: `Date`'s `>=` and `<=` both answer true for a date that is not a
        /// number, so `WorkoutTimeline.elapsed(since:)` counts from it. The engine refuses such a start
        /// (`EventEnvelope.isWellFormed`), so no session publishes one today; the function's own comment and
        /// `WorkoutTimelineTests` say that no start traps.
        @Test("A start that is not a number reads 0:00 and does not trap")
        func elapsed_startNotANumber_readsZero() {
            #expect(drawn(start: Date(timeIntervalSinceReferenceDate: .nan), at: Self.start) == "0:00")
        }
    }
#endif
