import Foundation

public extension WorkoutEngine {
    /// Rule 12 (ADR-004 rules 2 and 6): the state a workout's log folds to, the same whatever order
    /// the envelopes arrived in and however often; `nil` when the log holds no `started`.
    ///
    /// This is how a device applies a remote envelope (rebuild from the merged log) and how it
    /// resumes after a crash.
    static func replay(_ log: [EventEnvelope]) -> WorkoutState? {
        var state: WorkoutState?
        for envelope in foldOrder(log) {
            _ = step(&state, envelope)
        }
        return state
    }
}

extension WorkoutEngine {
    /// The order `replay` folds a log in: sorted (rule 12), one envelope per key, with the first
    /// `started` moved to the front.
    ///
    /// The move is rule 1's buffering. An envelope that sorts before the `started` (a peer whose
    /// clock runs slightly behind) is applied after it rather than dropped.
    static func foldOrder(_ log: [EventEnvelope]) -> [EventEnvelope] {
        var seen = Set<EnvelopeKey>()
        var ordered = log.sorted().filter { seen.insert($0.key).inserted }
        let start = ordered.firstIndex { envelope in
            if case .started = envelope.event {
                true
            } else {
                false
            }
        }
        if let start {
            ordered.insert(ordered.remove(at: start), at: 0)
        }
        return ordered
    }
}
