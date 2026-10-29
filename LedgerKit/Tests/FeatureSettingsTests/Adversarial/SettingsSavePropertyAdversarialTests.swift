@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F14 S1a, G2: R7's save queue against an oracle, over seeded random scripts. A script sends changes, and ends
/// held saves as committed or refused, in any order; the store is let settle after each end. The oracle is N1 as
/// written: the lifter's value is the last one sent, and a refused save puts back the stored value (the row).
///
/// After every step: the screen shows the oracle's value; a held save is of the whole latest value (the last
/// value wins, folded); never two saves at once. At the end, every save committed: the row is the oracle's value,
/// nothing is pending, and there were no more saves than changes.
@MainActor
@Suite("Settings' save queue, property", .serialized, .tags(.feature), .timeLimit(.minutes(2)))
struct SettingsSavePropertyAdversarialTests {
    /// SplitMix64: the same seed gives the same script on every machine.
    struct Generator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }

        mutating func below(_ bound: Int) -> Int {
            Int(next() % UInt64(bound))
        }
    }

    static func action(_ generator: inout Generator) -> SettingsAction {
        switch generator.below(6) {
        case 0: .setUnits(generator.below(2) == 0 ? .lb : .kg)
        case 1: .setDefaultRest(RestDuration(clampingSeconds: 30 + 15 * generator.below(19)))
        case 2: .setWeekStart(Weekday.allCases[generator.below(7)])
        case 3: .setPlateMath(generator.below(2) == 0)
        case 4: .setAutoRest(generator.below(2) == 0)
        default: .setWatchBuzz(generator.below(2) == 0)
        }
    }

    /// A short spelling for messages: "kg 120 P- A+ B- thu".
    static func brief(_ settings: Settings?) -> String {
        guard let settings else {
            return "nil"
        }
        let flags = [settings.plateMathEnabled, settings.autoRest, settings.watchBuzz]
            .enumerated().map { ["P", "A", "B"][$0.offset] + ($0.element ? "+" : "-") }
        return "\(settings.units) \(settings.defaultRest.seconds) \(flags.joined(separator: " ")) \(settings.weekStart)"
    }

    static func applying(_ action: SettingsAction, to settings: Settings) -> Settings {
        var next = settings
        switch action {
        case let .setUnits(units): next.units = units
        case let .setDefaultRest(rest): next.defaultRest = rest
        case let .setWeekStart(day): next.weekStart = day
        case let .setPlateMath(isOn): next.plateMathEnabled = isOn
        case let .setAutoRest(isOn): next.autoRest = isOn
        case let .setWatchBuzz(isOn): next.watchBuzz = isOn
        case .route: break
        }
        return next
    }

    /// The oracle's state through a script: the lifter's value, the changes sent, and what disagreed.
    struct Run {
        var lifter = Fixtures.settingsLb
        var changes = 0
        var problems: [String] = []
    }

    /// One step of the script: a send, or the end of the oldest held save, the store then let settle.
    static func step(
        _ step: Int,
        _ generator: inout Generator,
        _ scene: ScriptedSettingsScene,
        _ run: inout Run
    ) async {
        let roll = generator.below(100)
        if roll < 55 || scene.repository.heldValues.isEmpty {
            let action = action(&generator)
            let before = run.lifter
            run.lifter = applying(action, to: run.lifter)
            run.changes += run.lifter == before ? 0 : 1
            scene.store.send(action)
            if scene.store.shown != run.lifter {
                run.problems.append("step \(step): the send of \(action) is not shown at once")
            }
            if roll.isMultiple(of: 3) {
                await scene.settle()
            }
            return
        }
        let commits = roll < 82
        scene.repository.resolveNext(commit: commits)
        await scene.settle()
        if !commits {
            run.lifter = scene.repository.row
            if scene.store.model?.problem == nil {
                run.problems.append("step \(step): a refused save shows no problem")
            }
        }
        if scene.store.shown != run.lifter {
            run.problems.append("step \(step): after a \(commits ? "commit" : "refusal") the screen differs")
        }
        if let next = scene.repository.heldValues.first, next != run.lifter {
            run.problems.append("step \(step): the next save is not of the latest whole value")
        }
    }

    @Test("R7, N1. Random sends, commits and refusals agree with the oracle", arguments: 0 ..< 40)
    func randomScript_agreesWithTheOracle(seed: Int) async {
        var generator = Generator(state: UInt64(seed) &* 7919 &+ 1)
        let scene = ScriptedSettingsScene()
        let task = await scene.running()
        defer { task.cancel() }
        var run = Run()
        for step in 0 ..< 40 {
            await Self.step(step, &generator, scene, &run)
        }
        // Every save from here commits, until nothing is pending.
        for _ in 0 ..< 50 {
            await scene.settle()
            guard !scene.repository.heldValues.isEmpty else {
                break
            }
            scene.repository.resolveNext(commit: true)
        }
        await scene.until("nothing pending") { scene.store.pending == nil }
        #expect(run.problems.isEmpty, "seed \(seed): \(run.problems.prefix(3))")
        #expect(scene.repository.mostAtOnce == 1, "seed \(seed)")
        let row = scene.repository.row
        let state = "row \(Self.brief(row)), lifter \(Self.brief(run.lifter)), "
            + "pending \(Self.brief(scene.store.pending)), stored \(Self.brief(scene.store.stored))"
        let rowIsLifters = row == run.lifter
        let shownIsLifters = scene.store.shown == run.lifter
        #expect(rowIsLifters, "seed \(seed): the row is not the lifter's last value; \(state)")
        #expect(shownIsLifters, "seed \(seed): \(state)")
        #expect(scene.repository.saves.count <= run.changes, "seed \(seed): more saves than changes")
    }
}
