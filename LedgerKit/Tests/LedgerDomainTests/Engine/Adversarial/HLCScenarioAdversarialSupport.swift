import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// A seeded multi-device session for the round-2 HLC properties: 2–3 `SimHost`s whose clocks are skewed
/// by up to ±30 s and step back by up to 30 s, per-link partitions, relaunches, and batched, shuffled,
/// duplicated delivery of each device's own envelopes (F17 sends only its own).
struct HLCScenario {
    /// A lifter action: the envelope, the keys its device held when it was created, and whether that
    /// device's view showed the row the action names.
    struct Action {
        let envelope: EventEnvelope
        let seen: Set<EnvelopeKey>
        let rowSeen: Bool
    }

    private(set) var hosts: [SimHost]
    private(set) var actions: [Action] = []
    /// "+30s" taps whose outcome on their own device was not what the lifter saw (fix round 2, decision
    /// B): a rest shown running that was not extended, or a fresh rest that did not start at the tap.
    private(set) var extendsJudgedOver = 0
    /// "+30s" taps on a rest shown running whose HLC stamp lies at or after that rest's end: the case the
    /// engine used to judge over (finding 14). Counted to show the hazard still arises.
    private(set) var extendsStampedAfterEnd = 0
    private var real: Double = 0
    private var cut: Set<[Int]> = []
    private var sent: [[EventEnvelope]]
    private var delivered: [[Int]]

    init(policy: HostPolicy, using generator: inout SeededGenerator) {
        let devices = [EngineAdv.phone, EngineAdv.watch, EngineAdv.tablet]
        let count = Int.random(in: 2 ... 3, using: &generator)
        hosts = devices.prefix(count).map { device in
            SimHost(device, offset: Double(Int.random(in: -30000 ... 30000, using: &generator)) / 1000, policy: policy)
        }
        sent = Array(repeating: [], count: count)
        delivered = Array(repeating: Array(repeating: 0, count: count), count: count)
    }

    /// Runs one session of `steps` actions after the first host starts it, then heals every link.
    static func run(
        _ policy: HostPolicy,
        seed: PropertySeed,
        steps: Int = 30
    ) async throws -> HLCScenario {
        var generator = seed.generator
        var scenario = HLCScenario(policy: policy, using: &generator)
        let session = EngineGen.session(using: &generator)
        try await scenario.record(.started(session), by: 0)
        try await scenario.deliver(using: &generator)
        for step in 0 ..< steps {
            await scenario.perturb(using: &generator)
            try await scenario.act(late: step >= steps - 3, using: &generator)
            try await scenario.deliver(using: &generator)
        }
        scenario.cut = []
        try await scenario.deliver(using: &generator)
        return scenario
    }

    var everything: [EventEnvelope] {
        sent.flatMap(\.self)
    }

    /// Link failures, clock steps back, relaunches, and real time passing.
    private mutating func perturb(using generator: inout SeededGenerator) async {
        let count = hosts.count
        if generator.chance(25) {
            let pair = [Int.random(in: 0 ..< count, using: &generator), Int.random(in: 0 ..< count, using: &generator)]
            let link = pair.sorted()
            cut = cut.contains(link) ? cut.subtracting([link]) : cut.union([link])
        }
        if generator.chance(5) {
            hosts[Int.random(in: 0 ..< count, using: &generator)].offset -= Double(Int.random(
                in: 1 ... 30,
                using: &generator
            ))
        }
        if generator.chance(4) {
            await hosts[Int.random(in: 0 ..< count, using: &generator)].relaunch()
        }
        real += generator.chance(20) ? 0 : Double(Int.random(in: 1 ... 20, using: &generator))
    }

    /// A random host with a live view acts once (terminals only among the last steps).
    private mutating func act(late: Bool, using generator: inout SeededGenerator) async throws {
        let index = Int.random(in: 0 ..< hosts.count, using: &generator)
        guard let view = hosts[index].state, view.phase == .live else {
            return
        }
        var event = EngineGen.intent(for: view, at: hosts[index].now(real), sharedAddIDs: [], using: &generator)
        for _ in 0 ..< 5 where !late && Self.isTerminal(event) {
            event = EngineGen.intent(for: view, at: hosts[index].now(real), sharedAddIDs: [], using: &generator)
        }
        if Self.isTerminal(event), !late {
            event = .restSkipped
        }
        let envelope = try await record(event, by: index)
        guard case let .restExtended(amount, shown, tappedAt) = event else {
            return
        }
        // What the lifter saw: the shown rest grown by `amount`, else a fresh rest from the tap.
        let seconds = amount / .seconds(1)
        let expected = view.rest.flatMap { rest in
            shown ? RestTimer(endsAt: rest.endsAt.addingTimeInterval(seconds), total: rest.total + amount) : nil
        } ?? RestTimer(endsAt: tappedAt.addingTimeInterval(seconds), total: amount)
        extendsJudgedOver += hosts[index].state?.rest == expected ? 0 : 1
        if shown, let rest = view.rest, rest.endsAt <= envelope.wallClock {
            extendsStampedAfterEnd += 1
        }
    }

    @discardableResult
    private mutating func record(_ event: WorkoutEvent, by index: Int) async throws -> EventEnvelope {
        let seen = await Set(hosts[index].log.map(\.key))
        let rowSeen = Self.doneness(event).map { target in
            hosts[index].state?.exercises.indices.contains(target.exercise) == true
                && hosts[index].state?.exercises[target.exercise].sets.contains { $0.id == target.id } == true
        } ?? false
        let envelope = try await hosts[index].create(event, real: real)
        sent[index].append(envelope)
        actions.append(Action(envelope: envelope, seen: seen, rowSeen: rowSeen))
        return envelope
    }

    /// Every connected pair exchanges what it has not yet sent, shuffled, in one or two batches, with
    /// some envelopes delivered again.
    private mutating func deliver(using generator: inout SeededGenerator) async throws {
        for target in hosts.indices {
            for source in hosts.indices where source != target && !cut.contains([source, target].sorted()) {
                let fresh = Array(sent[source].dropFirst(delivered[target][source]))
                let again = sent[source].prefix(delivered[target][source]).filter { _ in generator.chance(10) }
                guard !fresh.isEmpty else {
                    continue
                }
                let batch = (fresh + again).shuffled(using: &generator)
                let split = Int.random(in: 0 ... batch.count, using: &generator)
                try await hosts[target].receive(Array(batch.prefix(split)))
                try await hosts[target].receive(Array(batch.dropFirst(split)))
                delivered[target][source] = sent[source].count
            }
        }
    }
}

// MARK: - What the lifter did

extension HLCScenario {
    static func isTerminal(_ event: WorkoutEvent) -> Bool {
        switch event {
        case .finished, .discarded:
            true
        default:
            false
        }
    }

    /// The row a log or un-log names, and whether it leaves the set done.
    struct Target {
        let exercise: Int
        let id: SetID
        let done: Bool
    }

    static func doneness(_ event: WorkoutEvent) -> Target? {
        switch event {
        case let .setLogged(exercise, id, _, _, _):
            Target(exercise: exercise, id: id, done: true)
        case let .setUnlogged(exercise, id):
            Target(exercise: exercise, id: id, done: false)
        default:
            nil
        }
    }

    /// Logs and un-logs that were the last word on their set: the device that made each had already
    /// seen every other log or un-log of that set, its view showed the row, and it sorts before the
    /// first terminal. Each is the lifter's latest intent for the set and must stand.
    var lastWords: [Action] {
        let firstTerminal = actions.map(\.envelope).filter { Self.isTerminal($0.event) }.min()
        return actions.filter { action in
            guard action.rowSeen, let target = Self.doneness(action.envelope.event),
                  firstTerminal.map({ action.envelope < $0 }) ?? true
            else {
                return false
            }
            return actions.allSatisfy { other in
                other.envelope.key == action.envelope.key || Self.doneness(other.envelope.event)?.id != target.id
                    || action.seen.contains(other.envelope.key)
            }
        }
    }

    /// The keys of `lastWords` that `final` contradicts.
    func lostActions(in final: WorkoutState) -> [EnvelopeKey] {
        lastWords.compactMap { action in
            guard let target = Self.doneness(action.envelope.event) else {
                return nil
            }
            let row = final.exercises.flatMap(\.sets).first { $0.id == target.id }
            return row?.isDone == target.done ? nil : action.envelope.key
        }
    }
}
