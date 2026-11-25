import Foundation
import LedgerDomain

/// The peer's envelopes (F17 S3; ADR-004, "The host loop", and F17 "Inputs from F04 / F05"): the host stores
/// every envelope it receives before it rebuilds, whatever the envelope holds, and never reduces one. When the
/// store took anything new, the workout is what its stored log replays to, and the effects are
/// `WorkoutEngine.effects(from:to:)`'s: at most one haptic per rebuild, none at an end, and never a transmit.
public extension LocalWorkoutSessionActor {
    /// How far ahead of this device's clock a received stamp may lie. A stamp further ahead is dropped on
    /// receipt: the hybrid logical clock would otherwise drag every later stamp of this device up to it, and above
    /// 2⁴⁴ s it could no longer move on at all (F17 "Inputs from F04", items 3 and 9). A peer's clock behind this
    /// one's is no harm (its envelopes sort earlier), so there is no bound below.
    static let driftBound: TimeInterval = 60 * 60

    /// Takes envelopes the peer sent, of any workout, in any order, as often as they arrive. Queued like every
    /// call, so it never overlaps one.
    ///
    /// - Dropped before anything is stored, with their keys logged: an envelope with a date that is not finite
    ///   (`EventEnvelope.hasFiniteDates`), and one stamped more than `driftBound` ahead of this device's clock.
    /// - The rest is appended per workout. When the store refuses a batch for a conflicting key (a peer that
    ///   reused a `seq`), the batch is appended again one envelope at a time and only the conflicting ones are
    ///   dropped, so a resent batch can never fail for good.
    /// - A workout whose log took something new is rebuilt by `WorkoutEngine.replay`. The live workout is
    ///   published with the rebuild's haptics, its rest notification follows, and an end the peer made completes
    ///   as an own end does (`finish(endedAt:)`). With no live workout, a live workout the peer started becomes
    ///   the live one; one that arrives already ended is saved or dropped without being shown. A log that
    ///   replays to nothing (its `started` has not arrived) waits in the store, and a second live workout waits
    ///   for the double-start rule (F17 S5).
    ///
    /// Throws what the store threw; what it stored before then stays stored, and the next call recovers first.
    /// Also throws, before storing anything, what kept a waiting end from completing.
    func receive(_ envelopes: [EventEnvelope]) async throws {
        try await inTurn { try await self.take(envelopes) }
    }

    /// Whether a device other than this one took part in `workout`: its log holds another device's envelope,
    /// or this host received one for it since it was built (a finished workout's log is dropped with its save).
    /// F16's phone-only Health save asks it (`LiveHealthStore`'s `watchTookPart`), and refuses to write a
    /// workout the watch writes. A store that cannot be read answers `true`, and a fault is logged: a workout
    /// missing from Health is better than one written twice.
    func hasWatchParticipant(_ workout: WorkoutID) async -> Bool {
        guard !participants.contains(workout) else {
            return true
        }
        do {
            return try await events.envelopes(for: workout).contains { $0.device != device }
        } catch {
            logger.fault("Participants of \(workout.rawValue, privacy: .public) unknown: \(String(describing: error))")
            return true
        }
    }
}

extension LocalWorkoutSessionActor {
    /// `receive`, in its turn.
    private func take(_ received: [EventEnvelope]) async throws {
        try await ready()
        try await settle()
        let limit = now().addingTimeInterval(Self.driftBound)
        var accepted: [EventEnvelope] = []
        for envelope in received {
            guard envelope.hasFiniteDates, envelope.wallClock <= limit else {
                logger.error("Dropped a received envelope (\(Self.describe(envelope.key), privacy: .public))")
                continue
            }
            accepted.append(envelope)
        }
        var workouts: [WorkoutID] = []
        for envelope in accepted where !workouts.contains(envelope.workoutID) {
            workouts.append(envelope.workoutID)
        }
        for workout in workouts {
            let stored = try await store(accepted.filter { $0.workoutID == workout })
            guard !stored.isEmpty else {
                continue
            }
            for envelope in stored {
                clock.observe(envelope.wallClock)
            }
            if stored.contains(where: { $0.device != device }) {
                participants.insert(workout)
            }
            try await rebuild(workout, after: stored)
        }
    }

    /// Appends `batch`, all of one workout, and returns what the store newly took. On a conflict, appends it
    /// again one envelope at a time, dropping each that conflicts (F17 "Inputs from F04", item 1).
    private func store(_ batch: [EventEnvelope]) async throws -> [EventEnvelope] {
        do {
            return try await append(batch)
        } catch EngineError.conflictingEnvelope {
            var stored: [EventEnvelope] = []
            for envelope in batch {
                do {
                    stored += try await append([envelope])
                } catch let EngineError.conflictingEnvelope(key) {
                    logger.error("Dropped a received envelope that conflicts (\(Self.describe(key), privacy: .public))")
                }
            }
            return stored
        }
    }

    /// One append. When the store fails other than by refusing a conflict (which stores nothing), what it holds
    /// is no longer known, so the next call recovers first.
    private func append(_ envelopes: [EventEnvelope]) async throws -> [EventEnvelope] {
        do {
            return try await events.append(envelopes)
        } catch {
            if !(error is EngineError) {
                isRecovered = false
            }
            throw error
        }
    }

    /// The workout after its log took `stored`, and what follows from the change.
    private func rebuild(_ workout: WorkoutID, after stored: [EventEnvelope]) async throws {
        let log = try await events.envelopes(for: workout)
        let isLive = workout == live?.id
        let fresh = Set(stored.map(\.key))
        let before = isLive ? live : WorkoutEngine.replay(log.filter { !fresh.contains($0.key) })
        let after = WorkoutEngine.replay(log)
        if isLive {
            // The peer may relay this device's own envelopes (a gap replay after a reinstall): never reuse a seq.
            seq = stored.filter { $0.device == device }.map(\.seq).reduce(seq, max)
        }
        let effects = WorkoutEngine.effects(from: before, to: after)
        guard let after, !effects.isEmpty else {
            return
        }
        let haptics = WorkoutSessionUpdate.haptics(from: effects)
        if !isLive, live != nil || after.phase != .live {
            try await settleUnshown(after)
            return
        }
        if !isLive {
            seq = try await events.highestSeq(for: workout, device: device) ?? 0
        }
        guard after.phase == .live else {
            try await endByPeer(after, haptics: haptics, effects: effects)
            return
        }
        live = after
        publish(after, haptics)
        await notify(effects)
    }

    /// The live workout ended in its log by the peer's envelopes: it completes as an own end does, unless the log
    /// holds rows this version cannot read, which the host never saves; it then stays live, as `apply` keeps a
    /// finish it refuses.
    private func endByPeer(_ ended: WorkoutState, haptics: [Haptic], effects: [Effect]) async throws {
        if ended.phase == .finished, try await events.unreadableCount(for: ended.id) > 0 {
            logger
                .notice("The peer finished \(ended.id.rawValue, privacy: .public), whose log is incomplete; kept live")
            return
        }
        ending = Ending(state: ended, haptics: haptics)
        await notify(effects)
        try await settle()
    }

    /// A workout no reader is shown: an ended one is saved or dropped as recovery does, unpublished; a second live
    /// one waits in the store.
    private func settleUnshown(_ state: WorkoutState) async throws {
        guard state.phase != .live else {
            logger.notice("A second live workout arrived (\(state.id.rawValue, privacy: .public)); kept")
            return
        }
        do {
            try await complete(state)
        } catch WorkoutSessionError.incompleteLog {
            logger.notice("Received log \(state.id.rawValue, privacy: .public) is finished but incomplete; kept")
        }
    }

    /// An envelope's key for a log line: the device and the seq, never what it holds.
    private static func describe(_ key: EnvelopeKey) -> String {
        "\(key.device.rawValue.uuidString) #\(key.seq)"
    }
}
