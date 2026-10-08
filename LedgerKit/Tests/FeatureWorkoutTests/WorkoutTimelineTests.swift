@testable import FeatureWorkout
import Foundation
import LedgerTestSupport
import SwiftUI
import Testing

/// F10 S4, criterion 6: the one value that gives the workout's views their time. What the elapsed time
/// reads is a reference's to show (`WorkoutSnapshotTests`): a timer's text cannot be read back.
@MainActor
@Suite("WorkoutTimeline", .tags(.feature))
struct WorkoutTimelineTests {
    @Test("In the app time runs: nothing stops it unless a preview or a test says when")
    func timeline_isLiveByDefault() {
        #expect(EnvironmentValues().workoutTimeline == .live)
        #expect(WorkoutTimeline.live.pausedAt == nil)
        #expect(WorkoutTimeline.fixed(at: Fixtures.now).pausedAt == Fixtures.now)
    }

    @Test("No start traps the elapsed time: not one before every calendar, nor one after every calendar")
    func elapsed_anyStart_makesAText() {
        let starts = [
            Fixtures.now, Fixtures.now.addingTimeInterval(86400), .distantPast, .distantFuture,
            Date(timeIntervalSinceReferenceDate: .infinity), Date(timeIntervalSinceReferenceDate: -.infinity),
            Date(timeIntervalSinceReferenceDate: .greatestFiniteMagnitude),
            Date(timeIntervalSinceReferenceDate: -.greatestFiniteMagnitude)
        ]
        for timeline in [WorkoutTimeline.live, .fixed(at: Fixtures.now)] {
            for start in starts {
                _ = timeline.elapsed(since: start)
            }
        }
    }
}
