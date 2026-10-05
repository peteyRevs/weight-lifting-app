import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 adversarial round 1, criterion 11: does the contract's script of calls made at once reject a racy
/// host? `RacyHost` is the real host, over stores that give way inside every call, with one fault that
/// strikes once and only when two calls are inside it. The gate runs twenty fixed seeds against a faulty
/// client (`WorkoutSessionConcurrentScriptTests`) and asks that one of them report it.
@Suite("Adversarial F10 S2 · does the concurrent script bite", .tags(.sync), .timeLimit(.minutes(1)))
struct HostContractBiteAdversarialTests {
    typealias Contract = WorkoutSessionClientContract

    /// The twenty seeds the gate runs, and sixty more.
    static let gateSeeds: [UInt64] = (0 ..< 20).map { UInt64($0) &* 7919 &+ 17 }
    static let moreSeeds: [UInt64] = (20 ..< 80).map { UInt64($0) &* 7919 &+ 17 }

    /// What `seeds` make of a racy host: in how many runs its fault struck, in how many of those the script
    /// reported something, and in how many it reported something although the fault had not struck.
    struct Tally: CustomStringConvertible {
        var runs = 0
        var struck = 0
        var reported = 0
        var falseAlarms: [String] = []
        /// The runs in which the fault struck and nothing was reported: the seed, and where it struck.
        var missed: [String] = []

        var description: String {
            "struck in \(struck) of \(runs) runs, reported in \(reported) of those; missed: \(missed)"
        }
    }

    static func tally(
        _ fault: RacyFault?,
        on streams: RacyHost.Streams,
        seeds: [UInt64]
    ) async throws -> Tally {
        var tally = Tally()
        for seed in seeds {
            let rig = try await SiegeRig.make(.memory, yields: 2)
            let racy = await RacyHost(rig.host(), fault, on: streams)
            let issue = try await Contract.concurrentScriptViolation(seed: seed, on: racy)
            let struck = await racy.strikes > 0
            tally.runs += 1
            tally.struck += struck ? 1 : 0
            tally.reported += struck && issue != nil ? 1 : 0
            if !struck, let issue {
                tally.falseAlarms.append("seed \(seed): \(issue)")
            }
            if struck, issue == nil {
                await tally.missed.append("seed \(seed) at \(racy.struckAt)")
            }
        }
        return tally
    }

    /// The script opens its second stream for the subscriber that acts on what it is told.
    static let actingStream = 2

    @Test("A wrapper with no fault passes the script: what it reports of a racy host is the fault")
    func honestWrapper_passesTheScript() async throws {
        let tally = try await Self.tally(nil, on: .all, seeds: Self.gateSeeds + Self.moreSeeds)
        #expect(tally.falseAlarms.isEmpty)
        #expect(tally.struck == 0)
    }

    /// The scheduler decides whether two calls overlap; the script decides whether a wrong history is seen.
    /// This is the script's half, on every stream it reads to the end and on every call: a run in which the
    /// fault struck must be reported. And within the gate's twenty seeds it must strike.
    @Test("Whenever a racy host's fault struck, the script of that seed reports it", arguments: RacyFault.allCases)
    func racyHost_wheneverItStruck_isReported(fault: RacyFault) async throws {
        let streams = RacyHost.Streams.allBut(Self.actingStream)
        let gate = try await Self.tally(fault, on: streams, seeds: Self.gateSeeds)
        #expect(gate.reported > 0, "\(fault), the gate's twenty seeds: \(gate)")
        let more = try await Self.tally(fault, on: streams, seeds: Self.moreSeeds)
        #expect(gate.falseAlarms.isEmpty && more.falseAlarms.isEmpty)
        #expect(gate.missed + more.missed == [], "\(fault): \(gate.struck + more.struck) strikes in 80 runs")
    }

    /// Rule 5 reads the acting subscriber's stream "up to the first that showed a workout" and no further,
    /// so what a host does to that stream afterwards is seen by nothing (finding F10-S2-3). A subscriber that
    /// acts on an update is the workout screen; its stream is the one that plays the haptics.
    @Test("A fault on the stream of the subscriber that acts is reported too", arguments: RacyFault.onAStream)
    func racyHost_faultOnTheActingStream_isReported(fault: RacyFault) async throws {
        let tally = try await Self.tally(fault, on: .only(Self.actingStream), seeds: Self.gateSeeds)
        #expect(tally.struck > 0, "\(fault) never struck")
        #expect(tally.reported == tally.struck, "\(fault): \(tally)")
    }

    @Test("This suite's storm reports a racy host whenever its fault struck", arguments: RacyFault.allCases)
    func storm_wheneverARacyHostStruck_reportsIt(fault: RacyFault) async throws {
        var struck = 0, reported = 0
        for seed in SeamSeed.all.prefix(40) {
            let racy = SiegeBox<RacyHost>()
            let issue = try await SiegeStorm.violation(seed: seed.value, backing: .memory) { host in
                let wrapped = RacyHost(host, fault)
                racy.put(wrapped)
                return wrapped
            }
            guard let host = racy.value, await host.strikes > 0 else {
                continue
            }
            struck += 1
            reported += issue == nil ? 0 : 1
        }
        #expect(struck > 0, "\(fault) never struck")
        #expect(reported == struck, "\(fault): struck in \(struck) storms, reported in \(reported)")
    }

    /// The gate asks that one of twenty fixed seeds report each fault of its stand-in that needs overlap. How
    /// wide is that margin? Which scripts report a fault is mostly the script's doing, not the scheduler's:
    /// a script must hold the calls the fault needs, side by side.
    @Test("Each overlap fault of the gate's stand-in is reported by at least four of its twenty seeds")
    func standInFaults_gateSeeds_areReportedWithAMargin() async throws {
        for fault in FaultyWorkoutSession.Fault.allCases.filter(\.needsOverlap) {
            var reports = 0
            for seed in Self.gateSeeds {
                let issue = try await Contract.concurrentScriptViolation(seed: seed, on: FaultyWorkoutSession(fault))
                reports += issue == nil ? 0 : 1
            }
            #expect(reports >= 4, "\(fault) is reported by \(reports) of twenty seeds")
        }
    }
}
