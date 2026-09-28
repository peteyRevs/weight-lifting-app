import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

@Suite("WorkoutEngine · model-based (criterion 10)", .tags(.domain, .property))
struct ModelOracleTests {
    /// Each seed checks five sequences, so the PR lane's 200 seeds cover criterion 10's 1,000.
    static let sequencesPerSeed = 5

    @Test(
        "Criterion 10: random valid sequences reduced step by step match ModelOracle at every step",
        arguments: PropertySeed.all
    )
    func reduce_matchesOracle_atEveryStep(seed: PropertySeed) {
        var random = RandomWorkout(seed: seed)
        for sequence in 0 ..< Self.sequencesPerSeed {
            var state: WorkoutState?
            var oracle = ModelOracle()
            for (step, envelope) in random.log(steps: 60).enumerated() {
                state = WorkoutEngine.reduce(state, envelope).0
                oracle.apply(envelope)
                guard state == oracle.state else {
                    Issue.record("\(seed), sequence \(sequence), step \(step): \(envelope.event)")
                    return
                }
            }
        }
    }

    @Test("replay of a shuffled, partly duplicated log matches the oracle's own replay", arguments: PropertySeed.all)
    func replay_matchesOracleReplay(seed: PropertySeed) {
        var random = RandomWorkout(seed: seed)
        let log = random.log(steps: 40)
        let arrival = random.shuffled(log + log.suffix(8))
        #expect(WorkoutEngine.replay(arrival) == ModelOracle.replay(arrival))
    }

    @Test("The oracle is not vacuous: it reproduces criteria 1 and 2 on its own")
    func oracle_reproducesCriteria1And2() throws {
        let seed = EventBuilders.log(from: [.started(EventBuilders.seedSession()), Engine.logged(0, 0, at: 10)])
        let first = try #require(ModelOracle.replay(seed))
        #expect(first.rest == RestTimer(endsAt: Engine.at(160), total: .seconds(150)))
        #expect(first.cursor == Cursor(exerciseIndex: 0, setIndex: 1))

        let superset = EventBuilders.log(from: [
            .started(EventBuilders.session(EventBuilders.supersetExercises)),
            Engine.logged(0, 0, at: 10),
            Engine.logged(1, 0, at: 20)
        ])
        let afterB1 = try #require(ModelOracle.replay(superset))
        #expect(afterB1.rest == RestTimer(endsAt: Engine.at(110), total: .seconds(90)))
        #expect(afterB1.cursor == Cursor(exerciseIndex: 0, setIndex: 1))
    }
}
