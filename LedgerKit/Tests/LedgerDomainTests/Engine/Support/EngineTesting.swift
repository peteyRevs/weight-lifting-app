import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

extension Tag {
    /// Longer than 2 s or timing-sensitive; skipped on the PR lane (testing-strategy §6).
    @Tag static var slow: Self
}

/// Shorthands for the engine suites.
enum Engine {
    static let phone = EventBuilders.phone
    static let watch = EventBuilders.watch

    /// `seconds` after the fixture start.
    static func at(_ seconds: TimeInterval) -> Date {
        EventBuilders.start.addingTimeInterval(seconds)
    }

    /// `session` started by `device` at the fixture start, seq 1.
    static func started(
        _ session: WorkoutState = EventBuilders.seedSession(),
        by device: DeviceID = phone
    ) -> EventEnvelope {
        EventBuilders.envelope(.started(session), device: device, seq: 1, at: at(0))
    }

    /// The live state right after `session` starts.
    static func live(_ session: WorkoutState = EventBuilders.seedSession()) throws -> WorkoutState {
        try #require(WorkoutEngine.reduce(nil, started(session)).0)
    }

    /// `event` from `device` at `seconds` after the start.
    static func envelope(
        _ event: WorkoutEvent,
        _ seconds: TimeInterval,
        from device: DeviceID = phone,
        seq: UInt64
    ) -> EventEnvelope {
        EventBuilders.envelope(event, device: device, seq: seq, at: at(seconds))
    }

    /// Reduces `events` in order after `session` starts: one phone envelope every 10 s from 10 s.
    /// Returns the final state and the effects of the last event.
    static func run(
        _ events: [WorkoutEvent],
        on session: WorkoutState = EventBuilders.seedSession()
    ) throws -> (state: WorkoutState, effects: [Effect]) {
        let log = [started(session)] + EventBuilders.log(from: events, firstSeq: 2, startingAt: at(10))
        var state: WorkoutState?
        var effects: [Effect] = []
        for envelope in log {
            (state, effects) = WorkoutEngine.reduce(state, envelope)
        }
        return try (#require(state), effects)
    }

    /// Reduces `log` in the order given (no sorting or dedupe).
    static func fold(_ log: [EventEnvelope]) -> WorkoutState? {
        log.reduce(nil) { WorkoutEngine.reduce($0, $1).0 }
    }

    /// "+`seconds`" tapped at `tapped` seconds by a device that showed a rest running (`shown`), or
    /// none (decision #7).
    static func extend(_ seconds: Int64 = 30, shown: Bool = true, tapped: TimeInterval) -> WorkoutEvent {
        .restExtended(amount: .seconds(seconds), extendsShownRest: shown, tappedAt: at(tapped))
    }

    static func set(_ exerciseIndex: Int, _ setIndex: Int) -> SetID {
        EventBuilders.setID(exerciseIndex, setIndex)
    }

    static func logged(
        _ exerciseIndex: Int,
        _ setIndex: Int,
        pounds: Decimal = 185,
        reps: Int = 5,
        at seconds: TimeInterval
    ) -> WorkoutEvent {
        .setLogged(
            exerciseIndex: exerciseIndex,
            setID: set(exerciseIndex, setIndex),
            weight: .pounds(pounds),
            reps: Reps(clamping: reps),
            doneAt: at(seconds)
        )
    }
}
