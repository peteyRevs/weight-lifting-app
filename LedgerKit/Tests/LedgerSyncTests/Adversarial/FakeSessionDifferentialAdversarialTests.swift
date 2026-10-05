import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S1 adversarial round 1: `FakeWorkoutSessionClient` beside `SeamOracle` (the brief's criteria over
/// `WorkoutEngine.reduce`, run here) on seeded scripts of `start` / `apply` / `finish` / `discard`, legal
/// and not. Every return value, every thrown error, `current()` after every call, `applied`, and every update
/// on two subscribers (one from the start, one that joins at a step the seed picks) must be the oracle's.
@Suite("Adversarial F10 S1 · fake session vs the engine", .tags(.sync, .property), .timeLimit(.minutes(1)))
struct FakeSessionDifferentialAdversarialTests {
    static let steps = 120

    /// `nil` when `client`, a fresh one, did what the oracle did for the whole script of `seed`; else the
    /// first difference.
    static func divergence(
        seed: UInt64,
        steps: Int = steps,
        on client: any WorkoutSessionClient
    ) async throws -> String? {
        var writer = SeamScriptWriter(seed: seed)
        var oracle = SeamOracle()
        let early = await client.updates()
        var late: AsyncStream<Seam.Update>?
        var expected = (early: [Seam.Update(state: nil)], late: [Seam.Update]())
        let joinAt = Int.random(in: 0 ..< steps, using: &writer.random)
        for step in 0 ..< steps {
            if step == joinAt {
                late = await client.updates()
                expected.late = [Seam.Update(state: oracle.live)]
            }
            let call = writer.next(live: oracle.live)
            let (outcome, published) = oracle.perform(call)
            let actual = await Seam.outcome(of: call, on: client)
            guard actual == outcome else {
                return "step \(step) \(call): \(actual), expected \(outcome)"
            }
            guard try await client.current() == oracle.live else {
                return "step \(step) \(call): current() is not the oracle's live workout afterwards"
            }
            expected.early += published.map { [$0] } ?? []
            expected.late += late == nil ? [] : published.map { [$0] } ?? []
        }
        if let fake = client as? FakeWorkoutSessionClient, await !Seam.sameEvents(fake.applied, oracle.asked) {
            return await "applied lists \(fake.applied.count) events, the script asked \(oracle.asked.count)"
        }
        let mark = try await Seam.Update(state: Seam.mark(client))
        if let fault = await streamFault(early, expected.early + [mark], "the first subscriber") {
            return fault
        }
        return await streamFault(late, expected.late + [mark], "the subscriber that joined at step \(joinAt)")
    }

    private static func streamFault(
        _ stream: AsyncStream<Seam.Update>?,
        _ expected: [Seam.Update],
        _ what: String
    ) async -> String? {
        guard let stream else {
            return "\(what) never joined"
        }
        return await Seam.difference(Seam.buffered(stream), expected, what)
    }

    @Test(
        "A seeded script: the fake returns, throws, holds and publishes what the engine says",
        arguments: SeamSeed.all
    )
    func script_fakeAnswersAsTheEngine(seed: SeamSeed) async throws {
        let divergence = try await Self.divergence(seed: seed.value, on: FakeWorkoutSessionClient())
        #expect(divergence == nil, "\(seed)")
    }

    @Test("The scripts reach what they claim: starts, refusals of each kind, ignored events and both ends")
    func scripts_coverTheRules() {
        var seen: Set<String> = []
        var published = 0
        for seed in SeamSeed.all.prefix(40) {
            var writer = SeamScriptWriter(seed: seed.value)
            var oracle = SeamOracle()
            for _ in 0 ..< Self.steps {
                let call = writer.next(live: oracle.live)
                let before = oracle.live
                let (outcome, update) = oracle.perform(call)
                published += update == nil ? 0 : 1
                seen.insert(Self.kind(call, outcome, update, before: before))
            }
        }
        let wanted: Set = [
            "start ok", "start notStartable", "start notStartable while live", "start workoutInProgress",
            "apply noLiveWorkout", "finish noLiveWorkout", "discard noLiveWorkout", "apply ignored",
            "apply accepted unchanged", "apply changed", "apply haptic", "apply ended",
            "finish ended", "finish invalidEndDate", "discard ended", "discard invalidEndDate"
        ]
        #expect(wanted.subtracting(seen).isEmpty, "never reached: \(wanted.subtracting(seen).sorted())")
        #expect(published > 1000)
    }

    /// The rule a call met, for `scripts_coverTheRules`.
    static func kind(
        _ call: SeamCall,
        _ outcome: SeamOutcome,
        _ update: Seam.Update?,
        before: WorkoutState?
    ) -> String {
        let name = String(call.description.prefix { $0 != "(" })
        switch outcome {
        case .refused(.notStartable):
            return before == nil ? "start notStartable" : "start notStartable while live"
        case let .refused(error):
            return "\(name) \(String(describing: error).prefix { $0 != "(" })"
        case .threw:
            return "\(name) threw"
        case .returned, .state:
            break
        }
        guard let update else {
            return "\(name) ignored"
        }
        if update.state?.phase != .live {
            return "\(name) ended"
        }
        if name == "start" {
            return "start ok"
        }
        guard update.haptics.isEmpty else {
            return "apply haptic"
        }
        return update.state == before ? "apply accepted unchanged" : "apply changed"
    }
}
