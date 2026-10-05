import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport

/// One seeded siege of `LocalWorkoutSessionActor` (F10 S2 adversarial round 1): a script of calls made one
/// after another while store calls fail, lose their answers or kill the process, the clock moves, and the app
/// is relaunched. The host is judged against its stores alone:
///
/// - **each call** made while no store call failed returns or throws what the brief's rules (`SeamOracle`)
///   say for the workout `WorkoutEngine.replay` makes of the stored log;
/// - **after each step** `current()` is that workout (or, while an end waits to be completed, the workout as
///   it stood before the end);
/// - **a call that returned** has its event in the log, a finished workout in history and a discarded one
///   out of it, at once;
/// - **at the end**, after one clean launch: every log is what its envelopes replay to, each `seq` once and
///   in order with rising stamps, nothing stored twice, nothing stored that no call asked for or that a call
///   refused, every finished workout in history once and as the engine replays it, no other workout there.
struct SiegeTrial {
    let rig: SiegeRig
    var writer: SiegeScriptWriter
    var host: LocalWorkoutSessionActor
    var stream: AsyncStream<WorkoutSessionUpdate>
    /// The event of every call made, whatever came of it.
    var asked: [WorkoutEvent] = []
    /// The events the store must hold: those of the calls that returned.
    var kept: [(event: WorkoutEvent, step: Int)] = []
    var stepIndex = 0
    /// The events the store must not hold: ignored ones, and those of calls refused while no store failed.
    var unwanted: [WorkoutEvent] = []
    /// The workout as it stood before an end whose call threw on a store fault: the protocol lets the host go
    /// on showing it until a later `apply`, `finish`, `discard` or recovery has completed the end, even when
    /// the store did what was asked and only its answer was lost.
    var waiting: WorkoutState?
    private(set) var trace: [String] = []

    init(seed: UInt64, backing: SiegeRig.Backing, sabotage: SiegeSabotage? = nil, linked: Bool = false) async throws {
        rig = try await SiegeRig.make(backing, yields: Int(seed % 3), sabotage: sabotage, linked: linked)
        writer = SiegeScriptWriter(seed: seed)
        host = await rig.host()
        stream = await host.updates()
    }

    /// `nil` when the host kept every rule through the script of `seed`, else the first it broke, with the
    /// steps that led there.
    static func violation(
        seed: UInt64,
        backing: SiegeRig.Backing,
        steps: Int = 70,
        linked: Bool = false
    ) async throws -> String? {
        try await run(seed: seed, backing: backing, steps: steps, linked: linked).issue
    }

    /// What a siege found, and what it put the host through.
    struct Report: Sendable {
        var issue: String?
        var faults = 0
        var envelopes = 0
        var saves = 0
        var drops = 0
    }

    static func run(
        seed: UInt64,
        backing: SiegeRig.Backing,
        steps: Int = 70,
        sabotage: SiegeSabotage? = nil,
        linked: Bool = false
    ) async throws -> Report {
        var trial = try await SiegeTrial(seed: seed, backing: backing, sabotage: sabotage, linked: linked)
        var issue: String?
        for index in 0 ..< steps where issue == nil {
            issue = try await trial.step(index)
        }
        if issue == nil {
            issue = try await trial.closing().map { "at the end: \($0)" }
        }
        let siege = trial.rig.siege
        return await Report(
            issue: issue.map { "\($0)\n  after: \(trial.trace.suffix(14).joined(separator: "\n         "))" },
            faults: siege.fired,
            envelopes: siege.stored.count,
            saves: siege.saved.count,
            drops: siege.dropped.count
        )
    }

    private mutating func step(_ index: Int) async throws -> String? {
        let before = try await rig.truth()
        guard before.live.count <= 1 else {
            return "the store holds \(before.live.count) live logs"
        }
        let next = writer.next(live: before.live.first)
        stepIndex = index
        trace.append("\(index): \(next)")
        var issue: String?
        switch next {
        case let .fault(after, fault):
            await rig.siege.failCall(numbered: rig.siege.calls.count + after, fault)
        case let .clock(seconds):
            rig.clock.advance(seconds)
        case let .relaunch(recovering):
            issue = await relaunch(recovering: recovering)
        case .recover:
            issue = try await recoverIssue()
        case let .call(call, ignored):
            issue = try await make(call, ignored: ignored, before: before)
        }
        if let found = await revived(issue) {
            return found
        }
        return try await revived(standingIssue())
    }

    /// The process died: the app is launched again, until a launch survives.
    private mutating func revived(_ issue: String?) async -> String? {
        var found = issue
        while await rig.siege.hasDied {
            let later = await relaunch(recovering: Bool.random(using: &writer.random))
            found = found ?? later
        }
        return found
    }

    /// A new host over the same stores. The old one's stream is judged first.
    private mutating func relaunch(recovering: Bool) async -> String? {
        let issue = await streamIssue()
        host = await rig.host()
        waiting = nil
        if recovering {
            // A launch step that fails here met a fault of the script; the closing pass runs one with none.
            _ = try? await host.resumeFromStore()
        }
        stream = await host.updates()
        return issue
    }

    private mutating func recoverIssue() async throws -> String? {
        let fired = await rig.siege.fired
        do {
            let resumed = try await host.resumeFromStore()
            guard await rig.siege.fired == fired else {
                return nil
            }
            waiting = nil
            let live = try await rig.truth().live.first
            return resumed == live ? nil : "resumeFromStore() did not return the stored live workout"
        } catch {
            return await rig.siege.fired == fired ? "resumeFromStore() threw \(error) though no store failed" : nil
        }
    }

    private mutating func make(_ call: SeamCall, ignored: Bool, before: SiegeRig.Truth) async throws -> String? {
        let fired = await rig.siege.fired
        let outcome = await Seam.outcome(of: call, on: host)
        let faulted = await rig.siege.fired != fired
        asked.append(call.event)
        if let issue = try await answerIssue(call, outcome, ignored: ignored, faulted: faulted, before: before) {
            return "\(call): \(issue)"
        }
        let wasWaiting = waiting != nil
        noteEnd(call, outcome, faulted: faulted, before: before)
        guard !faulted, before.ended.isEmpty, !wasWaiting else {
            return nil
        }
        var oracle = SeamOracle(live: before.live.first)
        let expected = oracle.perform(call).outcome
        return outcome == expected ? nil : "\(call): \(outcome), but on the stored log the rules say \(expected)"
    }
}

// MARK: - What a call's answer commits the host to

extension SiegeTrial {
    /// An end that threw on a store fault may wait; a later call that changes the workout, made while no
    /// store call fails, has completed it.
    mutating func noteEnd(_ call: SeamCall, _ outcome: SeamOutcome, faulted: Bool, before: SiegeRig.Truth) {
        let returned = outcome == .returned || outcome.state != nil
        if faulted, !returned, call.event.isTerminal, let live = before.live.first {
            waiting = live
        } else if !faulted, call.event.isTerminal || call.isApply {
            waiting = nil
        }
    }

    mutating func answerIssue(
        _ call: SeamCall,
        _ outcome: SeamOutcome,
        ignored: Bool,
        faulted: Bool,
        before: SiegeRig.Truth
    ) async throws -> String? {
        switch outcome {
        case .refused:
            if !faulted {
                unwanted.append(call.event)
            }
            return nil
        case let .threw(error):
            return faulted ? nil : "threw \(error) though no store call failed"
        case .returned, .state:
            break
        }
        if ignored {
            unwanted.append(call.event)
            return nil
        }
        return try await keptIssue(call, outcome, before: before)
    }

    /// A call that returned and was not ignored: its event is kept, and its end is complete.
    mutating func keptIssue(_ call: SeamCall, _ outcome: SeamOutcome, before: SiegeRig.Truth) async throws -> String? {
        let ending = before.live.first.map { [$0] }
            ?? before.ended.filter { $0.phase == .discarded } + [waiting].compactMap(\.self)
        switch call {
        case let .finish(endedAt):
            return try await finishIssue(outcome.state, asked: endedAt)
        case let .apply(event) where event.isTerminal && !event.isDiscard:
            kept.append((event, stepIndex))
            return try await finishIssue(outcome.state, asked: nil)
        case .discard:
            if before.ended.isEmpty, waiting == nil {
                kept.append((call.event, stepIndex))
            }
            return try await discardIssue(ending)
        case let .apply(event) where event.isDiscard:
            kept.append((event, stepIndex))
            return try await discardIssue(ending)
        case .start, .apply:
            kept.append((call.event, stepIndex))
            return nil
        }
    }

    /// `finish` returned: the workout is in history now, as the engine replays it, and its log is dropped.
    /// A retry returns the end the first call stored, so the event that must be in the log is the returned
    /// state's.
    mutating func finishIssue(_ returned: WorkoutState?, asked: Date?) async throws -> String? {
        guard let returned, returned.phase == .finished, let endedAt = returned.endedAt else {
            return "returned a workout that is not finished"
        }
        kept.append((.finished(endedAt: endedAt), stepIndex))
        if let asked, asked != endedAt {
            unwanted.append(.finished(endedAt: asked))
        }
        let history = try await rig.history().filter { $0.id == returned.id }
        guard try await history == [rig.asStored(returned)].compactMap(\.self) else {
            return "returned, and history does not hold the finished workout as it was returned"
        }
        return try await rig.uncompacted().contains(returned.id) ? "returned with its log not compacted" : nil
    }

    /// `discard` returned: nothing of the workout it ended (the live one, or one whose discard waited) is in
    /// history, and its log is dropped.
    func discardIssue(_ candidates: [WorkoutState]) async throws -> String? {
        let history = try await Set(rig.history().map(\.id))
        let logs = try await rig.uncompacted()
        guard !candidates.isEmpty else {
            return "returned with no workout to discard"
        }
        if candidates.contains(where: { !history.contains($0.id) && !logs.contains($0.id) }) {
            return nil
        }
        return "returned, and the discarded workout is in history or its log is not compacted"
    }
}
