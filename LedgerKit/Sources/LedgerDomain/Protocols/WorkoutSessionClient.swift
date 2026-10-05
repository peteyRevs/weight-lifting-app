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

    /// The live workout, or nil when there is none.
    func current() async throws -> WorkoutState?

    /// Makes `initial` the live workout and publishes it.
    ///
    /// Throws `notStartable` for a snapshot the engine would not start, whether or not a workout is live, and
    /// `workoutInProgress` while one is. A refused start changes nothing and publishes nothing. Of several
    /// starts made at once exactly one succeeds, and the others throw `workoutInProgress` naming its workout.
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
    @discardableResult
    func apply(_ event: WorkoutEvent) async throws -> WorkoutState

    /// Ends the live workout at `endedAt` and returns the finished state, which one last update carries. That
    /// update is published once the workout is stored, so a consumer may read history when it arrives.
    /// Afterwards there is no live workout: `current()` is nil and a new stream starts with a nil state. Of
    /// several overlapping `finish` and `discard` calls exactly one ends the workout.
    ///
    /// Throws `noLiveWorkout` when there is none; `invalidEndDate` when the workout is still live after the
    /// call because the engine ignored the end, as it does for a date that is not finite (nothing ends and
    /// nothing is published); and `incompleteLog` when the host cannot store the workout yet.
    func finish(endedAt: Date) async throws -> WorkoutState

    /// Ends the live workout at `endedAt` and drops it; one last update carries the discarded state, and is
    /// published once the workout's log is dropped. Afterwards there is no live workout, as after
    /// `finish(endedAt:)`.
    ///
    /// Throws `noLiveWorkout` when there is none, and `invalidEndDate` when the workout is still live after
    /// the call because the engine ignored the end (nothing ends and nothing is published).
    func discard(endedAt: Date) async throws
}

/// One element of `WorkoutSessionClient.updates()`: the workout after a change, and what the screen should
/// play for it.
public struct WorkoutSessionUpdate: Hashable, Sendable {
    /// The workout: live; finished or discarded in the one update that ends it; nil when there is no
    /// workout, which only a stream's first element can say.
    public let state: WorkoutState?
    /// The haptics for the screen to play, in order (`haptics(from:)`). Empty in a stream's first element.
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
    /// (`WorkoutEventStore.unreadableCount(for:)`): the host never stores or compacts such a log.
    case incompleteLog(WorkoutID)
    /// `finish` or `discard` after which the workout is still live: the engine ignored the end, as it does
    /// for a date that is not finite (`EventEnvelope.isWellFormed`). Nothing ended and nothing was published.
    case invalidEndDate
}
