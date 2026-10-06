import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// What `LocalWorkoutSessionActor` relies on when it completes an end from the state's phase and not from the
/// effect list (F10 S2, decision 15; review N9): an accepted envelope's effects hold `.materialize` of the
/// state it leaves exactly when it finishes the workout, `.discardLog` exactly when it discards it, and
/// neither otherwise. A host, a retry and recovery then complete the same end the same way.
@Suite("WorkoutEngine · an end's effects", .tags(.domain, .property))
struct EndEffectsTests {
    @Test(
        "Folding a seeded log: materialize(state) for the finish, discardLog for the discard, neither otherwise",
        arguments: PropertySeed.all
    )
    func endEffects_agreeWithThePhase(seed: PropertySeed) {
        var random = RandomWorkout(seed: seed)
        var log = random.log(steps: 40)
        // Every log ends, by a finish or a discard in turn, whatever it drew before.
        let end = EventBuilders.start.addingTimeInterval(86400)
        let last: WorkoutEvent = seed.value.isMultiple(of: 2) ? .finished(endedAt: end) : .discarded(endedAt: end)
        log.append(EventBuilders.envelope(last, seq: 100_000, at: end))
        var state: WorkoutState?
        var ends = 0
        for envelope in log {
            let (next, effects) = WorkoutEngine.reduce(state, envelope)
            let saved = effects.compactMap { effect -> WorkoutState? in
                guard case let .materialize(workout) = effect else {
                    return nil
                }
                return workout
            }
            let drops = effects.count { $0 == .discardLog }
            let hasEnded = state?.phase == .live && next?.phase != .live
            switch (hasEnded, next?.phase) {
            case (true, .finished):
                #expect(saved == [next].compactMap(\.self) && drops == 0, "\(seed): \(envelope.event)")
                ends += 1
            case (true, .discarded):
                #expect(saved.isEmpty && drops == 1, "\(seed): \(envelope.event)")
                ends += 1
            default:
                #expect(saved.isEmpty && drops == 0, "\(seed): \(envelope.event)")
            }
            state = next
        }
        #expect(ends == 1, "\(seed): a workout ends once")
    }
}
