import Foundation

/// Joins the logs two devices kept of one workout while they could not reach each other, and folds the
/// result (F19 criterion 6). It is pure and reads no clock, like `WorkoutEngine`.
///
/// The live path (F17) folds with `WorkoutEngine.replay`, where the first terminal envelope ends the
/// workout and everything after it is ignored. That is right while the devices are connected: nobody
/// logs on a workout the other device has already ended. After a partition it is not, because each
/// device kept logging on its own workout, so `resolve` holds every terminal back until the rest of the
/// log is folded (ruling R1), then applies one (ruling R2). Both rulings keep logged data whenever there
/// is a choice.
///
/// It reconciles the logs of one `WorkoutID` only. Two workouts started apart on the two devices for
/// the same day are two workouts, both kept (ruling R3): that is the caller's matter, and `merge`
/// refuses logs that mix workouts rather than pick one.
public enum WorkoutReconciler {
    /// Why `merge` refused its logs. It throws rather than keep one of two envelopes, so its result is
    /// always a function of the set of envelopes it was given.
    public enum MergeError: Error, Equatable, Sendable {
        /// The logs hold envelopes of more than one workout, listed in `rawValue` order. A key is unique
        /// only within a workout (seqs restart at 1), so these cannot be deduped together.
        case mixedWorkouts([WorkoutID])
        /// Two different envelopes share this key: a device reused a `seq`, which
        /// `WorkoutEventStore.append` refuses with `EngineError.conflictingEnvelope` for the same reason.
        case conflictingEnvelope(EnvelopeKey)
    }

    /// The union of `logs`, each envelope once, in the order `WorkoutEngine.replay` folds:
    /// - an envelope with a date that is not finite (`EventEnvelope.hasFiniteDates`) is dropped, as an F17
    ///   host drops one before storing it: NaN is unequal to itself, so a copy would look like a conflict,
    ///   and it has no place in the order;
    /// - copies are deduped by key (device, seq);
    /// - the result is sorted by `(wallClock, device, seq)`, `EventEnvelope`'s `<`, which is the sort
    ///   `WorkoutEngine.foldOrder` begins with.
    ///
    /// It keeps every other envelope, a malformed one or one before the `started` included: the merged log
    /// is what a device stores, and every device's log should agree (`EventEnvelope.isWellFormed`). That is
    /// why it does not return `foldOrder` itself, which drops those and moves the `started` to the front.
    ///
    /// The result is the same for any order or grouping of the same envelopes, and merging it again with
    /// any of the logs changes nothing.
    ///
    /// - Throws: `MergeError.mixedWorkouts` when the envelopes belong to more than one workout, and
    ///   `MergeError.conflictingEnvelope` for two different envelopes with one key.
    public static func merge(_ logs: [[EventEnvelope]]) throws(MergeError) -> [EventEnvelope] {
        let union = logs.joined().filter(\.hasFiniteDates).sorted()
        let workouts = Set(union.map(\.workoutID))
        guard workouts.count <= 1 else {
            throw .mixedWorkouts(workouts.sorted { $0.rawValue < $1.rawValue })
        }
        var held: [EnvelopeKey: EventEnvelope] = [:]
        var merged: [EventEnvelope] = []
        for envelope in union {
            if let copy = held[envelope.key] {
                guard copy == envelope else {
                    throw .conflictingEnvelope(envelope.key)
                }
                continue
            }
            held[envelope.key] = envelope
            merged.append(envelope)
        }
        return merged
    }

    /// `merge([local, remote])`: the phone's own log and the one the watch sent (the F19 pull-back).
    public static func merge(local: [EventEnvelope], remote: [EventEnvelope]) throws(MergeError) -> [EventEnvelope] {
        try merge([local, remote])
    }

    /// The state a reconciled log folds to, or `nil` when it holds no usable `started` (as `replay`).
    ///
    /// It folds `WorkoutEngine.foldOrder(log)`, so any log will do, merged or not, in any order, with
    /// copies. Like `replay`, it folds only the workout of the first usable `started`; `merge` is where
    /// mixed workouts are refused.
    ///
    /// **R1 (pending Pete): every non-terminal envelope from both devices is folded, then one terminal.**
    /// The terminals are held back, so a set the watch logged after the phone had finished is kept. The
    /// workout ends at the earliest of the chosen kind, in fold order (`(wallClock, device, seq)`, the
    /// order in which the live engine would have met them). Its `endedAt` is that envelope's own: elapsed
    /// time can then be shorter than the time of the last set, whose `doneAt` lies after `endedAt`.
    ///
    /// **R2 (pending Pete): a finish beats a discard whenever the folded workout has a done set.** One
    /// device discarding cannot drop sets either device logged. Only a workout with no done set is
    /// discarded when any device discarded it. Either way the earliest envelope of the chosen kind
    /// applies: of two discards, the earlier.
    ///
    /// With no terminal envelope the workout stays live. With no terminal held back it folds exactly as
    /// `replay`; with one that sorts after every other envelope, too.
    public static func resolve(_ log: [EventEnvelope]) -> WorkoutState? {
        var state: WorkoutState?
        var terminals: [EventEnvelope] = []
        for envelope in WorkoutEngine.foldOrder(log) {
            if envelope.event.isTerminal {
                terminals.append(envelope)
            } else {
                _ = WorkoutEngine.step(&state, envelope)
            }
        }
        let hasDoneSet = (state?.doneSets ?? 0) > 0
        if let terminal = chosenTerminal(of: terminals, hasDoneSet: hasDoneSet) {
            _ = WorkoutEngine.step(&state, terminal)
        }
        return state
    }

    /// R2: the earliest finish when a set is done, else the earliest discard; failing that, the earliest
    /// of the other kind. `terminals` are in fold order.
    private static func chosenTerminal(of terminals: [EventEnvelope], hasDoneSet: Bool) -> EventEnvelope? {
        let finish = terminals.first { $0.event.isFinish }
        let discard = terminals.first { !$0.event.isFinish }
        return hasDoneSet ? finish ?? discard : discard ?? finish
    }
}

private extension WorkoutEvent {
    /// `finished` or `discarded` (rule 10).
    var isTerminal: Bool {
        switch self {
        case .finished, .discarded:
            true
        default:
            false
        }
    }

    var isFinish: Bool {
        if case .finished = self {
            return true
        }
        return false
    }
}
