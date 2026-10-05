import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport

/// Many callers at once on one host whose stores give way inside every call (F10 S2 adversarial round 1,
/// re-entrancy). Which call wins is the scheduler's choice, so the outcome is judged against the one thing
/// that cannot lie: what the store took, in the order it took it.
///
/// - the stored envelopes are one history: one workout at a time, each `seq` once and in order, stamps rising;
/// - a stream from before the first call carries exactly that history, as `WorkoutEngine.reduce` folds it;
/// - a stream opened in flight is a suffix of it;
/// - every call that returned is in the store once, and what it returned is a published state;
/// - every other call threw a `WorkoutSessionError`;
/// - history holds the workouts that finished, and the store's logs the one still live.
enum SiegeStorm {
    enum Action: Sendable {
        case call(SeamCall)
        case open
    }

    struct Heard: Sendable {
        var outcomes: [(call: SeamCall, outcome: SeamOutcome)] = []
        var streams: [AsyncStream<WorkoutSessionUpdate>] = []
    }

    static let tasks = 6
    static let actions = 7

    /// The calls of `seed`: every one differs from every other, and none depends on what is live.
    static func script(seed: UInt64) -> [[Action]] {
        var random = SeamRandom(seed: seed)
        var unique = 0
        return (0 ..< tasks).map { task in
            (0 ..< actions).map { index in
                unique += 1
                return action(unique, first: task == 0 && index == 0, using: &random)
            }
        }
    }

    private static func action(_ unique: Int, first: Bool, using random: inout SeamRandom) -> Action {
        let date = Seam.at(Double(unique) * 5)
        let weight = Weight.pounds(Decimal(unique) * 2.5)
        switch first ? 0 : Int.random(in: 0 ..< 20, using: &random) {
        case 0 ..< 3:
            return .call(.start(Seam.session(0x5700 + unique, EventBuilders.supersetExercises)))
        case 3 ..< 6:
            return .call(.apply(.restStarted(endsAt: date, total: .seconds(60))))
        case 6 ..< 9:
            return .call(.apply(.allSetsRepeated(exerciseIndex: unique % 2, weight: weight, reps: .one)))
        case 9 ..< 12:
            let added = LoggedSet(id: Seam.freshSet(0x5700 + unique).id, weight: weight, reps: .one, kind: .added)
            return .call(.apply(.setAdded(exerciseIndex: unique % 2, set: added)))
        case 12, 13:
            return .call(.apply(.restExtended(amount: .seconds(30), extendsShownRest: unique % 2 == 0, tappedAt: date)))
        case 14, 15:
            return .call(.finish(date))
        case 16:
            return .call(.discard(date))
        case 17:
            return .call(.apply(.finished(endedAt: date)))
        default:
            return .open
        }
    }

    /// Runs the script's tasks at once on `host` and returns what each heard.
    static func run(_ script: [[Action]], on host: any WorkoutSessionClient) async -> [Heard] {
        await withTaskGroup(of: Heard.self) { group in
            for steps in script {
                group.addTask {
                    var heard = Heard()
                    for action in steps {
                        switch action {
                        case let .call(call): await heard.outcomes.append((call, Seam.outcome(of: call, on: host)))
                        case .open: await heard.streams.append(host.updates())
                        }
                    }
                    return heard
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
    }

    /// `nil` when the storm of `seed` left one history, else the first thing that is not. `wrap` puts a
    /// client of the test's between the callers and the host: a racy one must not get through.
    static func violation(
        seed: UInt64,
        backing: SiegeRig.Backing,
        wrap: (LocalWorkoutSessionActor) -> any WorkoutSessionClient = { $0 }
    ) async throws -> String? {
        let rig = try await SiegeRig.make(backing, yields: 1 + Int(seed % 3))
        let host = await wrap(rig.host())
        var early = await SeamReader(host)
        let heard = await run(script(seed: seed), on: host)
        let mark = try await Seam.mark(host, Int(seed % 1000))
        let stored = await rig.siege.stored
        let history = SiegeRig.updates(for: stored)
        if let issue = logIssue(stored, device: rig.device) {
            return issue
        }
        let told = await early.through(mark)
        if let issue = Seam.difference(told, [WorkoutSessionUpdate(state: nil)] + history, "the first stream") {
            return issue
        }
        for stream in heard.flatMap(\.streams) {
            var late = SeamReader(stream)
            if let issue = await lateIssue(late.through(mark), in: history) {
                return issue
            }
        }
        if let issue = answerIssue(heard.flatMap(\.outcomes), stored: stored, history: history) {
            return issue
        }
        return try await storeIssue(rig, stored: stored)
    }
}

// MARK: - The rules

extension SiegeStorm {
    /// One workout at a time, each with seq 1, 2, 3, … of this device and rising stamps.
    static func logIssue(_ stored: [EventEnvelope], device: DeviceID) -> String? {
        var live: WorkoutID?
        var seqs: [WorkoutID: UInt64] = [:]
        var newest: Date?
        for envelope in stored {
            if case .started = envelope.event {
                guard live == nil else {
                    return "a second workout was stored as started while one was live"
                }
                live = envelope.workoutID
            }
            guard envelope.workoutID == live, envelope.device == device else {
                return "an envelope was stored for a workout that was not the live one"
            }
            guard envelope.seq == seqs[envelope.workoutID, default: 0] + 1 else {
                return "seq \(envelope.seq) was stored after seq \(seqs[envelope.workoutID, default: 0])"
            }
            guard newest.map({ $0 < envelope.wallClock }) ?? true else {
                return "a stamp did not rise"
            }
            seqs[envelope.workoutID] = envelope.seq
            newest = envelope.wallClock
            live = envelope.event.isTerminal ? nil : live
        }
        return nil
    }

    /// A stream opened in flight: a state that was published (or "no workout"), without haptics, then every
    /// later update, none missed and none repeated.
    static func lateIssue(_ told: [WorkoutSessionUpdate], in history: [WorkoutSessionUpdate]) -> String? {
        guard let first = told.first, first.haptics.isEmpty else {
            return "a late stream has no first element, or one with haptics"
        }
        let rest = Array(told.dropFirst())
        let standing = [nil] + history.map(\.live)
        let joins = standing.indices.filter { standing[$0] == first.state && Array(history[$0...]) == rest }
        return joins.isEmpty ? "a late stream starting with \(Seam.brief(first)) is no suffix of the history" : nil
    }

    /// Every call that returned is stored once and returned a published state; every other was refused.
    static func answerIssue(
        _ outcomes: [(call: SeamCall, outcome: SeamOutcome)],
        stored: [EventEnvelope],
        history: [WorkoutSessionUpdate]
    ) -> String? {
        var returned = 0
        for (call, outcome) in outcomes {
            switch outcome {
            case .threw:
                return "\(call) \(outcome)"
            case .refused:
                if stored.contains(where: { $0.event == call.event }) {
                    return "\(call) was refused and is in the log"
                }
            case .returned, .state:
                returned += 1
                if stored.count(where: { $0.event == call.event }) != 1 {
                    return "\(call) returned and is in the log \(stored.count { $0.event == call.event }) times"
                }
                let published = zip(stored, history).first { $0.0.event == call.event }?.1.state
                if let state = outcome.state, state != published {
                    return "\(call) returned a state that is not the one its update carried"
                }
            }
        }
        // The mark is the one stored envelope no call of the script made.
        return returned + 1 == stored.count ? nil : "\(stored.count - 1) envelopes for \(returned) calls that returned"
    }

    /// History holds each finished workout once, as replayed; the store's logs, the one still live.
    static func storeIssue(_ rig: SiegeRig, stored: [EventEnvelope]) async throws -> String? {
        var finished: [WorkoutState] = []
        var live: Set<WorkoutID> = []
        for (workout, log) in Dictionary(grouping: stored, by: \.workoutID) {
            guard let state = WorkoutEngine.replay(log) else {
                return "a stored log replays to nothing"
            }
            if state.phase == .finished, let kept = try await rig.asStored(state) {
                finished.append(kept)
            }
            if state.phase == .live {
                live.insert(workout)
            }
        }
        let history = try await rig.history()
        guard Set(history) == Set(finished), history.count == finished.count else {
            return "history holds \(history.count) workouts, the logs finished \(finished.count)"
        }
        return try await rig.uncompacted() == live ? nil : "the uncompacted logs are not the live workout's"
    }
}
