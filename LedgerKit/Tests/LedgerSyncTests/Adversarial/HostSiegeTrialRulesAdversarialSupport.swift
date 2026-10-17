import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport

// MARK: - Memory follows the store

extension SiegeTrial {
    /// After a step: `current()` is the stored live log; or, with none, nil or a workout whose end waits.
    func standingIssue() async throws -> String? {
        let fired = await rig.siege.fired
        let current: WorkoutState?
        do {
            current = try await host.current()
        } catch {
            return await rig.siege.fired == fired ? "current() threw \(error) though no store call failed" : nil
        }
        guard await rig.siege.fired == fired else {
            return nil
        }
        let truth = try await rig.truth()
        if let live = truth.live.first {
            let told = "current() is \(Self.brief(current)), the stored live log \(Self.brief(live))"
            return current == live ? nil : told
        }
        guard let current, current != waiting else {
            return nil
        }
        for ended in truth.ended where try await rig.standing(ended.id) == current {
            return nil
        }
        return "current() is \(Self.brief(current)), which the store holds no live log for"
    }

    static func brief(_ state: WorkoutState?) -> String {
        state.map { Seam.brief(WorkoutSessionUpdate(state: $0)) } ?? "no workout"
    }

    /// A host's stream, read to where it stands: it starts without haptics, never says "no workout" again,
    /// ends a workout at most once and says nothing of it afterwards.
    func streamIssue() async -> String? {
        let heard = await Seam.buffered(stream)
        guard let first = heard.first, first.haptics.isEmpty else {
            return "a stream's first element is missing or carries haptics"
        }
        var ended: Set<WorkoutID> = []
        for update in heard.dropFirst() {
            guard let state = update.state else {
                return "a stream carries \"no workout\" after its first element"
            }
            guard !ended.contains(state.id) else {
                return "a stream carries \(Seam.brief(update)) after that workout's ending update"
            }
            if state.phase != .live {
                ended.insert(state.id)
            }
        }
        return nil
    }
}

// MARK: - The end: one clean launch, then the whole record

extension SiegeTrial {
    mutating func closing() async throws -> String? {
        await rig.siege.heal()
        if let issue = await streamIssue() {
            return issue
        }
        host = await rig.host()
        let resumed: WorkoutState?
        do {
            resumed = try await host.resumeFromStore()
        } catch {
            return "the launch step threw \(error) with no fault left"
        }
        if await host.needsRecovery {
            return "needsRecovery is true after a launch step that met no fault"
        }
        let truth = try await rig.truth()
        guard truth.ended.isEmpty, truth.empty.isEmpty, truth.live.count <= 1 else {
            return "after a clean launch the store still holds \(truth.ended.count) ended logs, "
                + "\(truth.empty.count) that replay to nothing and \(truth.live.count) live ones"
        }
        let current = try await host.current()
        guard resumed == truth.live.first, current == resumed else {
            return "after a clean launch the host's workout is not the stored live log"
        }
        return try await recordIssue(live: resumed)
    }

    func recordIssue(live: WorkoutState?) async throws -> String? {
        let stored = await rig.siege.stored
        for (index, envelope) in stored.enumerated() {
            if stored[..<index].contains(where: { $0.event == envelope.event }) {
                return "stored twice: \(SeamCall.apply(envelope.event))"
            }
            if !asked.contains(envelope.event) {
                return "stored an event no call asked for: \(SeamCall.apply(envelope.event))"
            }
        }
        if let lost = kept.first(where: { call in !stored.contains { $0.event == call.event } }) {
            return "lost: the call of step \(lost.step) returned, and no log ever held its event:\n"
                + trace.prefix(lost.step + 3).suffix(12).joined(separator: "\n")
        }
        if let extra = unwanted.first(where: { event in stored.contains { $0.event == event } }) {
            return "a call that was refused or ignored left \(SeamCall.apply(extra)) in a log"
        }
        let history = try await rig.history()
        let logs = Dictionary(grouping: stored, by: \.workoutID)
        for (workout, log) in logs {
            if let issue = try await logIssue(log, live: live, history: history.filter { $0.id == workout }) {
                return "workout \(workout.rawValue.uuidString.suffix(6)): \(issue)"
            }
        }
        return history.allSatisfy { logs[$0.id] != nil } ? nil : "history holds a workout no log ever started"
    }

    /// One workout's envelopes, in the order the store took them.
    func logIssue(_ log: [EventEnvelope], live: WorkoutState?, history: [WorkoutState]) async throws -> String? {
        guard log.map(\.seq) == Array(1 ... UInt64(log.count)), log.allSatisfy({ $0.device == rig.device }) else {
            return "seqs \(log.map(\.seq)) are not 1, 2, 3, … of this device"
        }
        guard zip(log, log.dropFirst()).allSatisfy({ $0.wallClock < $1.wallClock }) else {
            return "stamps do not rise with seq"
        }
        guard let final = WorkoutEngine.replay(log) else {
            return history.isEmpty ? nil : "replays to nothing, and is in history"
        }
        switch final.phase {
        case .finished:
            let expected = try await [rig.asStored(final)].compactMap(\.self)
            return history == expected ? nil : "finished, and history holds \(history.count) of it, or another"
        case .live:
            return history.isEmpty && live == final ? nil : "live in its log, and not the host's workout"
        case .discarded:
            return history.isEmpty ? nil : "discarded, and in history"
        }
    }
}

extension SeamCall {
    var isApply: Bool {
        if case .apply = self {
            return true
        }
        return false
    }
}
