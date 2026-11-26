import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing
@testable import WatchFeatureWorkout

/// F18's mode rule (spec §4.2, §4.5 resolved): summary, idle, rest, the 1.2 s "GO", and ready.
@Suite("WatchMode", .tags(.watch))
nonisolated struct WatchModeTests {
    static let now = Fixtures.now

    static func resting(endsIn seconds: TimeInterval, total: Duration = .seconds(90)) throws -> WorkoutState {
        var state = try WatchSample.session()
        state.rest = RestTimer(endsAt: now.addingTimeInterval(seconds), total: total)
        return state
    }

    @Test("Idle without a live workout, ready, rest before the end, GO at it, summary until dismissed")
    func test_mode_idleReadyRestGoSummary() throws {
        let live = try WatchSample.session()
        var finished = live
        finished.phase = .finished
        finished.endedAt = Self.now
        var discarded = live
        discarded.phase = .discarded
        #expect(WatchMode(nil, at: Self.now, summaryDismissed: false) == .idle)
        #expect(WatchMode(discarded, at: Self.now, summaryDismissed: false) == .idle)
        #expect(WatchMode(finished, at: Self.now, summaryDismissed: false) == .summary)
        #expect(WatchMode(finished, at: Self.now, summaryDismissed: true) == .idle)
        #expect(WatchMode(live, at: Self.now, summaryDismissed: false) == .ready)
        let resting = try Self.resting(endsIn: 45)
        let rest = try #require(resting.rest)
        #expect(WatchMode(resting, at: Self.now, summaryDismissed: false) == .rest(rest))
        #expect(WatchMode(resting, at: rest.endsAt, summaryDismissed: false) == .restOver(rest))
        #expect(WatchMode(resting, at: rest.endsAt.addingTimeInterval(5), summaryDismissed: false) == .ready)
        // A set logged once the rest had ended, with no rest of its own: the ended rest is not shown, so no GO.
        var loggedAfter = resting
        loggedAfter.exercises[0].sets[0].doneAt = rest.endsAt
        #expect(WatchMode(loggedAfter, at: rest.endsAt, summaryDismissed: false) == .ready)
        #expect(WatchMode.restOver(rest).isLive && WatchMode.rest(rest).isLive && WatchMode.ready.isLive)
        #expect(!WatchMode.idle.isLive && !WatchMode.summary.isLive, "the overlays open only over a live workout")
    }

    @Test("GO lasts exactly 1.2 s from endsAt: GO at endsAt and just before 1.2 s, ready at 1.2 s")
    func test_mode_goWindowIs1200ms() throws {
        #expect(WatchMode.goWindow == .milliseconds(1200))
        let state = try Self.resting(endsIn: 30)
        let rest = try #require(state.rest)
        let mode = { (offset: TimeInterval) in WatchMode(
            state,
            at: rest.endsAt.addingTimeInterval(offset),
            summaryDismissed: false
        ) }
        #expect(mode(-0.001) == .rest(rest))
        #expect(mode(0) == .restOver(rest))
        #expect(mode(1.199) == .restOver(rest))
        #expect(mode(1.2) == .ready)
    }

    // MARK: Property

    /// The seeds a PR run and `swift test` take.
    static let fixedSeeds: [UInt64] = (0 ..< 12).map(seed)

    /// In the nightly lane, `LEDGER_PROPERTY_SEED_COUNT` seeds up to `nightlySeedCount`, never fewer than the fixed
    /// ones; the fixed seeds elsewhere (the pattern of `LiveSyncPropertyTests`).
    static let seeds: [UInt64] = {
        let configured = ProcessInfo.processInfo.environment["LEDGER_PROPERTY_SEED_COUNT"].flatMap(Int.init) ?? 0
        let count = min(configured, nightlySeedCount)
        return TestLane.isNightly && count > fixedSeeds.count ? (0 ..< count).map(seed) : fixedSeeds
    }()

    static let nightlySeedCount = 2000

    static func seed(_ number: Int) -> UInt64 {
        UInt64(number) &* 104_729 &+ 31
    }

    /// Where a moment stands against a rest's end, and the mode it must give.
    enum Place: CaseIterable {
        case before, atEnd, inGo, atGoEnd, after
    }

    @Test(
        "Every (now, endsAt, total) gives the mode its place gives, with exact edges at endsAt and endsAt + 1.2 s",
        .tags(.property),
        arguments: seeds
    )
    func mode_partitionsTime(seed: UInt64) throws {
        var random = SplitMix64(seed: seed)
        let base = try WatchSample.session()
        for _ in 0 ..< 200 {
            let endsAt = Self.now.addingTimeInterval(.random(in: -1e6 ... 1e6, using: &random))
            let total = Duration.milliseconds(Int64.random(in: 0 ... 600_000, using: &random))
            var state = base
            state.rest = RestTimer(endsAt: endsAt, total: total)
            let rest = try #require(state.rest)
            let place = try #require(Place.allCases.randomElement(using: &random))
            let moment = switch place {
            case .before: endsAt.addingTimeInterval(-.random(in: 0.001 ... 600, using: &random))
            case .atEnd: endsAt
            case .inGo: endsAt.addingTimeInterval(.random(in: 0.001 ... 1.199, using: &random))
            case .atGoEnd: endsAt.addingTimeInterval(1.2)
            case .after: endsAt.addingTimeInterval(.random(in: 1.201 ... 600, using: &random))
            }
            let expected: WatchMode = switch place {
            case .before: .rest(rest)
            case .atEnd, .inGo: .restOver(rest)
            case .atGoEnd, .after: .ready
            }
            let mode = WatchMode(state, at: moment, summaryDismissed: false)
            #expect(mode == expected, "seed \(seed), \(place), total \(total)")
            let shown = WatchPresentation.rest(state, mode: mode, at: moment, WatchSample.live())
            #expect(
                (shown != nil) == (place != .atGoEnd && place != .after),
                "seed \(seed): a rest screen only at rest"
            )
            if let offset = shown?.ringOffset {
                #expect((0 ... WatchPresentation.ringLength).contains(offset), "seed \(seed): ring \(offset)")
            }
        }
    }
}
