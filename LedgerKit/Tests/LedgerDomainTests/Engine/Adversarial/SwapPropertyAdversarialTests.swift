import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S8a adversarial round 1 (G2): seeded scripts of swaps (with and without a replacement, the toggle
/// flipping, the same slot twice, back to the original) among logs, un-logs, steps, repeats and added sets.
/// Each step is checked against a model written from the plan, and the whole log against replay.
@Suite("Adversarial F10 S8a · swap scripts against a model", .tags(.domain, .property))
struct SwapPropertyAdversarialTests {
    /// What the model tracks across a script: the last toggle per slot.
    struct Model {
        var updates: [SlotID: ExerciseID] = [:]
    }

    /// The first broken rule of one swap step, or `nil`.
    static func swapIssue(
        _ before: WorkoutState,
        _ after: WorkoutState,
        _ event: WorkoutEvent,
        _ model: inout Model
    ) -> String? {
        guard case let .exerciseSwapped(index, id, name, toggle, replacement) = event else {
            return nil
        }
        guard before.exercises.indices.contains(index) else {
            return after == before ? nil : "out of range \(index) changed the state"
        }
        guard !SwapAdv.isRefused(replacement) else { // F10-S8a-G2-1's ruling (S8a fix round 1)
            return after == before ? nil : "an unstorable replacement changed the state"
        }
        var expected = before
        expected.exercises[index] = SwapAdv.expected(before.exercises[index], id: id, name: name, replacement)
        if let slot = before.exercises[index].slotID {
            model.updates[slot] = toggle ? id : nil
        }
        expected.programUpdates = model.updates
        if after.programUpdates != model.updates {
            return "programUpdates \(after.programUpdates.count) entries, model \(model.updates.count)"
        }
        let doneBefore = before.exercises[index].sets.filter(\.isDone)
        let doneAfter = after.exercises[index].sets.filter(\.isDone)
        if doneBefore != doneAfter {
            return "a done set changed at a swap"
        }
        return after == expected ? nil : "swap of \(index) differs from the plan's rule"
    }

    @Test(
        "Each swap does what the plan says; replay of the log, shuffled and doubled, equals the fold",
        arguments: PropertySeed.all
    )
    func scripts_matchTheModel(seed: PropertySeed) throws {
        var rng = seed.generator
        var start = SwapAdv.session()
        start.units = Bool.random(using: &rng) ? .lb : .kg
        var events: [WorkoutEvent] = [.started(start)]
        var state: WorkoutState?
        var model = Model()
        var envelopes: [EventEnvelope] = []
        for step in 0 ..< 40 {
            let time = EventBuilders.start.addingTimeInterval(Double(step * 10))
            let event = try step == 0 ? events[0] : SwapAdv.randomEvent(#require(state), at: time, &rng)
            let device = Bool.random(using: &rng) ? EventBuilders.phone : EventBuilders.watch
            let seq = UInt64(envelopes.count(where: { $0.device == device }) + 1)
            let envelope = EventBuilders.envelope(event, device: device, seq: seq, at: time)
            let before = state
            state = WorkoutEngine.reduce(state, envelope).0
            envelopes.append(envelope)
            if let before, let after = state, let issue = Self.swapIssue(before, after, event, &model) {
                Issue.record("\(seed) step \(step): \(issue)")
                return
            }
            if step > 0 {
                events.append(event)
            }
        }
        var shuffled = envelopes + envelopes.shuffled(using: &rng).prefix(10)
        shuffled.shuffle(using: &rng)
        let replayed = WorkoutEngine.replay(shuffled) == state
        #expect(replayed, "\(seed): replay differs from the fold")
        let decoded = try envelopes.map { try EnvelopeCodec.decode(EnvelopeCodec.encode($0), version: 1) }
        let afterCodec = WorkoutEngine.replay(decoded) == state
        #expect(afterCodec, "\(seed): replay after the codec differs")
    }

    @Test(
        "A replacement with no logged set: undone rows all equal the load or its drop, whatever came before",
        arguments: PropertySeed.all.prefix(50)
    )
    func swap_afterSteps_everyUndoneRowIsTheLoadOrItsDrop(seed: PropertySeed) throws {
        var rng = seed.generator
        let start = SwapAdv.session()
        var events: [WorkoutEvent] = []
        var current = try #require(SwapAdv.fold(start, []))
        for _ in 0 ..< 12 {
            events.append(SwapAdv.randomEvent(current, at: EventBuilders.start, &rng))
            current = try #require(SwapAdv.fold(start, events))
        }
        let index = Int.random(in: 0 ..< 3, using: &rng)
        let swap = SwappedExercise(
            equipment: .kettlebell,
            step: .kilograms(2),
            load: SwapAdv.randomWeight(&rng),
            lastPerformance: nil
        )
        let after = try #require(SwapAdv.fold(start, events + [SwapAdv.swap(index, swap)]))
        guard !SwapAdv.isRefused(swap) else { // F10-S8a-G2-1's ruling (S8a fix round 1): ignored
            let unchanged = after == current
            #expect(unchanged, "\(seed): an unstorable replacement changed the state")
            return
        }
        let drop = SessionBuilder.dropLoad(of: swap.load, step: swap.step)
        let wrong = after.exercises[index].sets.filter { !$0.isDone }
            .count { $0.weight != ($0.kind == .drop ? drop : swap.load) }
        #expect(wrong == 0, "\(seed)")
    }
}

/// The script generators.
extension SwapAdv {
    static func randomWeight(_ rng: inout SeededGenerator) -> Weight {
        switch Int.random(in: 0 ..< 6, using: &rng) {
        case 0: .zero
        case 1: .pounds(Decimal(Int.random(in: 0 ... 200, using: &rng)) * SwapAdv.dec("2.5"))
        case 2: .kilograms(Decimal(Int.random(in: 0 ... 100, using: &rng)) * 2)
        case 3: Weight(grams: Decimal(Int.random(in: 0 ... 1_000_000, using: &rng)) / 7) // inexact, off-step
        case 4: .pounds(SwapAdv.dec("185.125"))
        default: .kilograms(SwapAdv.dec("83.91458845"))
        }
    }

    static func randomSwap(_ state: WorkoutState, _ rng: inout SeededGenerator) -> WorkoutEvent {
        let index = Int.random(in: -1 ... state.exercises.count, using: &rng)
        let backToOriginal = Bool.random(using: &rng) && state.exercises.indices.contains(index)
        let id = backToOriginal ? state.exercises[index].originalExerciseID
            : ExerciseID(EventBuilders.uuid(0xEE00 + Int.random(in: 0 ..< 6, using: &rng)))
        let replacement: SwappedExercise? = Int.random(in: 0 ..< 4, using: &rng) == 0 ? nil : SwappedExercise(
            equipment: Equipment.allCases.randomElement(using: &rng) ?? .barbell,
            step: [Weight.pounds(5), .pounds(2.5), .kilograms(2), .kilograms(1.25), .kilograms(2.5)]
                .randomElement(using: &rng) ?? .pounds(5),
            load: randomWeight(&rng),
            lastPerformance: Bool.random(using: &rng) ? nil : LastPerformance(
                date: EventBuilders.start.addingTimeInterval(-Double.random(in: 0 ... 1e7, using: &rng)),
                sets: 3, reps: 5, load: randomWeight(&rng)
            )
        )
        return .exerciseSwapped(
            exerciseIndex: index,
            exerciseID: id,
            name: "N\(id.rawValue.uuidString.suffix(3))",
            alsoUpdateProgram: Bool.random(using: &rng),
            replacement: replacement
        )
    }

    static func randomEvent(_ state: WorkoutState, at time: Date, _ rng: inout SeededGenerator) -> WorkoutEvent {
        let exercise = Int.random(in: 0 ..< state.exercises.count, using: &rng)
        let sets = state.exercises[exercise].sets
        let set = sets.randomElement(using: &rng)?.id ?? EventBuilders.setID(exercise, 0)
        switch Int.random(in: 0 ..< 7, using: &rng) {
        case 0, 1:
            return randomSwap(state, &rng)
        case 2:
            return .setLogged(
                exerciseIndex: exercise,
                setID: set,
                weight: randomWeight(&rng),
                reps: Reps(clamping: Int.random(in: 0 ... 12, using: &rng)),
                doneAt: time
            )
        case 3:
            return .setUnlogged(exerciseIndex: exercise, setID: set)
        case 4:
            return .setTargetChanged(exerciseIndex: exercise, setID: set, weight: randomWeight(&rng), reps: nil)
        case 5:
            return .allSetsRepeated(exerciseIndex: exercise, weight: randomWeight(&rng), reps: Reps(clamping: 5))
        default:
            let kind: SetKind = [.added, .drop, .warmup].randomElement(using: &rng) ?? .added
            return .setAdded(exerciseIndex: exercise, set: LoggedSet(
                id: SetID(EventBuilders.uuid(0x5000 + Int.random(in: 0 ..< 100_000, using: &rng))),
                weight: randomWeight(&rng), reps: Reps(clamping: 5), kind: kind,
                doneAt: Bool.random(using: &rng) ? time : nil
            ))
        }
    }
}
