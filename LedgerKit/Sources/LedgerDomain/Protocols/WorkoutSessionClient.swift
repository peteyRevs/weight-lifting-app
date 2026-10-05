import Foundation

/// The live workout as one device hosts it: what Today, the workout screen and the watch call, and what they
/// watch. The host (`LocalWorkoutSessionActor`, F10 S2) stamps each call's event, reduces it with
/// `WorkoutEngine`, stores it and publishes the result (ADR-004, "The host loop");
/// `FakeWorkoutSessionClient` in LedgerFakes does the same without a store. `WorkoutSessionClientContract` in
/// LedgerTestSupport holds both to the rules written here.
///
/// Every method waits for the host's launch recovery, which is the composition root's step and not part of
/// this protocol, so a call can never race it. The rules hold when calls overlap: a client takes them one at
/// a time, so every caller and every subscriber is told the same one story.
///
/// A call that throws publishes nothing of its own, and has stored nothing, except an end that reached the
/// log before its save or its drop failed (`finish(endedAt:)`). Two things can still reach readers while a
/// call runs, whether or not it then throws: an end that was waiting, which the call completes first, and,
/// after a write that failed, the state the host finds in its store. A workout whose end is stored but
/// could not be completed is still the workout readers see and, in this process, the one workout there may
/// be, until the host has completed its end.
public protocol WorkoutSessionClient: Sendable {
    /// The workout as it stands (the first element, with no haptics), then one update for each call whose
    /// event the engine accepts, in the order the events were applied. A host may publish further updates for
    /// changes that do not come from this client's calls.
    ///
    /// Each call returns a new stream, registered before the call returns, so it misses no later update: a
    /// stream opened while other calls are in flight starts with a state the client published, and each
    /// update after it follows from the one before. A stream is unbounded, because a dropped update would
    /// drop a haptic, and it ends only when its consumer stops: its task is cancelled, or the stream is
    /// dropped.
    func updates() async -> AsyncStream<WorkoutSessionUpdate>

    /// The live workout, or nil when there is none: the `live` of the last update. Throws only what kept a
    /// host from reading its store.
    func current() async throws -> WorkoutState?

    /// Makes `initial` the live workout and publishes it.
    ///
    /// Throws `notStartable` for a snapshot the engine would not start, whether or not a workout is live, and
    /// `workoutInProgress` while one is. A refused start changes nothing and publishes nothing. Of several
    /// starts made at once exactly one succeeds, and the others throw `workoutInProgress` naming its workout.
    /// So does a start made again after a write whose answer was lost, when the host has since found that
    /// workout in its store: it names the caller's own workout, which is live.
    func start(_ initial: WorkoutState) async throws

    /// Applies `event` to the live workout and returns the state after it, which the next update also carries.
    ///
    /// - An event the engine accepts is published once, even when it leaves this device's state as it was: it
    ///   is part of the workout's log all the same, because a peer may order it differently (ADR-004).
    /// - An event the engine ignores (a malformed one, `EventEnvelope.isWellFormed`, or a second `started`)
    ///   changes nothing: the workout is returned as it stands and no update is published.
    /// - A terminal event ends the workout as `finish(endedAt:)` and `discard(endedAt:)` do, except that one
    ///   the engine ignores is an ignored event like any other.
    ///
    /// Throws `noLiveWorkout` when there is none, which includes an `apply` that loses to an overlapping end.
    /// While an end waits to be completed (`finish(endedAt:)`), the host completes it first: `apply` then
    /// throws `noLiveWorkout`, or what kept the end from being completed.
    @discardableResult
    func apply(_ event: WorkoutEvent) async throws -> WorkoutState

    /// Ends the live workout at `endedAt` and returns the finished state, which one last update carries. That
    /// update is published once the workout is stored, so a consumer may read history when it arrives.
    /// Afterwards there is no live workout: `current()` is nil and a new stream starts with a nil state. Of
    /// several overlapping `finish` and `discard` calls exactly one ends the workout.
    ///
    /// Throws `noLiveWorkout` when there is none; `invalidEndDate` when the workout is still live after the
    /// call because the engine ignored the end, as it does for a date that is not finite (nothing ends and
    /// nothing is published); and `incompleteLog` when the host cannot store the workout yet, in which case
    /// the workout stays live.
    ///
    /// **When the save fails** a host throws what its store threw, and nothing is lost: the end stays in the
    /// workout's log. No update is published, and `current()` and every stream go on showing the workout as
    /// it stood before the call, with a phase of `.live`: nothing tells a reader that its end is stored and
    /// waiting. The host saves it again when `finish` is called again, which returns the finished state,
    /// ended when the first call said; before any `apply` or `discard`; and when the app next launches or
    /// returns to the foreground. The first save that succeeds publishes the one ending update. A `finish`
    /// called after that throws `noLiveWorkout`: a retry can find the end completed in between, by the launch
    /// step or, after a write whose answer was lost, by the host reading its store.
    ///
    /// That holds in this process. After a relaunch the unsaved workout is no longer shown, another can be
    /// started, and the launch step saves the first when it can.
    ///
    /// Three things follow for a caller while an end waits:
    /// - **`discard` saves the workout.** It completes the waiting finish and then throws `noLiveWorkout`;
    ///   so does `apply`. A lifter who answers a failed save with "Discard" gets the workout in history.
    /// - **`StartWorkoutUseCase` sees an ordinary live workout.** For the same day it answers `.resumed`,
    ///   with a workout that accepts no change; for another day `.conflict`, and replacing it saves it and
    ///   starts the new one, or throws what the store throws and starts nothing.
    /// - **A save that can never succeed leaves no exit in this process.** `finish`, `apply` and `discard`
    ///   throw the store's error each time, `start` answers `workoutInProgress`, and every return to the
    ///   foreground tries the save again. Only a relaunch frees the workout's place.
    func finish(endedAt: Date) async throws -> WorkoutState

    /// Ends the live workout at `endedAt` and drops it; one last update carries the discarded state, and is
    /// published once the workout's log is dropped. Afterwards there is no live workout, as after
    /// `finish(endedAt:)`.
    ///
    /// Throws `noLiveWorkout` when there is none, and `invalidEndDate` when the workout is still live after
    /// the call because the engine ignored the end (nothing ends and nothing is published). When the log
    /// cannot be dropped a host throws what its store threw, and the end waits as a failed save does
    /// (`finish(endedAt:)`): calling `discard` again completes it.
    func discard(endedAt: Date) async throws
}

/// One element of `WorkoutSessionClient.updates()`: the workout after a change, and the haptics that go with
/// it.
public struct WorkoutSessionUpdate: Hashable, Sendable {
    /// The workout: live; finished or discarded in the one update that ends it; nil when there is no
    /// workout, which only a stream's first element can say.
    public let state: WorkoutState?
    /// The haptics of the change, in order (`haptics(from:)`). Empty in a stream's first element. Every
    /// subscriber receives them; exactly one, on the workout side, plays them. Today reads `state` only.
    public let haptics: [Haptic]

    public init(state: WorkoutState?, haptics: [Haptic] = []) {
        self.state = state
        self.haptics = haptics
    }

    /// `state` while its workout is live, else nil: what Today's Resume button and the workout screen show.
    public var live: WorkoutState? {
        state?.phase == .live ? state : nil
    }

    /// The one forwarding rule: of the engine's effects for a change, an update carries the haptics, in the
    /// engine's order. The host runs every other effect itself (storage, the rest notification, the Live
    /// Activity), because a workout also changes while no screen is alive to run them; the type keeps a host
    /// from forwarding one.
    public static func haptics(from effects: [Effect]) -> [Haptic] {
        effects.compactMap { effect -> Haptic? in
            guard case let .haptic(haptic) = effect else {
                return nil
            }
            return haptic
        }
    }
}

/// Why a `WorkoutSessionClient` refused a call.
public enum WorkoutSessionError: Error, Equatable, Sendable {
    /// `start` while this workout is live.
    case workoutInProgress(WorkoutID)
    /// `start` with a snapshot the engine would not start: one that is not live, or is malformed.
    case notStartable(WorkoutID)
    /// `apply`, `finish` or `discard` with no live workout.
    case noLiveWorkout
    /// `finish` while the workout's log holds envelopes this app version cannot read
    /// (`WorkoutEventStore.unreadableCount(for:)`): the host never stores or compacts such a log. The workout
    /// stays live; it can be discarded, and its log is then kept for a version that reads it.
    case incompleteLog(WorkoutID)
    /// `finish` or `discard` after which the workout is still live: the engine ignored the end, as it does
    /// for a date that is not finite (`EventEnvelope.isWellFormed`). Nothing ended and nothing was published.
    case invalidEndDate
}
