import Foundation
import LedgerDomain

/// One way a `WorkoutSessionClient` can be wrong: the rule of the brief (F10 "Plan amendments", slice S1,
/// criteria 1 to 4) or of the protocol's documentation that it breaks.
enum SeamFault: String, Sendable, CaseIterable, CustomStringConvertible {
    // Criterion 1: the stream.
    case firstElementRepeatsEffects = "gives a new stream the last update's effects in its first element"
    case firstElementIsStale = "gives a new stream the workout before the last change as its first element"
    case endedShownToNewStreams = "starts a new stream with the ended workout, not with nil"
    case onlyFirstSubscriber = "publishes to its first subscriber only: a later stream ends after its first element"
    case newestOnly = "keeps only the newest unread update of a stream"
    case duplicatesUpdates = "publishes every update twice"
    case swapsForSecondSubscriber = "gives its second subscriber each set edit after the update that follows it"
    case endsStreamsWithTheWorkout = "ends every stream when the workout ends"
    case cancelEndsEveryone = "ends every stream once one consumer has stopped"
    // Criterion 2: starting, and calls with nothing live.
    case startUnpublished = "publishes nothing for a start: its streams end there instead"
    case secondStartReplaces = "lets a second start replace the live workout"
    case unstartableStartIsSilent = "returns from a start the engine would not make, having started nothing"
    case inProgressBeforeNotStartable = "answers an unstartable snapshot with workoutInProgress while a workout is live"
    case inProgressNamesTheNewWorkout = "names the offered workout, not the live one, in workoutInProgress"
    case applyStartsWhenIdle = "lets apply(.started) start a workout when none is live"
    case discardSilentWhenIdle = "returns from discard with nothing live"
    case restartRefused = "refuses a start after a workout has ended"
    case judgesSnapshotsByPhaseAndStart = "starts any live snapshot with a finite start, whatever else it holds"
    // Criterion 3: apply.
    case returnsStateBefore = "returns from apply the state before the event"
    case dropsHaptics = "forwards no effect at all"
    case publishesIgnored = "publishes an update for an event the engine ignores"
    case skipsUnchanged = "publishes nothing for an accepted event that leaves the workout as it was"
    case currentLags = "answers current() with the workout before the last change"
    // Criterion 4: ending.
    case finishLeavesCurrent = "keeps the finished workout as current()"
    case discardLeavesCurrent = "keeps the discarded workout as current()"
    case terminalApplyLeavesCurrent = "keeps the workout as current() after a terminal event through apply"
    case finishUnpublished = "publishes nothing for a finish"
    case discardUnpublished = "publishes nothing for a discard"
    case endPublishesNil = "publishes a second update, with no workout, after the one that ends it"
    case nonFiniteEndEnds = "drops the workout on a finish or discard whose date the engine ignores"
    case terminalApplyMovesTheEnd = "ends a workout through apply a second later than the event says"
    /// F10-S1-1, as ruled: what the protocol documented before round 1's ruling (returning the workout
    /// still live) is now the fault; criterion 4 has `finish` and `discard` throw `invalidEndDate`.
    case nonFiniteEndReturns = "returns from a finish or discard whose date the engine ignores"
    /// The contract's documentation says a client whose streams have no first element keeps a clause
    /// waiting until the suite's time limit fails it, so no test here runs it.
    case noFirstElement = "gives a stream no first element"
    // Only when calls overlap.
    case racyLostUpdate = "reduces from a state read before a suspension, so overlapping applies lose one"
    case racyReversed = "publishes the updates of overlapping applies in reverse order"
    case racyScrambled = "publishes the updates of overlapping applies with the first two swapped, the last in place"
    case racySecondSubscriberScrambled = "gives its second subscriber overlapping applies' updates in another order"
    case racyDropsOne = "publishes all but the first of the updates of overlapping applies"
    case racyReturnsLatest = "returns from overlapping applies the newest state, not the one after each caller's event"
    case racyLateRegistration = "registers a stream after a suspension, so it misses what is published meanwhile"
    case racyDoubleStart = "suspends between a start's checks and its commit, so overlapping starts all succeed"
    case racyDoubleEnd = "suspends before an end's commit, so overlapping finishes and discards all succeed"
    case racyApplyAfterEnd = "publishes an end and suspends before it lets go, so an overlapping apply lands after it"

    var description: String {
        rawValue
    }

    /// Faults that show only when calls overlap: whether a run meets one depends on the scheduler.
    static let racy: [SeamFault] = [
        .racyLostUpdate, .racyReversed, .racyScrambled, .racySecondSubscriberScrambled, .racyDropsOne,
        .racyReturnsLatest, .racyLateRegistration, .racyDoubleStart, .racyDoubleEnd, .racyApplyAfterEnd
    ]
    /// The racy faults that commit each apply in turn and then publish the overlapping ones together.
    static let batching: Set<SeamFault> = [
        .racyReversed, .racyScrambled, .racySecondSubscriberScrambled, .racyDropsOne, .racyReturnsLatest
    ]
    /// Faults that show on calls made one after another, and leave no reader waiting for an update that
    /// never comes.
    static let sequential = allCases.filter { !(racy + [.noFirstElement, .nonFiniteEndReturns]).contains($0) }
}

extension WorkoutEvent {
    /// A log or a stepper edit: what `swapsForSecondSubscriber` holds back.
    var isSetEdit: Bool {
        switch self {
        case .setLogged, .setTargetChanged: true
        default: false
        }
    }
}
