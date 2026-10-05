import Foundation

extension FaultyWorkoutSession {
    /// One way a host could plausibly get the seam wrong. Each breaks the clause `brokenClauses` names for it;
    /// every clause of the contract has at least one (`WorkoutSessionClientContractFaultTests`).
    enum Fault: String, CaseIterable, Sendable, CustomStringConvertible {
        /// A new stream holds its first element twice.
        case duplicatesTheFirstElement
        /// A start's update carries a haptic.
        case startBuzzes
        /// A second start replaces the live workout.
        case secondStartReplaces
        /// The live workout is checked before the snapshot, so `workoutInProgress` hides `notStartable`.
        case judgesTheSessionFirst
        /// Any snapshot whose phase is live is started, whatever the engine says of the rest of it.
        case judgesSnapshotsByPhaseAlone
        /// `apply(.started)` with nothing live starts a workout.
        case startsThroughApply
        /// After a finish, `current()` still answers with the finished workout.
        case keepsTheEndedWorkoutCurrent
        /// After the update that ends a workout comes one more, with a nil state.
        case publishesNilAfterTheEnd
        /// A discard ends the workout without an update.
        case discardsSilently
        /// `finish` and `discard` return from an end the engine ignored, the workout still live.
        case returnsFromAnIgnoredEnd
        /// A terminal event through `apply` is taken for an ignored one: the workout stays live.
        case terminalThroughApplyStaysLive
        /// A terminal event through `apply` ends the workout a second later than the event says.
        case movesTheEndThroughApply
        /// Once a workout has ended, every start is refused as if it were still live.
        case refusesAStartAfterAnEnd
        /// `apply` returns the state before the event.
        case returnsTheStateBefore
        /// An update carries no haptic at all.
        case dropsTheHaptics
        /// A new stream's first element repeats the last update's haptics.
        case firstElementCarriesHaptics
        /// Only the first stream is served: a later one gets its first element and ends.
        case servesOneSubscriber
        /// A stream keeps only its newest update, as the repositories' observations do.
        case keepsOnlyTheNewestUpdate
        /// An accepted event that leaves the state as it was is not published.
        case skipsUnchangedStates
        /// An event the engine ignores is published as one more, unchanged update.
        case publishesIgnoredEvents
        /// Once one consumer has stopped, the next publication ends every stream.
        case cancellationEndsEveryStream
        /// `apply` suspends between reading the workout and committing: callers at once start from one state.
        case losesAnEditBetweenCallers
        /// `start` suspends between "nothing is live" and its commit: starts at once all succeed.
        case startsTwiceAtOnce
        /// An end suspends before it commits: ends at once all end the workout.
        case endsTwiceAtOnce
        /// An end is published before the workout is let go, across a suspension: an `apply` lands after it.
        case appliesAfterTheEnd
        /// `updates()` suspends between reading the workout and registering the stream.
        case registersAfterASuspension

        var description: String {
            rawValue
        }

        /// How the name of the clause this fault must break begins.
        var brokenClause: String {
            Self.brokenClauses[self] ?? "no clause is named for \(rawValue)"
        }

        /// Whether the fault shows only when two calls are inside the client at once. No test can force
        /// that, so such a fault is given several runs to show.
        var needsOverlap: Bool {
            Self.overlapping.contains(self)
        }

        /// Whether a seeded script can meet the fault: a script makes its calls one after another and
        /// cancels no subscriber.
        var showsInAScript: Bool {
            !needsOverlap && self != .cancellationEndsEveryStream
        }

        static let overlapping: Set<Fault> = [
            .losesAnEditBetweenCallers, .startsTwiceAtOnce, .endsTwiceAtOnce, .appliesAfterTheEnd,
            .registersAfterASuspension
        ]

        static let brokenClauses: [Fault: String] = [
            .duplicatesTheFirstElement: "a new client has no workout",
            .startBuzzes: "start makes a live snapshot current",
            .secondStartReplaces: "a second start throws workoutInProgress",
            .judgesTheSessionFirst: "a snapshot the engine would not start",
            .judgesSnapshotsByPhaseAlone: "a snapshot the engine would not start",
            .startsThroughApply: "apply, finish and discard with nothing live",
            .keepsTheEndedWorkoutCurrent: "finish returns the finished state",
            .publishesNilAfterTheEnd: "finish returns the finished state",
            .discardsSilently: "discard publishes the discarded state once",
            .returnsFromAnIgnoredEnd: "finish and discard at a date the engine ignores",
            .terminalThroughApplyStaysLive: "a terminal event through apply",
            .movesTheEndThroughApply: "a terminal event through apply",
            .refusesAStartAfterAnEnd: "after a workout ends another can start",
            .returnsTheStateBefore: "apply returns the state after the event",
            .dropsTheHaptics: "apply returns the state after the event",
            .firstElementCarriesHaptics: "a stream opened on a live workout starts with it",
            .servesOneSubscriber: "two subscribers",
            .keepsOnlyTheNewestUpdate: "updates under rapid apply calls",
            .skipsUnchangedStates: "an event the engine accepts is published once",
            .publishesIgnoredEvents: "an event the engine ignores",
            .cancellationEndsEveryStream: "a subscriber whose task is cancelled",
            .losesAnEditBetweenCallers: "callers at once",
            .startsTwiceAtOnce: "starts at once",
            .endsTwiceAtOnce: "ends at once",
            .appliesAfterTheEnd: "an apply against an end",
            .registersAfterASuspension: "a stream opened while calls are in flight"
        ]
    }
}
