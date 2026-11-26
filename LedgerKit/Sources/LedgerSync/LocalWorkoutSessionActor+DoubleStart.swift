import Foundation
import LedgerDomain

/// Two workouts started at once, one on each device (F17 S5b, criterion 8; Pete 2026-11-25, option C). When two
/// live logs' `started` envelopes come from different devices and are no more than `doubleStartWindow` apart (two
/// of one device's own only damage makes: recovery resumes the later), the earlier `started` in the engine's
/// order (`wallClock`, then device) wins: it is the live workout on both devices. The loser is never deleted when
/// it holds anything the lifter did to a set: it is saved to history as a workout of its own, through the save a
/// finish takes. Only a loser of nothing but its `started`, cursor moves and rests is dropped.
///
/// **Who ends the loser.** Only the device that started it: it holds the loser's whole log, and one end, made
/// once and sent as an envelope, is what both devices complete, as any end. The other device keeps the loser's log
/// until that end arrives, then saves or drops it as any ended workout it was not shown. So both devices reach the
/// same outcome, nothing is saved twice, and no device answers another's end with one of its own.
extension LocalWorkoutSessionActor {
    /// How far apart two `started` envelopes may be for the rule to hold. Further apart, both workouts stay live
    /// in the store, and the one that started last is resumed on a launch (recovery).
    public static let doubleStartWindow: TimeInterval = 60

    /// A live log, as the rule judges it.
    private struct Contender {
        let state: WorkoutState
        let started: EventEnvelope
        let log: [EventEnvelope]
    }

    /// Applies the rule to every live log in the store, in turn: the winner becomes the live workout when the one
    /// shown lost, and each loser this device started is ended. Run when a `started` was received, and by recovery.
    func resolveDoubleStarts() async throws {
        var contenders: [Contender] = []
        for workout in try await events.uncompactedWorkoutIDs() {
            let log = try await events.envelopes(for: workout)
            let starts = log.filter(\.isStarted)
            guard let state = WorkoutEngine.replay(log), state.phase == .live, let started = starts.min() else {
                continue
            }
            contenders.append(Contender(state: state, started: started, log: log))
        }
        guard let winner = contenders.min(by: { $0.started < $1.started }) else {
            return
        }
        let losers = contenders.filter { contender in
            contender.started.device != winner.started.device
                && contender.started.wallClock.timeIntervalSince(winner.started.wallClock) <= Self.doubleStartWindow
        }
        guard !losers.isEmpty else {
            return
        }
        if let shown = live?.id, losers.contains(where: { $0.state.id == shown }) {
            seq = try await events.highestSeq(for: winner.state.id, device: device) ?? 0
            live = winner.state
            publish(winner.state, [])
            logger.notice("Double start: \(winner.state.id.rawValue, privacy: .public) won, and is shown")
        }
        for loser in losers where loser.started.device == device {
            try await end(loser)
        }
    }

    /// Ends a loser this device started: `finished` at its last event when it holds set data, else `discarded`.
    /// The end goes to the peer with the whole log in one frame, so an end that arrives brings every set with it.
    /// A loser already in this device's history (its log came back from the peer after it was saved, because the
    /// frame with its end was lost) is not saved again, so a partial copy can never overwrite the whole one. Its
    /// end is still sent, so the peer completes its copy; it takes a `seq` above `2³²`, past any this device stamps
    /// in one workout, as the log that would say which were used is gone.
    private func end(_ loser: Contender) async throws {
        let id = loser.state.id
        let lastEvent = loser.log.map(\.wallClock).max() ?? loser.state.startedAt
        let endedAt = max(lastEvent, loser.state.startedAt)
        let holdsSetData = loser.log.contains { !$0.event.isDroppableAtADoubleStart }
        let event: WorkoutEvent = holdsSetData ? .finished(endedAt: endedAt) : .discarded(endedAt: endedAt)
        let isSaved = try await workouts.workout(id: id) != nil
        var advanced = clock
        let kept = try await events.highestSeq(for: id, device: device) ?? 0
        let envelope = try stamp(event, of: id, seq: kept + 1 + (isSaved ? 1 << 32 : 0), with: &advanced)
        let (reduced, _) = WorkoutEngine.reduce(loser.state, envelope)
        guard let ended = reduced, ended.phase != .live else {
            logger.fault("The engine refused the end of double-start loser \(id.rawValue, privacy: .public)")
            return
        }
        try await persist(envelope)
        clock = advanced
        connection.outbox?.yield(.envelopes((loser.log + [envelope]).sorted()))
        logger.notice("Double start: \(id.rawValue, privacy: .public) lost; \(holdsSetData ? "saved" : "dropped")")
        if isSaved {
            try await events.compact(workout: id)
            return
        }
        do {
            try await complete(ended)
        } catch WorkoutSessionError.incompleteLog {
            logger.notice("Double-start loser \(id.rawValue, privacy: .public) has unreadable rows; kept")
        }
    }
}

extension EventEnvelope {
    /// Whether this is a workout's `started`.
    var isStarted: Bool {
        if case .started = event {
            return true
        }
        return false
    }
}

extension WorkoutEvent {
    /// Whether a double-start loser holding only events like this may be dropped (Pete 2026-11-25): its `started`,
    /// cursor moves and rests. Anything done to a set, an exercise or the workout's end is the lifter's and is kept.
    var isDroppableAtADoubleStart: Bool {
        switch self {
        case .started, .exerciseSelected, .restStarted, .restExtended, .restSkipped:
            true
        default:
            false
        }
    }
}
