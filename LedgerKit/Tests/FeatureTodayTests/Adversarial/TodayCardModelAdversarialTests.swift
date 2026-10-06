@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S3, gate G2: which card Today shows, with its title and its routes, and the strip and the tiles beside
/// it, for seeded inputs (`TodayScenario`) against the tester's own model of the specification (`TodayOracle`).
/// A failing seed is named in the failure's line and can be replayed with `TodayScenario(seed:catalog:)`.
@Suite("Adversarial F09 S3 · which card, against the tester's model", .tags(.feature))
nonisolated struct TodayCardModelAdversarialTests {
    typealias Support = TodayAdversarial

    /// 4,000 seeds in eight batches.
    static let batches: [ClosedRange<UInt64>] = (0 ..< 8).map { $0 * 500 ... $0 * 500 + 499 }

    @Test("Seeded inputs show the card, the title, the strip and the tiles the specification gives", arguments: batches)
    func seededInputs_showWhatTheSpecificationGives(_ seeds: ClosedRange<UInt64>) throws {
        let failures = try Self.disagreements(seeds, asGenerated: false)
        let lines = failures.prefix(6).joined(separator: "\n")
        let agrees = failures.isEmpty
        #expect(agrees, "\(failures.count) of \(seeds.count) seeds disagree with the model:\n\(lines)")
    }

    @Test("The same holds when the week's workouts arrive in another order than newest first", arguments: batches)
    func seededInputsInAnyOrder_showWhatTheSpecificationGives(_ seeds: ClosedRange<UInt64>) throws {
        let failures = try Self.disagreements(seeds, asGenerated: true)
        let lines = failures.prefix(6).joined(separator: "\n")
        let agrees = failures.isEmpty
        #expect(agrees, "\(failures.count) of \(seeds.count) seeds disagree with the model:\n\(lines)")
    }

    /// One short line per seed whose model is not the oracle's.
    static func disagreements(_ seeds: ClosedRange<UInt64>, asGenerated: Bool) throws -> [String] {
        let catalog = try Support.exercises()
        var failures: [String] = []
        for seed in seeds {
            let scenario = try TodayScenario(seed: seed, catalog: catalog, asGenerated: asGenerated)
            let model = TodayPresentation.make(scenario.input)
            let oracle = try #require(TodayOracle(scenario.input))
            let problems = oracle.problems(in: model, for: scenario.input)
            if !problems.isEmpty {
                failures.append("seed \(seed) [\(scenario.note)]: \(problems.prefix(3).joined(separator: "; "))")
            }
        }
        return failures
    }

    @Test("The seeds reach each of the six outcomes often enough to mean something")
    func seeds_reachEveryOutcome() throws {
        let catalog = try Support.exercises()
        var counts: [String: Int] = [:]
        for seed in UInt64(0) ..< 4000 {
            let scenario = try TodayScenario(seed: seed, catalog: catalog)
            let card = try #require(TodayOracle(scenario.input)).card
            let kind = String(card.description.prefix { $0 != "(" })
            counts[kind, default: 0] += 1
        }
        print("TodayCardModelAdversarialTests outcomes over 4,000 seeds: \(counts.sorted { $0.key < $1.key })")
        for kind in ["resume", "start", "logged", "rest", "noProgram", "blockComplete"] {
            #expect(counts[kind, default: 0] >= 60, "only \(counts[kind, default: 0]) seeds give \(kind)")
        }
    }

    @Test("The same input gives the same model, however often it is asked", arguments: [UInt64(0) ... 299])
    func sameInput_givesTheSameModel(_ seeds: ClosedRange<UInt64>) throws {
        let catalog = try Support.exercises()
        var different: [UInt64] = []
        for seed in seeds {
            let scenario = try TodayScenario(seed: seed, catalog: catalog)
            let first = TodayPresentation.make(scenario.input)
            let again = try TodayPresentation.make(TodayScenario(seed: seed, catalog: catalog).input)
            if first != TodayPresentation.make(scenario.input) || first != again {
                different.append(seed)
            }
        }
        let isStable = different.isEmpty
        #expect(isStable, "seeds whose model changed between calls: \(different.prefix(10))")
    }
}
