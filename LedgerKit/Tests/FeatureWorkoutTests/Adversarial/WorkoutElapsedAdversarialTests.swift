#if canImport(UIKit)
    @testable import FeatureWorkout
    import Foundation
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// G2 round 2, F10 S4 criterion 14: the elapsed time never traps, whatever the start, paused or running,
    /// alone or in the header.
    @MainActor
    @Suite("Workout elapsed time, every start (adversarial)", .tags(.feature))
    struct WorkoutElapsedAdversarialTests {
        private static let now = EventBuilders.start

        /// Starts that are not a time, and times at and past every edge. None is before `now` by less than
        /// an age, so each reads "0:00" or a count of many hours.
        nonisolated static let starts: [Double] = [
            .nan, -.nan, .signalingNaN, .infinity, -.infinity, .greatestFiniteMagnitude, -.greatestFiniteMagnitude,
            1e300, -1e300, 1e19, -1e19, .leastNonzeroMagnitude, -0.0,
            Date.distantPast.timeIntervalSinceReferenceDate, Date.distantPast.timeIntervalSinceReferenceDate - 1,
            Date.distantFuture.timeIntervalSinceReferenceDate, Date.distantFuture.timeIntervalSinceReferenceDate + 1
        ]

        private func drawn(_ text: some View) -> String {
            text.accessibilityElements().map(\.label).joined(separator: "¦")
        }

        @Test("No start traps the paused time, and one that is not a countable time reads 0:00", arguments: starts)
        func paused_anyStart(seconds: Double) {
            let start = Date(timeIntervalSinceReferenceDate: seconds)
            let text = drawn(WorkoutTimeline.fixed(at: Self.now).elapsed(since: start))
            let isCountable = seconds.isFinite && start >= .distantPast && start <= Self.now
            if isCountable {
                #expect(text.contains(":") && text != "0:00", "a start long ago counts: \(text)")
            } else {
                #expect(text == "0:00")
            }
        }

        @Test("No start traps the running time", arguments: starts)
        func running_anyStart(seconds: Double) {
            let start = Date(timeIntervalSinceReferenceDate: seconds)
            let text = drawn(WorkoutTimeline.live.elapsed(since: start))
            #expect(!text.isEmpty)
            if !seconds.isFinite || start > .distantFuture || start < .distantPast {
                #expect(text == "0:00")
            }
        }

        @Test("The header of a workout with such a start is drawn whole, and reads no time", arguments: starts)
        func header_anyStart(seconds: Double) {
            var state = EventBuilders.seedSession()
            state.startedAt = Date(timeIntervalSinceReferenceDate: seconds)
            let model = WorkoutPresentation.screen(
                .loaded(state),
                isBusy: false,
                locale: Fixtures.locale,
                calendar: Fixtures.calendar
            )
            // F10 S5: the real screen again (G2, round 1), read outside its scroll view: the pinned header.
            for timeline in [WorkoutTimeline.live, .fixed(at: Self.now)] {
                let labels = WorkoutScreen(model: model) { _ in }
                    .environment(\.workoutTimeline, timeline)
                    .frame(height: 400)
                    .accessibilityElements(outsideScrollViews: true)
                    .map(\.label)
                #expect(labels.count == 5)
                #expect(labels.dropFirst().first == "Elapsed time")
            }
        }

        @Test("The paused time at the pause's own edges", arguments: [
            Date.distantPast, .distantFuture, Date(timeIntervalSinceReferenceDate: 0)
        ])
        func paused_atAnyPause(pause: Date) {
            let text = drawn(WorkoutTimeline.fixed(at: pause).elapsed(since: Self.now))
            #expect(text.contains(":"))
        }
    }
#endif
