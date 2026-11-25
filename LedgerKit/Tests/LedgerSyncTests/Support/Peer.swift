import Foundation
import LedgerDomain
import LedgerTestSupport

/// The watch's envelopes, as a phone host under test receives them (F17 S3).
enum Peer {
    static let device = EventBuilders.watch

    /// `event` as the watch records it, at `seconds` after the fixture start.
    static func envelope(
        _ event: WorkoutEvent,
        seq: UInt64,
        at seconds: Double,
        of workout: WorkoutID = Sample.session.id,
        from device: DeviceID = device
    ) -> EventEnvelope {
        EventBuilders.envelope(event, device: device, seq: seq, at: Sample.at(seconds), workoutID: workout)
    }

    /// Row (`exerciseIndex`, `setIndex`) logged on the watch, as its envelope number `seq`.
    static func set(_ exerciseIndex: Int, _ setIndex: Int, seq: UInt64, at seconds: Double = 60) -> EventEnvelope {
        envelope(Sample.logged(exerciseIndex, setIndex, at: seconds), seq: seq, at: seconds)
    }

    /// `snapshot` started on the watch, with `events` after it, ten seconds apart from 10 s.
    static func log(_ events: [WorkoutEvent], of snapshot: WorkoutState = Sample.session) -> [EventEnvelope] {
        let started = envelope(.started(snapshot), seq: 1, at: 0, of: snapshot.id)
        return [started] + events.enumerated().map { offset, event in
            envelope(event, seq: UInt64(offset + 2), at: Double(offset + 1) * 10, of: snapshot.id)
        }
    }

    /// Whether `state` has row (`exerciseIndex`, `setIndex`) done.
    static func isDone(_ state: WorkoutState?, _ exerciseIndex: Int, _ setIndex: Int) -> Bool {
        state?.exercises[exerciseIndex].sets[setIndex].isDone == true
    }
}
