import Foundation
import LedgerDomain

/// `WorkoutSessionClient`'s documented contract as named clauses, which every implementation runs:
/// `FakeWorkoutSessionClient` (F10 S1) and the host, `LocalWorkoutSessionActor` (S2), both in
/// `LedgerSyncTests`, so a screen tested on the fake meets the same updates in the app.
///
/// Each clause gets a fresh client with no workout and no subscriber, and returns `nil` when the client keeps
/// it, or what it did instead. The clauses use the protocol alone. They do not observe, and so do not
/// constrain:
/// - an envelope's stamp (device, `seq`, wall clock): the fake counts from 1 and reads the clock it was given,
///   the host uses a hybrid logical clock, and an update carries none of the three;
/// - what a client stores, and every effect it runs itself (the log, the stored workout, the rest
///   notification, the Live Activity);
/// - recovery at launch, and a store that fails. Those are the host's own tests'.
///
/// Nothing waits on a clock. A clause ends by making one last change it can recognise (`markEnd(of:)`) and
/// reads each stream up to it, so a client that publishes too few or too many updates gets a line saying so.
/// Only a client that never publishes that change, or whose streams have no first element, keeps a clause
/// waiting, until the suite's time limit fails it.
public enum WorkoutSessionClientContract {
    public typealias Client = any WorkoutSessionClient
    public typealias Clause = ContractClause<Client>
    typealias Update = WorkoutSessionUpdate

    public static let clauses: [Clause] = lifecycleClauses + updateClauses

    /// Every clause's complaint about a client from `make`, which is called once per clause.
    public static func violations(of make: @Sendable () async throws -> Client) async -> [String] {
        var found: [String] = []
        for clause in clauses {
            do {
                if let issue = try await clause.check(make()) {
                    found.append("\(clause.name): \(issue)")
                }
            } catch {
                found.append("\(clause.name): threw \(error)")
            }
        }
        return found
    }

    // MARK: Fixtures

    /// Spec §6.3's five-exercise session as a live snapshot (`EventBuilders.seedSession()`).
    static let session = EventBuilders.seedSession()

    /// A second live snapshot, for another workout: the superset pair.
    static let other = EventBuilders.session(
        EventBuilders.supersetExercises,
        id: WorkoutID(EventBuilders.uuid(0xF101))
    )

    /// A date no envelope may carry (`EventEnvelope.isWellFormed`).
    static let never = Date(timeIntervalSinceReferenceDate: .infinity)

    /// `seconds` after the fixture start.
    static func at(_ seconds: Double) -> Date {
        EventBuilders.start.addingTimeInterval(seconds)
    }

    /// Row (`exerciseIndex`, `setIndex`) of `session` logged at 185 lb × 5, done `seconds` after the start.
    static func logged(_ exerciseIndex: Int, _ setIndex: Int, at seconds: Double = 60) -> WorkoutEvent {
        .setLogged(
            exerciseIndex: exerciseIndex,
            setID: EventBuilders.setID(exerciseIndex, setIndex),
            weight: .pounds(185),
            reps: Reps(clamping: 5),
            doneAt: at(seconds)
        )
    }

    /// A stepper edit of row (`exerciseIndex`, `setIndex`) of `session`: its weight becomes `pounds`.
    static func retargeted(_ exerciseIndex: Int, _ setIndex: Int, pounds: Decimal) -> WorkoutEvent {
        .setTargetChanged(
            exerciseIndex: exerciseIndex,
            setID: EventBuilders.setID(exerciseIndex, setIndex),
            weight: .pounds(pounds),
            reps: nil
        )
    }

    // MARK: The engine's answer

    /// What the engine makes of `event` on `state`: the update a client must publish for it, which is the
    /// state after it with `feedback(from:)` of the engine's effects, or `nil` when the engine ignores the
    /// event. The stamp is this function's own: neither the state nor the haptics depend on it.
    static func engineUpdate(_ state: WorkoutState?, _ event: WorkoutEvent, in workout: WorkoutID) -> Update? {
        let envelope = EventBuilders.envelope(event, seq: 1, at: EventBuilders.start, workoutID: workout)
        let (next, effects) = WorkoutEngine.reduce(state, envelope)
        return effects.isEmpty ? nil : Update(state: next, effects: Update.feedback(from: effects))
    }

    /// The updates the engine gives for `events` applied in turn to `state`: one for each it accepts.
    static func engineUpdates(from state: WorkoutState, _ events: [WorkoutEvent]) -> [Update] {
        var state = state
        var updates: [Update] = []
        for event in events {
            if let update = engineUpdate(state, event, in: state.id), let next = update.state {
                updates.append(update)
                state = next
            }
        }
        return updates
    }

    // MARK: Reading a stream

    /// One subscriber: a stream from `updates()`, read in order.
    struct Subscriber {
        private var iterator: AsyncStream<Update>.AsyncIterator

        init(_ client: Client) async {
            iterator = await client.updates().makeAsyncIterator()
        }

        /// Every update before the one that carries `mark`; the stream is left just after it. When the
        /// stream ends first, what it held.
        mutating func updates(before mark: WorkoutState) async -> [Update] {
            var seen: [Update] = []
            while let update = await iterator.next(), update.state != mark {
                seen.append(update)
            }
            return seen
        }
    }

    /// Makes one last change no clause makes itself, and returns the state it leaves, which every stream
    /// then carries: on a live workout a one-second rest ending a day after the start, otherwise the start
    /// of a workout of its own.
    static func markEnd(of client: Client) async throws -> WorkoutState {
        guard try await client.current() != nil else {
            let closing = EventBuilders.session(EventBuilders.seedExercises, id: WorkoutID(EventBuilders.uuid(0xF1FF)))
            try await client.start(closing)
            return closing
        }
        return try await client.apply(.restStarted(endsAt: at(86400), total: .seconds(1)))
    }

    /// `nil` when a stream carried exactly `expected`; else how many it carried and the first update that
    /// differs, in a few words, and in full when the few words are the same.
    static func expectUpdates(_ seen: [Update], _ expected: [Update], _ what: String = "updates") -> String? {
        guard seen != expected else {
            return nil
        }
        let index = zip(seen, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset
            ?? min(seen.count, expected.count)
        let got = seen.indices.contains(index) ? seen[index] : nil
        let wanted = expected.indices.contains(index) ? expected[index] : nil
        let line = "\(what): got \(seen.count), expected \(expected.count); "
            + "at \(index) got \(brief(got)), expected \(brief(wanted))"
        guard brief(got) == brief(wanted) else {
            return line
        }
        return "\(line); in full: got \(String(describing: got)), expected \(String(describing: wanted))"
    }

    /// An update in a few words, for a clause's complaint.
    static func brief(_ update: Update?) -> String {
        guard let update else {
            return "no update"
        }
        guard let state = update.state else {
            return "no workout, effects \(update.effects)"
        }
        let rest = state.rest.map { ", rest until \($0.endsAt.timeIntervalSince(EventBuilders.start)) s" } ?? ""
        return "\(state.phase) workout \(state.id.rawValue.uuidString.suffix(4)), "
            + "\(state.doneSets) of \(state.totalSets) sets done\(rest), effects \(update.effects)"
    }
}
