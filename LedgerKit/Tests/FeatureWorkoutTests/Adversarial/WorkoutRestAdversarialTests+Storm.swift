import Dependencies
@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S6 criterion 5: "+30s" and "Skip rest" through the one tap queue. S5's seeded storm (calls
/// that wait, taps that arrive meanwhile, a page behind the answers) with the two new taps among the
/// others, and a date that moves up to 40 s at each reading, so that rests are met running and over.
extension WorkoutRestAdversarialTests {
    typealias Pump = WorkoutPumpAdversarialTests

    /// S5's taps of every kind, with one in three replaced by a tap on the panel: "+30s" twice as often
    /// as "Skip rest".
    static func tapsWithRest(seed: UInt64, in running: WorkoutState, count: Int = 48) -> [WorkoutEdit] {
        var generator = SplitMix64(seed: seed ^ 0x5E57)
        return Pump.taps(seed: seed, in: running, count: count).map { tap in
            switch Int.random(in: 0 ..< 9, using: &generator) {
            case 0, 1: .extendRest
            case 2: .skipRest
            default: tap
            }
        }
    }

    /// Up to 40 s between two readings of the date.
    nonisolated static let stormSteps = 0.0 ... 40.0

    /// What the calm run came to, and the first tap on the panel that sent something other than the
    /// engine's one event for what the lifter saw.
    struct Calm {
        var outcome: Pump.Outcome
        var fault: String?
        var extended = (running: 0, over: 0)
        var skipped = 0
        var nothing = 0
        var logged = 0
        var unlogged = (held: 0, applied: 0)

        /// The events the brief owes a tap on the panel, counted by case.
        mutating func owed(for tap: WorkoutEdit, showing shown: RestTimer?, readAt read: Date) -> [WorkoutEvent] {
            guard let shown else {
                nothing += 1
                return []
            }
            guard tap == .extendRest else {
                skipped += 1
                return [.restSkipped]
            }
            let isRunning = shown.remaining(at: read) > .zero
            extended.running += isRunning ? 1 : 0
            extended.over += isRunning ? 0 : 1
            return [.restExtended(amount: .seconds(30), extendsShownRest: isRunning, tappedAt: read)]
        }
    }

    /// Each tap made, applied and shown before the next. For a tap on the panel the events it sent are
    /// compared with what the brief owes: from the session's workout before the tap and the one reading of
    /// the date the tap is allowed, "+30s" is one `restExtended` of 30 s that says whether the rest was
    /// still running at that reading; "Skip rest" one `restSkipped`; with no rest shown, nothing.
    static func calm(_ taps: [WorkoutEdit], seed: UInt64) async throws -> Calm {
        let bench = try await PumpBench.make(ticking: seed, by: stormSteps)
        var calm = Calm(outcome: Pump.Outcome(applied: [], final: nil, selection: nil))
        for (index, tap) in taps.enumerated() {
            let before = await bench.session.current()
            let sent = await bench.session.applied.count
            bench.tap(tap)
            await bench.store.drain()
            await bench.settled()
            // One reading of the date for a tap, and it is the moment the panel is then drawn at.
            if bench.store.moment != bench.clock.value, calm.fault == nil {
                calm.fault = "tap \(index), \(tap): the date was read again after the tap's moment"
            }
            guard tap == .extendRest || tap == .skipRest else {
                continue
            }
            let events = await Array(bench.session.applied.dropFirst(sent))
            let owed = calm.owed(for: tap, showing: before?.shownRest, readAt: bench.clock.value)
            if events != owed, calm.fault == nil {
                calm.fault = "tap \(index), \(tap): sent \(events), owed \(owed)"
            }
        }
        bench.following.cancel()
        return await Calm(
            outcome: Pump.Outcome(
                applied: bench.session.applied, final: bench.session.current(), selection: bench.store.selection
            ),
            fault: calm.fault, extended: calm.extended, skipped: calm.skipped, nothing: calm.nothing
        )
    }

    @Test(
        "+30s and Skip rest among the page's taps, in a storm: the engine's one event each, in order, each once",
        arguments: RestSeeds.all
    )
    func storm_withThePanelsTaps(seed: UInt64) async throws {
        let taps = Self.tapsWithRest(seed: seed, in: EventBuilders.seedSession())
        let calm = try await Self.calm(taps, seed: seed)
        #expect(calm.fault == nil, "seed \(seed)")
        let storm = try await Pump.inAStorm(taps, seed: seed, by: Self.stormSteps)
        let firstDifference = zip(calm.outcome.applied, storm.applied).enumerated()
            .first { $0.element.0 != $0.element.1 }?.offset
        #expect(firstDifference == nil, "seed \(seed): the events differ from number \(firstDifference ?? -1) on")
        #expect(calm.outcome.applied.count == storm.applied.count, "seed \(seed)")
        let isSameWorkout = unchanged(storm.final, calm.outcome.final)
        #expect(isSameWorkout, "seed \(seed)")
        #expect(calm.outcome.selection == storm.selection, "seed \(seed)")
    }

    @Test("The storm's taps on the panel meet every case: a rest running, a rest over, and no rest at all")
    func storm_isNotVacuous() async throws {
        var (running, over, skipped, nothing) = (0, 0, 0, 0)
        for seed in RestSeeds.all.prefix(40) {
            let calm = try await Self.calm(Self.tapsWithRest(seed: seed, in: EventBuilders.seedSession()), seed: seed)
            running += calm.extended.running
            over += calm.extended.over
            skipped += calm.skipped
            nothing += calm.nothing
        }
        // The first 40 seeds give 179, 31, 95 and 317.
        #expect(running >= 80)
        #expect(over >= 15)
        #expect(skipped >= 40)
        #expect(nothing >= 80)
    }
}
