@testable import FeatureOnboarding
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The root's `.task(id: attempt)` as SwiftUI runs it, made steppable: a new attempt cancels the task and starts
/// one, the view going away cancels it, the view coming back starts one with the attempt it has, and every store
/// call and the retry step wait until the test releases them.
final class SteppedRoot {
    let scene: AdversarialScene
    let stepper = Stepper()
    private var task: Task<Void, Never>?
    private var taskID: OnboardingSaveAttempt?
    private(set) var isVisible = true
    /// What "Start training" and "Skip setup" were tapped for: the only programs that may be stored.
    private(set) var asked: Set<[String]> = []
    /// What the run went through, for the control that the walks reach what they are meant to attack.
    private(set) var coverage: Set<String> = []
    private var hasCancelledWaiter = false

    init(_ scene: AdversarialScene) async {
        self.scene = scene
        scene.settings.script.step(with: stepper)
        scene.exercises.script.step(with: stepper)
        scene.programs.script.step(with: stepper)
        scene.onPrepare = { [stepper] in _ = await stepper.arrive("prepare") }
        start()
        await stepper.settle()
    }

    private func start() {
        task?.cancel()
        taskID = scene.store.attempt
        stepper.taskStarted()
        task = Task { [scene, stepper] in
            await scene.runSave()
            stepper.taskEnded()
        }
    }

    /// A tap, which reaches the store only while the view is there.
    func tap(_ action: OnboardingAction) async {
        guard isVisible else {
            return
        }
        if action == .startTraining {
            asked.insert([scene.store.state.goal.rawValue, "\(scene.store.state.days.rawValue)"])
        } else if action == .skipSetup {
            asked.insert([TrainingGoal.both.rawValue, "4"])
        }
        scene.store.send(action)
        if scene.store.attempt != taskID {
            start()
        }
        await stepper.settle()
    }

    func disappear() async {
        task?.cancel()
        isVisible = false
        hasCancelledWaiter = hasCancelledWaiter || !stepper.waiting.isEmpty
        await stepper.settle()
    }

    func appear() async {
        isVisible = true
        start()
        await stepper.settle()
    }

    /// Lets the oldest waiting call go with `outcome`, and waits until its task waits again or has ended.
    @discardableResult
    func release(_ outcome: CallPlan.Outcome) async -> String? {
        let stored = scene.programs.saved.count
        let name = stepper.release(outcome)
        await stepper.settle()
        if let name, hasCancelledWaiter {
            coverage.insert("cancelled \(name) \(outcome)".components(separatedBy: "(").first ?? "")
        }
        hasCancelledWaiter = hasCancelledWaiter && !stepper.waiting.isEmpty
        if scene.programs.saved.count > stored {
            coverage.insert(isVisible ? "saved in view" : "saved with the view gone")
        }
        if scene.store.model.error != nil {
            coverage.insert("failure shown")
        }
        if name == "prepare" {
            coverage.insert("prepared")
        }
        return name
    }
}

/// F08 S2 adversarial round 1, criteria 4, 7 and 11: seeded random interleavings of taps, the view going away and
/// coming back (which cancels and restarts its task), and store calls that pass, fail or give up on cancellation.
/// Whatever the order, at most one program is ever stored, the stored one is a program that was asked for, and
/// the screen is never left where nothing answers and nothing is running.
@Suite("Adversarial F08 S2 · random interleavings of taps, cancellation and slow stores", .timeLimit(.minutes(1)))
struct OnboardingInterleavingAdversarialTests {
    /// 100 interleavings in the PR lane, 1,500 in the nightly one (testing-strategy §6).
    static let seeds: Range<UInt64> = 0 ..< (AdversarialLane.isNightly ? 1500 : 100)
    static let moves = 45

    static func randomTap(using random: inout SplitMix64) -> OnboardingAction {
        let goal = TrainingGoal.allCases.randomElement(using: &random) ?? .both
        let days = DaysPerWeek.allCases.randomElement(using: &random) ?? .four
        let taps: [OnboardingAction] = [
            .startTraining, .startTraining, .skipSetup, .retry, .retry, .back, .advance, .advance,
            .pickGoal(goal), .pickDays(days)
        ]
        return taps.randomElement(using: &random) ?? .advance
    }

    static func randomOutcome(using random: inout SplitMix64) -> CallPlan.Outcome {
        switch Int.random(in: 0 ..< 10, using: &random) {
        case 0 ..< 5: .pass
        case 5 ..< 8: .fail(PlantedFailure(marker: "interleaved"))
        default: .honourCancellation
        }
    }

    /// What must hold whenever every task waits or has ended.
    static func expectInvariants(_ root: SteppedRoot, _ context: Comment) {
        let scene = root.scene
        let screen = scene.store.model
        #expect(scene.programs.saved.count <= 1, context)
        if scene.programs.saved.count == 1 {
            #expect(!screen.canProceed, "a program is stored, so no control may start another. \(context)")
        } else if root.stepper.waiting.isEmpty {
            #expect(screen.canProceed, "nothing is stored and nothing runs, so the screen must answer. \(context)")
        }
        #expect(root.stepper.waiting.count <= 1, "one save at a time: \(root.stepper.waiting). \(context)")
    }

    /// One interleaving, checked after every move. Returns what it went through.
    static func interleave(seed: UInt64) async throws -> Set<String> {
        var random = SplitMix64(seed: seed)
        let scene = try AdversarialScene(.seeded())
        if seed.isMultiple(of: 2) {
            scene.walk(goal: .strength, days: .six)
        }
        let root = await SteppedRoot(scene)
        var trail: [String] = []
        for move in 0 ..< moves {
            switch Int.random(in: 0 ..< 10, using: &random) {
            case 0 ..< 4:
                let outcome = randomOutcome(using: &random)
                let name = await root.release(outcome)
                trail.append("release \(name ?? "nothing") \(outcome)")
            case 4 ..< 8:
                let action = randomTap(using: &random)
                await root.tap(action)
                trail.append(root.isVisible ? "tap \(action)" : "no view")
            default:
                await (root.isVisible ? root.disappear() : root.appear())
                trail.append(root.isVisible ? "appear" : "disappear")
            }
            expectInvariants(root, "seed \(seed), move \(move): \(trail.suffix(8).joined(separator: " → "))")
        }
        try await finish(root, seed: seed)
        return root.coverage
    }

    /// Lets everything through, brings the view back and, if nothing is stored yet, skips: one program, asked for.
    static func finish(_ root: SteppedRoot, seed: UInt64) async throws {
        let scene = root.scene
        while await root.release(.pass) != nil {}
        if !root.isVisible {
            await root.appear()
        }
        if scene.programs.saved.isEmpty {
            await root.tap(.skipSetup)
            while await root.release(.pass) != nil {}
        }
        let saved = try #require(scene.programs.saved.first, "seed \(seed): nothing is stored after a clean skip")
        #expect(scene.programs.saved.count == 1, "seed \(seed)")
        let goal = try #require(saved.goal)
        let days = try #require(saved.daysPerWeek.flatMap(DaysPerWeek.init(rawValue:)))
        #expect(root.asked.contains([goal.rawValue, "\(days.rawValue)"]), "seed \(seed): stored what nobody asked for")
        try await scene.expectOneProgram(goal: goal, days: days, offered: scene.programs.offered.count)
        await root.tap(.startTraining)
        await root.tap(.skipSetup)
        await root.tap(.retry)
        #expect(root.stepper.waiting.isEmpty, "seed \(seed): a tap after the save started work")
        #expect(scene.programs.saved.count == 1, "seed \(seed)")
    }

    @Test("Seeded interleavings of 45 moves never store two programs, a wrong one, or leave the screen dead")
    func randomInterleavings_storeAtMostOneAndNeverStick() async throws {
        var coverage: Set<String> = []
        for seed in Self.seeds {
            try await coverage.formUnion(Self.interleave(seed: seed))
        }
        // Control: the interleavings reached the orders they are meant to attack.
        let attacked: Set = [
            "cancelled settings.load pass", "cancelled exercises.all pass", "cancelled programs.save pass",
            "cancelled programs.save honourCancellation", "cancelled programs.save fail", "cancelled prepare pass",
            "cancelled settings.load fail", "saved in view", "saved with the view gone", "failure shown", "prepared"
        ]
        #expect(coverage.isSuperset(of: attacked), "not reached: \(attacked.subtracting(coverage).sorted())")
    }

    @Test("Control: with the view gone a cancelled save is released and the next tap is then the one that saves")
    func steppedRoot_cancelledSaveThenTap_isDrivenAsDescribed() async throws {
        let scene = try AdversarialScene(.seeded())
        scene.walk(goal: .hypertrophy, days: .three)
        let root = await SteppedRoot(scene)
        await root.tap(.startTraining)
        #expect(root.stepper.waiting.count == 1, "the save waits at its first store call")
        await root.disappear()
        #expect(await root.release(.honourCancellation) != nil)
        #expect(root.stepper.waiting.isEmpty)
        #expect(scene.programs.offered.isEmpty)
        await root.appear()
        await root.tap(scene.store.model.primary.action)
        var released: [String] = []
        while let name = await root.release(.pass) {
            released.append(name)
        }
        #expect(released.last == "programs.save", "\(released)")
        #expect(Set(released) == ["settings.load", "exercises.all", "programs.save"], "\(released)")
        try await scene.expectOneProgram(goal: .hypertrophy, days: .three)
    }
}
