@testable import FeatureOnboarding
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// The screen as the brief's S2 criteria describe it, written from the brief alone: three steps, two picks, a
/// save that either stores one program or shows the failure, and a retry of what failed.
nonisolated struct BriefModel {
    enum Phase: Sendable {
        case picking, failed, saved
    }

    struct Request: Equatable, Sendable {
        var goal: TrainingGoal
        var days: DaysPerWeek
    }

    var step = 0
    var goal = TrainingGoal.both
    var days = DaysPerWeek.four
    var phase = Phase.picking
    /// What the failed attempt asked for: what "Retry" asks for again.
    var failed: Request?
    var saved: Request?
    /// The retry steps that must have run, and those that may have ("Skip setup" after a failure: the brief
    /// names the retry step for "Retry" only).
    var prepares = 0
    var optionalPrepares = 0

    /// The controls the brief puts on the screen now. After a failure it names "Retry" and "Skip setup" only.
    var offered: [OnboardingAction] {
        switch (phase, step) {
        case (.saved, _): []
        case (.failed, _): [.retry, .skipSetup]
        case (.picking, 0): TrainingGoal.allCases.map(OnboardingAction.pickGoal) + [.advance, .skipSetup]
        case (.picking, 1): DaysPerWeek.allCases.map(OnboardingAction.pickDays) + [.advance, .back, .skipSetup]
        case (.picking, _): [.startTraining, .back, .skipSetup]
        }
    }

    /// Applies a tap on an offered control. A tap that starts a save ends as `saveFails` says.
    mutating func apply(_ action: OnboardingAction, saveFails: Bool) {
        guard phase != .saved else {
            return
        }
        switch action {
        case let .pickGoal(goal): self.goal = goal
        case let .pickDays(days): self.days = days
        case .advance: step = min(step + 1, 2)
        case .back: step = max(step - 1, 0)
        case .startTraining: save(Request(goal: goal, days: days), fails: saveFails)
        case .skipSetup:
            optionalPrepares += phase == .failed ? 1 : 0
            save(Request(goal: .both, days: .four), fails: saveFails)
        case .retry:
            guard let failed else {
                return
            }
            prepares += 1
            save(failed, fails: saveFails)
        }
    }

    private mutating func save(_ request: Request, fails: Bool) {
        phase = fails ? .failed : .saved
        failed = fails ? request : nil
        saved = fails ? nil : request
    }
}

/// F08 S2 adversarial round 1, criteria 1 to 5 and 7 together: seeded random walks of taps, each on a control the
/// brief puts on the screen at that moment, with saves that fail at a random step, checked after every tap
/// against `BriefModel`. A failing seed is printed in the failure.
@Suite("Adversarial F08 S2 · random walks against the brief's model", .timeLimit(.minutes(1)))
struct OnboardingModelAdversarialTests {
    /// 100 walks in the PR lane, 2,000 in the nightly one (testing-strategy §6).
    static let seeds: Range<UInt64> = 0 ..< (AdversarialLane.isNightly ? 2000 : 100)
    static let taps = 40

    /// The model and the screen agree: the step, the picks, the texts of the state, and what is stored.
    static func expectAgreement(_ model: BriefModel, _ scene: AdversarialScene, _ context: Comment) {
        let state = scene.store.state
        let screen = scene.store.model
        #expect(state.step.rawValue == model.step, context)
        #expect(state.goal == model.goal, context)
        #expect(state.days == model.days, context)
        #expect(screen.progressLabel == BriefCopy.step(model.step + 1), context)
        #expect(screen.showsBack == (model.step > 0), context)
        #expect(screen.error == (model.phase == .failed ? BriefCopy.saveFailed : nil), context)
        let primary = [BriefCopy.continueTitle, BriefCopy.continueTitle, BriefCopy.startTraining][model.step]
        #expect(screen.primary.title == (model.phase == .failed ? BriefCopy.retry : primary), context)
        #expect(screen.skip.title == BriefCopy.skipSetup, context)
        #expect(scene.programs.saved.count == (model.saved == nil ? 0 : 1), context)
        let prepared = scene.journal.count(of: "prepare.start")
        #expect((model.prepares ... model.prepares + model.optionalPrepares).contains(prepared), context)
        switch screen.content {
        case let .options(options):
            #expect(model.step < 2, context)
            #expect(options.count { $0.isSelected } == 1, "exactly one pick. \(context)")
            let picked = options.first { $0.isSelected }?.title
            let expected = model.step == 0
                ? BriefCopy.goals.first { $0.goal == model.goal }?.title
                : BriefCopy.days.first { $0.days == model.days }?.title
            #expect(picked == expected, context)
        case let .days(rows):
            #expect(model.step == 2, context)
            #expect(rows.map(\.title) == BriefCopy.dayRows(model.days).map(\.title), context)
            #expect(screen.body == BriefCopy.programBody(model.days, .lb), context)
        }
    }

    /// The next tap of a walk: a control the brief offers now (after the program is saved it offers none, so every
    /// control is then a stale tap), "Skip setup" less often than the rest so that walks last, and whether the save
    /// it starts fails.
    static func nextTap(
        _ model: BriefModel,
        using random: inout SplitMix64
    ) -> (action: OnboardingAction, fails: Bool) {
        var offered = model.phase == .saved ? OnboardingSaveOnceAdversarialTests.everyAction : model.offered
        if model.phase != .saved, Int.random(in: 0 ..< 12, using: &random) != 0 {
            offered.removeAll { $0 == .skipSetup }
        }
        let action = offered.randomElement(using: &random) ?? .skipSetup
        let startsSave = model.phase != .saved && [.startTraining, .skipSetup, .retry].contains(action)
        return (action, startsSave && Int.random(in: 0 ..< 5, using: &random) < 3)
    }

    /// Plants a failure at a random step of the next save.
    static func plantFailure(in scene: AdversarialScene, using random: inout SplitMix64) {
        switch Int.random(in: 0 ..< 3, using: &random) {
        case 0: scene.settings.script.next(.fail("settings"))
        case 1: scene.exercises.script.next(.fail("catalog"))
        default: scene.programs.script.next(.fail("write"))
        }
    }

    /// One walk, checked after every tap; the last taps are in each failure's message.
    static func walk(seed: UInt64) async throws {
        var random = SplitMix64(seed: seed)
        let scene = try AdversarialScene(.seeded())
        await scene.store.loadUnits()
        var model = BriefModel()
        var trail: [String] = []
        for tap in 0 ..< taps {
            let (action, fails) = nextTap(model, using: &random)
            if fails {
                plantFailure(in: scene, using: &random)
            }
            model.apply(action, saveFails: fails)
            await scene.tap(action)
            trail.append("\(action)\(fails ? " (fails)" : "")")
            expectAgreement(model, scene, "seed \(seed), tap \(tap): \(trail.suffix(6).joined(separator: " → "))")
        }
        guard let saved = model.saved else {
            #expect(scene.programs.saved.isEmpty, "seed \(seed)")
            return
        }
        try await scene.expectOneProgram(goal: saved.goal, days: saved.days, offered: scene.programs.offered.count)
    }

    @Test("Seeded walks of 40 taps agree with the brief's model after every tap")
    func randomWalks_agreeWithTheBriefsModel() async throws {
        for seed in Self.seeds {
            try await Self.walk(seed: seed)
        }
    }

    @Test("Control: the walks reach every step, a failure, a retry that prepares, and most kinds of saved program")
    func randomWalks_coverTheStates() {
        var seen = Set<String>()
        for seed in Self.seeds {
            var random = SplitMix64(seed: seed)
            var model = BriefModel()
            for _ in 0 ..< Self.taps {
                let (action, fails) = Self.nextTap(model, using: &random)
                if fails {
                    _ = Int.random(in: 0 ..< 3, using: &random)
                }
                model.apply(action, saveFails: fails)
                seen.insert("step \(model.step) \(model.phase)")
                if let saved = model.saved {
                    seen.insert("saved \(saved.goal) \(saved.days.rawValue)")
                }
                if model.prepares > 0 {
                    seen.insert("prepared")
                }
            }
        }
        let steps = [0, 1, 2].flatMap { step in ["picking", "failed", "saved"].map { "step \(step) \($0)" } }
        #expect(seen.isSuperset(of: steps + ["prepared", "saved both 4"]), "\(seen.sorted())")
        // Of the sixteen programs a walk can end on: all in the nightly lane's 2,000 walks, most in the PR lane's 100.
        let kinds = seen.count { $0.hasPrefix("saved ") }
        #expect(kinds >= (AdversarialLane.isNightly ? 16 : 12), "\(seen.sorted())")
    }
}
