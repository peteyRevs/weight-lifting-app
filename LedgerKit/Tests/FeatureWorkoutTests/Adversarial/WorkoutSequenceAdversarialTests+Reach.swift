@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

extension WorkoutSequenceAdversarialTests {
    /// The sequences are worth their name only if they reach the states the table is about. Over the fixed
    /// seeds, on the fake, each of these is reached at least once.
    @Test("The seeded sequences reach every state they are meant to attack")
    func sequences_reachEveryState() async throws {
        var reached: Set<String> = []
        for seed in Self.seeds {
            try await AdversarialWorld.run(.fake) { world in
                var generator = SplitMix64(seed: seed)
                let rig = AdversarialRig()
                for index in 0 ..< Self.steps {
                    let step = Step.random(using: &generator)
                    _ = await Self.injectFault(in: world, using: &generator)
                    let before = try await world.live()
                    let routes = rig.routes.count
                    try await step.perform(on: rig, in: world, tick: index)
                    await world.session.heal()
                    await world.launcherStores.heal()
                    let after = try await world.live()
                    await rig.absorb(after)
                    reached.formUnion(Self.marks(
                        step,
                        before: before,
                        after: after,
                        rig: rig,
                        newRoute: rig.routes.count > routes
                    ))
                }
            }
        }
        let wanted: Set = [
            "conflict", "replaced", "replace failed, kept", "replace failed, gone", "start failed", "cover",
            "discarded by the lifter", "discard refused", "ended elsewhere under the cover", "minimized",
            "resumed from the conflict"
        ]
        let missing = wanted.subtracting(reached).sorted()
        #expect(missing.isEmpty, "never reached: \(missing)")
    }

    private static func marks(
        _ step: Step,
        before: WorkoutState?,
        after: WorkoutState?,
        rig: AdversarialRig,
        newRoute: Bool
    ) -> Set<String> {
        var marks = phaseMarks(rig)
        guard let before else {
            return marks
        }
        switch step {
        case .replace where after != nil && after?.id != before.id: marks.insert("replaced")
        case .resumeIt where rig.phase == .cover: marks.insert("resumed from the conflict")
        case .discard where after == nil: marks.insert("discarded by the lifter")
        case .finishedElsewhere where newRoute, .discardedElsewhere where newRoute:
            marks.insert("ended elsewhere under the cover")
        case .minimize where newRoute: marks.insert("minimized")
        default: break
        }
        return marks
    }

    private static func phaseMarks(_ rig: AdversarialRig) -> Set<String> {
        var marks: Set<String> = rig.store?.dialog == .discardFailed ? ["discard refused"] : []
        switch rig.phase {
        case .conflict: marks.insert("conflict")
        case .cover: marks.insert("cover")
        case .failed(.notReplaced(.liveKept)): marks.insert("replace failed, kept")
        case .failed(.notReplaced(.nothingLive)): marks.insert("replace failed, gone")
        case .failed(.notStarted): marks.insert("start failed")
        default: break
        }
        return marks
    }
}
