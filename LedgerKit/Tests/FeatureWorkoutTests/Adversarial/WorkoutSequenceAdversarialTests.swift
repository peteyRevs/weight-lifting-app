@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S4: "never two, never lost". Seeded sequences of launcher requests, dialog answers, taps on the
/// cover and changes by another hand, with a fault on a session or store call before some steps. After
/// every step: the launcher is at rest, the cover shows the live workout or nothing, a workout is gone
/// only when the lifter discarded it or another hand ended it, and a new one came only from a start.
@MainActor
@Suite("Workout sequences (adversarial)", .tags(.feature), .timeLimit(.minutes(2)))
struct WorkoutSequenceAdversarialTests {
    typealias World = AdversarialWorld
    typealias Step = AdversarialStep

    nonisolated static let seeds: [UInt64] = Array(1 ... 40)
    static let steps = 40

    @Test(
        "Seeded sequences with faults: never two, never lost, never a stale cover",
        arguments: World.Kind.allCases,
        seeds
    )
    func sequences_keepTheInvariants(kind: World.Kind, seed: UInt64) async throws {
        try await World.run(kind) { world in
            var generator = SplitMix64(seed: seed)
            let rig = AdversarialRig()
            var trail: [String] = []
            for index in 0 ..< Self.steps {
                let step = Step.random(using: &generator)
                let fault = await Self.injectFault(in: world, using: &generator)
                let before = try await world.live()
                let startsBefore = await world.session.count(.start)
                try await step.perform(on: rig, in: world, tick: index)
                await world.session.heal()
                await world.launcherStores.heal()
                let after = try await world.live()
                await rig.absorb(after)
                trail.append("\(step)\(fault)")
                let started = await world.session.count(.start) - startsBefore
                let tooMany = started > (step.mayStart ? 1 : 0) ? "\(started) starts" : nil
                if let failure = Self.broken(step, before: before, after: after, rig: rig) ?? tooMany {
                    Issue
                        .record(
                            "\(kind) seed \(seed), step \(index): \(failure). Trail: \(trail.joined(separator: ", "))"
                        )
                    return
                }
            }
        }
    }

    /// Before about one step in two, the next call of one kind fails: before it reaches the client, or
    /// after it did its work.
    static func injectFault(in world: World, using generator: inout SplitMix64) async -> String {
        switch Int.random(in: 0 ..< 12, using: &generator) {
        case 0:
            await world.session.fail(.start)
            return " [start fails]"
        case 1:
            await world.session.fail(.start, afterwards: true)
            return " [start's answer lost]"
        case 2:
            await world.session.fail(.discard)
            return " [discard fails]"
        case 3:
            await world.session.fail(.discard, afterwards: true)
            return " [discard's answer lost]"
        case 4:
            await world.session.fail(.current)
            return " [current fails]"
        case 5:
            await world.launcherStores.fail(.activeProgram)
            return " [program store fails]"
        default:
            return ""
        }
    }

    /// What `step` broke, or nil.
    private static func broken(
        _ step: Step,
        before: WorkoutState?,
        after: WorkoutState?,
        rig: AdversarialRig
    ) -> String? {
        if rig.phase == .working {
            return "the launcher is still working"
        }
        if let before, after?.id != before.id, !step.mayEnd {
            return "the live workout is gone, and the lifter did not discard it"
        }
        if let after, after.id != before?.id, !step.mayStart {
            return "a workout appeared without a start"
        }
        return staleCover(rig, live: after)
    }

    /// The cover shows the live workout as it is, or it is down and nothing of it is left.
    private static func staleCover(_ rig: AdversarialRig, live: WorkoutState?) -> String? {
        guard rig.phase == .cover else {
            return rig.store == nil ? nil : "a cover's store outlived its cover"
        }
        guard let live else {
            return "the cover is up with nothing live"
        }
        guard rig.shown?.id == live.id else {
            return "the cover shows \(String(describing: rig.shown?.id)) and \(live.id) is live"
        }
        return rig.shown == live ? nil : "the cover shows the live workout as it was, not as it is"
    }
}
