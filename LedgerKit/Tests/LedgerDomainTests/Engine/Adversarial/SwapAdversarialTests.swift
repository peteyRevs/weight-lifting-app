import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

@Suite("Adversarial F10 S8a · the reducer's swap", .tags(.domain))
struct SwapReduceAdversarialTests {
    @Test("No replacement: only the id and the name change, as before S8; the toggle on writes the slot")
    func swap_noReplacement_changesOnlyIdAndName() throws {
        let start = SwapAdv.session()
        let event = SwapAdv.swap(0, program: true)
        let state = try #require(SwapAdv.fold(start, [event]))
        let id = ExerciseID(EventBuilders.uuid(0xEEA1))
        var expected = start
        expected.exercises[0] = SwapAdv.expected(start.exercises[0], id: id, name: "Dumbbell Bench Press", nil)
        expected.programUpdates = try [#require(start.exercises[0].slotID): id]
        let matches = state == expected
        #expect(matches)
    }

    @Test("A replacement re-targets every undone row: working and added take the load, drop its drop")
    func swap_replacement_retargetsUndoneRows() throws {
        let start = SwapAdv.session()
        let added = LoggedSet(
            id: SetID(EventBuilders.uuid(0xADD)),
            weight: .pounds(185),
            reps: Reps(clamping: 3),
            kind: .added
        )
        let warm = LoggedSet(
            id: SetID(EventBuilders.uuid(0xADE)),
            weight: .pounds(95),
            reps: Reps(clamping: 3),
            kind: .warmup
        )
        let swap = SwapAdv.replacement(.dumbbell, step: .pounds(2.5), load: .pounds(60))
        let state = try #require(SwapAdv.fold(start, [
            .setAdded(exerciseIndex: 0, set: added),
            .setAdded(exerciseIndex: 0, set: warm),
            SwapAdv.swap(0, swap)
        ]))
        let sets = state.exercises[0].sets
        #expect(sets.filter { $0.kind != .drop }.allSatisfy { $0.weight == .pounds(60) })
        // 60 × 0.85 = 51 → 50 on a 2.5 lb step.
        #expect(sets.filter { $0.kind == .drop }.map(\.weight) == [.pounds(50)])
        #expect(state.exercises[0].targetLoad == .pounds(60))
        #expect(state.exercises[0].equipment == .dumbbell && state.exercises[0].step == .pounds(2.5))
    }

    @Test("Kettlebell in kilograms, step 2: 16 kg → drop 13.6 → 14; an off-step load is copied, not rounded")
    func swap_kettlebell_dropRoundsToTwoKilograms() throws {
        var start = SwapAdv.session()
        start.units = .kg
        for (load, drop) in [("16", "14"), ("17", "14"), ("24", "20"), ("2", "2"), ("1", "0")] {
            let swap = try SwapAdv.replacement(
                .kettlebell,
                step: .kilograms(2),
                load: .kilograms(SwapAdv.dec(load))
            )
            let state = try #require(SwapAdv.fold(start, [SwapAdv.swap(2, swap)]))
            let sets = state.exercises[2].sets
            #expect(sets.filter { $0.kind == .working }.allSatisfy { $0.weight == .kilograms(SwapAdv.dec(load)) })
            #expect(
                sets.filter { $0.kind == .drop }.map(\.weight) == [.kilograms(SwapAdv.dec(drop))],
                "load \(load)"
            )
        }
    }

    @Test("Done sets keep their weight, reps and time; the superset flag, slot, original, rest, RPE stay")
    func swap_doneSetsAndSlotFieldsUntouched() throws {
        let start = SwapAdv.session()
        let logged: [WorkoutEvent] = [
            .setLogged(
                exerciseIndex: 2,
                setID: EventBuilders.setID(2, 0),
                weight: .pounds(75),
                reps: Reps(clamping: 7),
                doneAt: EventBuilders.start.addingTimeInterval(30)
            ),
            .setLogged(
                exerciseIndex: 2,
                setID: EventBuilders.setID(2, 4),
                weight: .pounds(60),
                reps: Reps(clamping: 9),
                doneAt: EventBuilders.start.addingTimeInterval(60)
            )
        ]
        let before = try #require(SwapAdv.fold(start, logged))
        let swap = SwapAdv.replacement(.cable, step: .pounds(2.5), load: .pounds(90))
        let after = try #require(SwapAdv.fold(start, logged + [SwapAdv.swap(2, swap)]))
        let id = ExerciseID(EventBuilders.uuid(0xEEA1))
        let swapped = after.exercises[2] == SwapAdv.expected(
            before.exercises[2],
            id: id,
            name: "Dumbbell Bench Press",
            swap
        )
        let others = after.exercises[0] == before.exercises[0] && after.exercises[1] == before.exercises[1]
        #expect(swapped && others)
        #expect(after.exercises[2].isSupersetWithPrevious)
        #expect(after.cursor == before.cursor && after.rest == before.rest)
    }

    @Test("An index out of range, negative or huge, changes nothing and the envelope is still persisted")
    func swap_outOfRange_changesNothing() {
        let start = SwapAdv.session()
        for index in [-1, 3, Int.max, Int.min] {
            let envelope = EventBuilders.envelope(
                SwapAdv.swap(index, program: true, SwapAdv.replacement()),
                seq: 2,
                at: EventBuilders.start
            )
            let (state, effects) = WorkoutEngine.reduce(start, envelope)
            let unchanged = state == start
            #expect(unchanged, "index \(index)")
            #expect(effects == [.persist(envelope), .transmit(envelope)], "index \(index)")
        }
    }

    @Test("An unknown exercise id, an empty name and a 10,000-character name are taken as given; no trap")
    func swap_oddIdentity_isCopied() throws {
        let start = SwapAdv.session()
        for name in ["", String(repeating: "é", count: 10000), "\u{0}"] {
            let state = try #require(SwapAdv.fold(start, [SwapAdv.swap(1, to: 0xFFF, name: name)]))
            #expect(state.exercises[1].name == name)
        }
    }

    @Test("Malformed replacements are ignored in memory too: NaN step, NaN load, ±∞ and NaN Last date")
    func swap_malformedInMemory_isIgnored() {
        let start = SwapAdv.session()
        let bad: [SwappedExercise] = [
            SwapAdv.replacement(step: Weight(grams: .nan)),
            SwapAdv.replacement(load: Weight(grams: .nan)),
            SwapAdv.replacement(step: .zero),
            SwapAdv.replacement(step: .pounds(-2.5)),
            SwapAdv.replacement(load: .pounds(-1)),
            SwapAdv.replacement(last: LastPerformance(
                date: Date(timeIntervalSinceReferenceDate: .nan),
                sets: 1,
                reps: 1,
                load: .pounds(1)
            )),
            SwapAdv.replacement(last: LastPerformance(
                date: .distantFuture.addingTimeInterval(.infinity),
                sets: 1,
                reps: 1,
                load: .pounds(1)
            ))
        ]
        for (number, swap) in bad.enumerated() {
            let envelope = EventBuilders.envelope(SwapAdv.swap(0, program: true, swap), seq: 2, at: EventBuilders.start)
            let (state, effects) = WorkoutEngine.reduce(start, envelope)
            let unchanged = state == start
            #expect(unchanged && effects.isEmpty, "case \(number)")
        }
    }
}

@Suite("Adversarial F10 S8a · the reducer's swap, edges and the toggle", .tags(.domain))
struct SwapReduceEdgeAdversarialTests {
    @Test("A zero load (bodyweight) is accepted: every undone row is 0, the drop 0")
    func swap_bodyweightZero_isAccepted() throws {
        let swap = SwapAdv.replacement(.bodyweight, step: .pounds(2.5), load: .zero)
        let state = try #require(SwapAdv.fold(SwapAdv.session(), [SwapAdv.swap(0, swap)]))
        #expect(state.exercises[0].sets.allSatisfy { $0.weight == .zero })
    }

    /// FAILING (F10-S8a-G2-1): a replacement that passes `isWellFormed` can still leave a weight the store
    /// cannot write: a step so small that the drop's quotient overflows `Decimal` (NaN), or one finer than
    /// 10⁻⁷ g. The engine accepts it, the event store keeps it, and the workout can never be saved (F10-S2-1).
    @Test("FAILING F10-S8a-G2-1: an accepted replacement leaves every weight a finite whole number of 10⁻⁷ g")
    func failing_wellFormedReplacement_leavesStorableWeights() throws {
        let start = SwapAdv.session()
        let hostile: [(String, SwappedExercise)] = try [
            ("huge load, tiny step", SwapAdv.replacement(
                step: Weight(grams: SwapAdv.dec("1e-120")),
                load: Weight(grams: SwapAdv.dec("1e120"))
            )),
            (
                "step finer than 1e-7 g",
                SwapAdv.replacement(
                    step: Weight(grams: SwapAdv.dec("0.000000001")),
                    load: Weight(grams: SwapAdv.dec("0.000000003"))
                )
            ),
            (
                "load beyond Int64 units",
                SwapAdv.replacement(step: .pounds(5), load: Weight(grams: SwapAdv.dec("1e30")))
            )
        ]
        for (label, swap) in hostile {
            let envelope = EventBuilders.envelope(SwapAdv.swap(0, swap), seq: 2, at: EventBuilders.start)
            let state = WorkoutEngine.reduce(start, envelope).0
            let unstorable = SwapAdv.weights(state).count { !SwapAdv.isWholeE7g($0) }
            #expect(unstorable == 0, "\(label): \(unstorable) weights the store refuses")
        }
    }

    @Test("Toggle: on writes the slot, a second swap with it off removes it; ad hoc writes none; back to original")
    func swap_toggle() throws {
        let start = SwapAdv.session()
        let slot = try #require(start.exercises[0].slotID)
        let onThenOff = try #require(SwapAdv.fold(start, [
            SwapAdv.swap(0, to: 1, program: true, SwapAdv.replacement()),
            SwapAdv.swap(0, to: 2, program: false, SwapAdv.replacement())
        ]))
        #expect(onThenOff.programUpdates.isEmpty)
        let offThenOn = try #require(SwapAdv.fold(start, [
            SwapAdv.swap(0, to: 1, program: false),
            SwapAdv.swap(0, to: 2, program: true)
        ]))
        #expect(offThenOn.programUpdates == [slot: ExerciseID(EventBuilders.uuid(0xEE02))])
        // Swap back to the original with the toggle on: the entry names the original.
        let back = try #require(SwapAdv.fold(start, [
            SwapAdv.swap(0, to: 1, program: true),
            .exerciseSwapped(
                exerciseIndex: 0,
                exerciseID: start.exercises[0].exerciseID,
                name: "Barbell Bench Press",
                alsoUpdateProgram: true,
                replacement: nil
            )
        ]))
        #expect(back.programUpdates == [slot: start.exercises[0].exerciseID])
        var adHoc = start
        adHoc.exercises[1].slotID = nil
        let none = try #require(SwapAdv.fold(adHoc, [SwapAdv.swap(1, program: true), SwapAdv.swap(1, program: false)]))
        #expect(none.programUpdates.isEmpty)
    }

    @Test("Q2 is the sheet's rule, not the engine's: a swap after a logged set keeps that set as logged")
    func swap_afterALoggedSet_keepsTheDoneSet() throws {
        let start = SwapAdv.session()
        let log: WorkoutEvent = .setLogged(
            exerciseIndex: 0,
            setID: EventBuilders.setID(0, 0),
            weight: .pounds(185),
            reps: Reps(clamping: 5),
            doneAt: EventBuilders.start.addingTimeInterval(9)
        )
        let state = try #require(SwapAdv.fold(start, [log, SwapAdv.swap(0, SwapAdv.replacement())]))
        #expect(state.exercises[0].sets[0].weight == .pounds(185) && state.exercises[0].sets[0].isDone)
        #expect(state.exercises[0].sets[1].weight == .pounds(60))
    }

    @Test("Idempotent: the same swap twice is the swap once; a replayed duplicate key folds once")
    func swap_twice_isOnce() {
        let start = SwapAdv.session()
        let swap = SwapAdv.swap(0, program: true, SwapAdv.replacement(.kettlebell, step: .pounds(5), load: .pounds(35)))
        let once = SwapAdv.fold(start, [swap])
        let twice = SwapAdv.fold(start, [swap, swap]) == once
        #expect(twice)
        let log = EventBuilders.log(from: [.started(start), swap])
        let replayed = WorkoutEngine.replay(log + log.reversed() + [log[1]]) == once
        #expect(replayed)
    }
}
