import Foundation

public extension WorkoutEngine {
    /// Rule 12 (ADR-004 rules 2 and 6): the state a workout's log folds to, the same whatever order
    /// the envelopes arrived in and however often; `nil` when the log holds no usable `started`. It
    /// ignores malformed envelopes (`EventEnvelope.isWellFormed`), as `reduce` does.
    ///
    /// This is how a device applies a remote envelope (rebuild from the merged log) and how it
    /// resumes after a crash. It is a function of the envelope set only while each key names one
    /// envelope (`EventEnvelope`); it breaks no tie between two envelopes that share a key.
    static func replay(_ log: [EventEnvelope]) -> WorkoutState? {
        var state: WorkoutState?
        for envelope in foldOrder(log) {
            _ = step(&state, envelope)
        }
        return state
    }

    /// The effects a rebuild must run: what changed between the state before (`old`) and after (`new`)
    /// the host applied envelopes it received (the host loop on `reduce`). They are, in order:
    /// - when the workout has just ended: `.materialize(new)` if finished or `.discardLog` if discarded,
    ///   then `.cancelRestNotification`;
    /// - when a finished workout changed (a late envelope sorted before its finish): `.materialize(new)`
    ///   again, an idempotent upsert;
    /// - otherwise, when the rest changed: `.scheduleRestNotification` for the new rest, or
    ///   `.cancelRestNotification` when there is none;
    /// - `.updateLiveActivity` whenever the state changed.
    ///
    /// There are no haptics: a rebuild can apply many envelopes at once, so a reconnect that delivers a
    /// dozen sets plays nothing. (A received envelope reduced live, in order, runs `reduce`'s own effects,
    /// haptic included; see ADR-004, "The host loop".) There is no `.persist` or `.transmit` either: the
    /// host has stored what it received, and sends only its own envelopes.
    static func effects(from old: WorkoutState?, to new: WorkoutState?) -> [Effect] {
        guard new != old else {
            return []
        }
        let ended = new.map { $0.phase != .live && $0.phase != old?.phase } ?? false
        var effects: [Effect] = []
        if let new, new.phase == .finished {
            effects.append(.materialize(new))
        } else if ended {
            effects.append(.discardLog)
        }
        if ended || new?.rest != old?.rest {
            effects.append(new?.rest.map { .scheduleRestNotification(endsAt: $0.endsAt) } ?? .cancelRestNotification)
        }
        return effects + [.updateLiveActivity]
    }
}

extension WorkoutEngine {
    /// The order `replay` folds a log in: its well-formed envelopes, sorted (rule 12), then
    /// 1. only the envelopes of the workout that the first usable `started` begins, because a key is
    ///    unique only within a workout (seqs restart at 1), so the filter comes before the dedupe;
    /// 2. one envelope per key;
    /// 3. that `started` moved to the front.
    ///
    /// The move is rule 1's buffering. An envelope that sorts before the `started` (a peer whose
    /// clock runs slightly behind) is applied after it rather than dropped. An unusable `started`
    /// (not live, or for another workout) is never moved: `step` ignores it where it sorts.
    static func foldOrder(_ log: [EventEnvelope]) -> [EventEnvelope] {
        let sorted = log.filter(\.isWellFormed).sorted()
        guard let workout = sorted.first(where: { snapshot(startedBy: $0) != nil })?.workoutID else {
            return []
        }
        var seen = Set<EnvelopeKey>()
        var ordered = sorted.filter { $0.workoutID == workout && seen.insert($0.key).inserted }
        if let start = ordered.firstIndex(where: { snapshot(startedBy: $0) != nil }) {
            ordered.insert(ordered.remove(at: start), at: 0)
        }
        return ordered
    }
}
