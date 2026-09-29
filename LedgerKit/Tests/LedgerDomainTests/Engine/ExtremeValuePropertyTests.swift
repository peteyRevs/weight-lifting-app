import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// Fix round 2, orchestrator decision A: decodable envelopes carrying extreme doubles (±1e308, ±1e21,
/// ±∞, NaN) in every date, and extreme `Duration`s. They go through a binary property list, which,
/// unlike JSON, carries non-finite dates. Nothing traps, a replayed state equals itself, and every
/// public computed property of the result can be read at an extreme `now`.
@Suite("WorkoutEngine · extreme values (decision A)", .tags(.domain, .property))
struct ExtremeValuePropertyTests {
    static let extremes: [Double] = [1e308, -1e308, 1e21, -1e21, .infinity, -.infinity, .nan]

    /// The `now`s every computed property is read at.
    static let nows = extremes.map(Date.init(timeIntervalSinceReferenceDate:)) + [
        .distantPast,
        .distantFuture,
        engineTime(0)
    ]

    static let durations: [Duration] = [
        .zero,
        .seconds(30),
        WorkoutEngine.longestRest,
        .seconds(-30),
        .seconds(Int64.max),
        Duration(attoseconds: .max),
        Duration(attoseconds: .min)
    ]

    /// Half the time an extreme, otherwise a realistic time near the fixture, so well-formed envelopes
    /// mix with malformed ones.
    static func date(using generator: inout SeededGenerator) -> Date {
        guard generator.chance(50), let extreme = extremes.randomElement(using: &generator) else {
            return engineTime(Double(Int.random(in: -60 ... 600, using: &generator)))
        }
        return Date(timeIntervalSinceReferenceDate: extreme)
    }

    static func duration(using generator: inout SeededGenerator) -> Duration {
        durations.randomElement(using: &generator) ?? .zero
    }

    /// A seed session whose dates and rest may be extreme.
    static func snapshot(using generator: inout SeededGenerator) -> WorkoutState {
        var snapshot = EventBuilders.seedSession()
        if generator.chance(40) {
            snapshot.startedAt = date(using: &generator)
        }
        if generator.chance(30) {
            snapshot.rest = RestTimer(endsAt: date(using: &generator), total: duration(using: &generator))
        }
        if generator.chance(20) {
            snapshot.exercises[0].sets[0].doneAt = date(using: &generator)
        }
        return snapshot
    }

    static func event(using generator: inout SeededGenerator) -> WorkoutEvent {
        let (date, amount) = (date(using: &generator), duration(using: &generator))
        switch Int.random(in: 0 ..< 8, using: &generator) {
        case 0:
            return .started(snapshot(using: &generator))
        case 1:
            let exercise = Int.random(in: 0 ..< 5, using: &generator)
            return Engine.logged(exercise, 0, at: date.timeIntervalSince(EventBuilders.start))
        case 2:
            let set = LoggedSet(
                id: SetID(generator.uuid()),
                weight: .pounds(60),
                reps: .one,
                kind: .added,
                doneAt: date
            )
            return .setAdded(exerciseIndex: 1, set: set)
        case 3:
            return .restStarted(endsAt: date, total: amount)
        case 4:
            return .restExtended(amount: amount, extendsShownRest: generator.chance(50), tappedAt: date)
        case 5:
            return .restSkipped
        case 6:
            return .finished(endedAt: date)
        default:
            return .discarded(endedAt: date)
        }
    }

    /// A `started` then 1–40 envelopes from two devices, with unique keys and extreme or realistic stamps.
    static func log(_ seed: PropertySeed) -> [EventEnvelope] {
        var generator = seed.generator
        var seqs: [DeviceID: UInt64] = [:]
        var log: [EventEnvelope] = []
        for index in 0 ... Int.random(in: 1 ... 40, using: &generator) {
            let device = generator.chance(50) ? Engine.phone : Engine.watch
            seqs[device, default: 0] += 1
            let event = index == 0 ? .started(snapshot(using: &generator)) : event(using: &generator)
            let stamp = generator.chance(70) ? engineTime(Double(index * 10)) : date(using: &generator)
            log.append(EventBuilders.envelope(event, device: device, seq: seqs[device, default: 0], at: stamp))
        }
        return log
    }

    /// `log` after a binary property list round-trip: what a store or a peer could hand the engine.
    static func decoded(_ log: [EventEnvelope]) throws -> [EventEnvelope] {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try PropertyListDecoder().decode([EventEnvelope].self, from: encoder.encode(log))
    }

    /// Reads every public computed property of `state` and its rest at every extreme `now`.
    static func readEverything(_ state: WorkoutState) {
        for now in nows {
            _ = state.elapsed(at: now)
            _ = state.rest?.remaining(at: now)
            _ = state.rest?.fraction(at: now)
        }
        _ = (state.doneSets, state.totalSets, state.volume)
        _ = WorkoutEngine.summary(state, prs: [])
        _ = (WorkoutEngine.effects(from: nil, to: state), WorkoutEngine.effects(from: state, to: nil))
    }

    @Test(
        "Extreme decodable envelopes never trap; replay equals itself, its shuffle and the oracle",
        arguments: PropertySeed.all
    )
    func extremeValues_neverTrap_andStateEqualsItself(seed: PropertySeed) throws {
        let log = try Self.decoded(Self.log(seed))
        var generator = seed.generator
        let replayed = WorkoutEngine.replay(log)
        #expect(replayed == WorkoutEngine.replay(log), "replay(log) != replay(log)")
        #expect(replayed == WorkoutEngine.replay(log.shuffled(using: &generator)))
        #expect(replayed == ModelOracle.replay(log))
        var state: WorkoutState?
        for envelope in log {
            let (next, _) = WorkoutEngine.reduce(state, envelope)
            _ = WorkoutEngine.effects(from: state, to: next)
            state = next
        }
        for final in [replayed, state].compactMap(\.self) {
            #expect(final == final, "a folded state is not equal to itself")
            Self.readEverything(final)
        }
    }
}
