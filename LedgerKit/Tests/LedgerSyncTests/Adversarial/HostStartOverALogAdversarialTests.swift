import Foundation
import LedgerDomain
import LedgerSync
import LedgerTestSupport
import Testing

/// F10 S2 adversarial round 1, criterion 2 on `start`: "An event is stamped with `seq` = the highest stored
/// for this workout and device + 1". A start is given a workout id; here the store already holds envelopes
/// under that id (a log that replays to nothing is kept, criterion 6). `StartWorkoutUseCase` draws a new id
/// for every workout, so only a caller that passes an id twice reaches this.
@Suite("Adversarial F10 S2 · a start under an id whose log is kept", .tags(.sync), .timeLimit(.minutes(1)))
struct HostStartOverALogAdversarialTests {
    typealias Backing = SiegeRig.Backing

    /// What a killed app could not have left by itself, and a damaged or half-synced store can: workout 1's
    /// second and third envelopes without its `started`.
    static let orphans = Array(SiegeLogs.log(1, SiegeLogs.twoSets(in: 1)).dropFirst())

    /// Expected: after any call that returns, the host's workout is what its store replays to (the host's own
    /// documentation: "Memory follows the store"). Either the start takes the next free `seq` and the workout
    /// is the log's, or the start is refused.
    @Test(
        "A start under such an id leaves the host's workout equal to what the store replays",
        arguments: Backing.allCases
    )
    func start_overAKeptLog_memoryFollowsTheStore(backing: Backing) async throws {
        let rig = try await SiegeLogs.rig(backing, [Self.orphans])
        let host = await rig.host()
        #expect(try await host.resumeFromStore() == nil)
        let outcome = await Seam.outcome(of: .start(Seam.session(1)), on: host)
        let current = try await host.current()
        let replayed = try await rig.replayed(Seam.workout(1))
        #expect(
            current == replayed,
            "start \(outcome); the host shows \(SiegeTrialBrief.of(current)), the log \(SiegeTrialBrief.of(replayed))"
        )
        let seqs = try await rig.log(Seam.workout(1)).map(\.seq).sorted()
        #expect(seqs == Array(Set(seqs)).sorted(), "each seq once")
    }

    @Test("And the next event is stored, not refused as a seq that is taken", arguments: Backing.allCases)
    func apply_afterAStartOverAKeptLog_isStored(backing: Backing) async throws {
        let rig = try await SiegeLogs.rig(backing, [Self.orphans])
        let host = await rig.host()
        guard await Seam.outcome(of: .start(Seam.session(1)), on: host) == .returned else {
            return
        }
        let event = Seam.logged(1, 0, in: 1, at: 900)
        let outcome = await Seam.outcome(of: .apply(event), on: host)
        #expect(outcome.state != nil, "\(outcome)")
        #expect(try await rig.log(Seam.workout(1)).contains { $0.event == event })
    }
}

enum SiegeTrialBrief {
    static func of(_ state: WorkoutState?) -> String {
        state.map { Seam.brief(WorkoutSessionUpdate(state: $0)) } ?? "no workout"
    }
}
