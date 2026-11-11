import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S8 criteria 4 to 7: a swap with a replacement swaps the exercise whole in one event; without one it
/// does what it did before S8; done sets are never touched; the toggle writes and removes the slot's entry;
/// a malformed replacement is ignored.
@Suite("WorkoutEngine · exerciseSwapped with a replacement (F10 S8)", .tags(.domain))
struct WorkoutEngineSwapTests {
    static let dumbbellBench = ExerciseID(EventBuilders.uuid(0xD8B))
    static let last = LastPerformance(date: Engine.at(-86400), sets: 3, reps: 10, load: .pounds(60))
    static let replacement = SwappedExercise(
        equipment: .dumbbell,
        step: .pounds(2.5),
        load: .pounds(60),
        lastPerformance: last
    )

    static func swap(
        _ exerciseIndex: Int = 0,
        to exerciseID: ExerciseID = dumbbellBench,
        inProgram: Bool = false,
        with replacement: SwappedExercise? = replacement
    ) -> WorkoutEvent {
        .exerciseSwapped(
            exerciseIndex: exerciseIndex,
            exerciseID: exerciseID,
            name: "Dumbbell Bench Press",
            alsoUpdateProgram: inProgram,
            replacement: replacement
        )
    }

    /// The seed session with a drop row after Bench's five working rows.
    static func withDrop() -> WorkoutState {
        var specs = EventBuilders.seedExercises
        specs[0].dropSet = true
        return EventBuilders.session(specs)
    }

    @Test("Each field the replacement brings is copied; the rest of the exercise is as it was")
    func replacement_copiesItsFields() throws {
        let live = try Engine.live()
        let (state, effects) = try Engine.run([Self.swap()])
        var expected = live.exercises[0]
        expected.exerciseID = Self.dumbbellBench
        expected.name = "Dumbbell Bench Press"
        expected.equipment = .dumbbell
        expected.step = .pounds(2.5)
        expected.lastPerformance = Self.last
        expected.targetLoad = .pounds(60)
        for index in expected.sets.indices {
            expected.sets[index].weight = .pounds(60)
        }
        let isExpected = state.exercises[0] == expected
        #expect(isExpected)
        #expect(state.exercises[0].originalExerciseID == live.exercises[0].exerciseID)
        let othersKept = Array(state.exercises.dropFirst()) == Array(live.exercises.dropFirst())
        #expect(othersKept)
        let oldSwap = try Engine.run([Self.swap(with: nil)]).effects
        #expect(effects.count == oldSwap.count, "the effects of any swap: \(effects)")
        #expect(!effects.contains {
            if case .haptic = $0 {
                true
            } else {
                false
            }
        })
    }

    @Test("Undone working, added and drop rows take the load (a drop row its 85 %); done rows keep theirs")
    func undoneRowsTakeTheLoad_doneRowsKeep() throws {
        let added = LoggedSet(
            id: SetID(EventBuilders.uuid(0xADD)), weight: .pounds(185), reps: Reps(clamping: 5), kind: .added
        )
        let (state, _) = try Engine.run([
            Engine.logged(0, 0, pounds: 185, at: 10),
            Engine.logged(0, 1, pounds: 190, at: 20),
            .setAdded(exerciseIndex: 0, set: added),
            Self.swap()
        ], on: Self.withDrop())
        let rows = state.exercises[0].sets
        let pounds: [Decimal] = [185, 190, 60, 60, 60, 50, 60] // the drop: 51 → 50 on a 2.5 lb step
        #expect(rows.map(\.weight) == pounds.map { Weight.pounds($0) })
        #expect(rows.map(\.kind) == [.working, .working, .working, .working, .working, .drop, .added])
        #expect(rows.prefix(2).allSatisfy(\.isDone) && !rows.dropFirst(2).contains(where: \.isDone))
        #expect(rows.map(\.reps.value) == Array(repeating: 5, count: 7))
    }

    @Test("A drop row's load is SessionBuilder's drop rule of the swap's load")
    func dropRow_sharesSessionBuildersRule() throws {
        let odd = SwappedExercise(equipment: .machine, step: .pounds(2.5), load: .pounds(77.5), lastPerformance: nil)
        let (state, _) = try Engine.run([Self.swap(with: odd)], on: Self.withDrop())
        let drop = try #require(state.exercises[0].sets.last)
        #expect(drop.weight == SessionBuilder.dropLoad(of: .pounds(77.5), step: .pounds(2.5)))
        #expect(drop.weight == .pounds(65)) // 65.875 → 65
    }

    @Test("Done rows are never touched by a swap, with or without a replacement, under seeded scripts")
    func doneRows_neverChange_seeded() throws {
        var random = SeededGenerator(seed: 0x5A8)
        for _ in 0 ..< 200 {
            let session = Self.withDrop()
            var events: [WorkoutEvent] = []
            for row in 0 ..< 6 where Bool.random(using: &random) {
                let pounds = Decimal(Int.random(in: 100 ... 200, using: &random))
                events.append(Engine.logged(0, row, pounds: pounds, at: 10))
            }
            let before = try Engine.run(events, on: session).state.exercises[0].sets
            let load = Weight.pounds(Decimal(Int.random(in: 0 ... 300, using: &random)))
            let swapped = Bool.random(using: &random)
                ? SwappedExercise(equipment: .cable, step: .pounds(2.5), load: load, lastPerformance: nil)
                : nil
            let after = try Engine.run(events + [Self.swap(with: swapped)], on: session).state.exercises[0].sets
            let doneKept = zip(before, after).allSatisfy { !$0.isDone || $0 == $1 }
            #expect(doneKept)
            let drop = SessionBuilder.dropLoad(of: load, step: .pounds(2.5))
            let undoneTake = zip(before, after).allSatisfy { (old: LoggedSet, new: LoggedSet) -> Bool in
                guard !old.isDone, swapped != nil else {
                    return old.isDone || old == new
                }
                return new.weight == (new.kind == .drop ? drop : load)
            }
            #expect(undoneTake)
        }
    }

    @Test("Without a replacement a swap does what it did before S8: the id and the name only")
    func noReplacement_isTheOldSwap() throws {
        let live = try Engine.live()
        let (state, _) = try Engine.run([Self.swap(with: nil)])
        var expected = live.exercises[0]
        expected.exerciseID = Self.dumbbellBench
        expected.name = "Dumbbell Bench Press"
        let isExpected = state.exercises[0] == expected
        #expect(isExpected)
    }

    @Test("The toggle: on records the slot's entry, off removes it, an exercise with no slot records none")
    func toggle_writesAndRemoves() throws {
        let slot = try #require(try Engine.live().exercises[0].slotID)
        let switchedOn = try Engine.run([Self.swap(inProgram: true)]).state
        #expect(switchedOn.programUpdates == [slot: Self.dumbbellBench])
        let incline = ExerciseID(EventBuilders.uuid(0x1C))
        let switchedOff = try Engine.run([Self.swap(inProgram: true), Self.swap(to: incline)]).state
        #expect(switchedOff.programUpdates.isEmpty)
        let otherSlot = try Engine.run([Self.swap(1, inProgram: true), Self.swap(0)]).state
        #expect(otherSlot.programUpdates.count == 1 && otherSlot.programUpdates[slot] == nil)
        var adHoc = EventBuilders.seedSession()
        adHoc.exercises[0].slotID = nil
        #expect(try Engine.run([Self.swap(inProgram: true)], on: adHoc).state.programUpdates.isEmpty)
    }

    @Test("An index out of range changes nothing")
    func outOfRange_changesNothing() throws {
        let live = try Engine.live()
        for index in [-1, 5, Int.max] {
            let unchanged = try Engine.run([Self.swap(index, inProgram: true)]).state == live
            #expect(unchanged)
        }
    }
}

/// The superset member, the malformed replacements and the model oracle.
extension WorkoutEngineSwapTests {
    /// Each a replacement that `isWellFormed` refuses.
    static let malformed: [SwappedExercise] = [
        SwappedExercise(equipment: .dumbbell, step: .zero, load: .pounds(60), lastPerformance: nil),
        SwappedExercise(equipment: .dumbbell, step: .pounds(-2.5), load: .pounds(60), lastPerformance: nil),
        SwappedExercise(equipment: .dumbbell, step: .pounds(2.5), load: .pounds(-0.5), lastPerformance: nil),
        SwappedExercise(equipment: .dumbbell, step: .pounds(2.5), load: .pounds(60), lastPerformance: lastDone(.nan)),
        // G2-1: weights a store cannot keep, and a drop that would leave the Int64 range.
        SwappedExercise(equipment: .dumbbell, step: grams("0.000000001"), load: .zero, lastPerformance: nil),
        SwappedExercise(equipment: .dumbbell, step: .pounds(2.5), load: .pounds(185.125), lastPerformance: nil),
        SwappedExercise(equipment: .dumbbell, step: .pounds(2.5), load: grams("1e30"), lastPerformance: nil),
        SwappedExercise(equipment: .dumbbell, step: grams("1e-120"), load: grams("1e120"), lastPerformance: nil),
        SwappedExercise(
            equipment: .dumbbell, step: grams("313594649253.0062"), load: grams("922337203685.4775807"),
            lastPerformance: nil
        ),
        SwappedExercise(equipment: .cable, step: .pounds(2.5), load: .pounds(60), lastPerformance: lastDone(-.infinity))
    ]

    static func grams(_ text: String) -> Weight {
        Weight(grams: Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? .nan)
    }

    static func lastDone(_ seconds: TimeInterval) -> LastPerformance {
        LastPerformance(date: Date(timeIntervalSinceReferenceDate: seconds), sets: 3, reps: 10, load: .pounds(60))
    }

    @Test("A superset member swaps alone: its flag, the block's rounds and its partner are unchanged")
    func supersetMember_flagKept() throws {
        let session = EventBuilders.session(EventBuilders.supersetExercises)
        let live = try Engine.live(session)
        let state = try Engine.run([Self.swap(1)], on: session).state
        #expect(state.exercises[1].isSupersetWithPrevious)
        #expect(state.exercises[0] == live.exercises[0])
        #expect(SupersetRounds.blocks(in: state.exercises) == SupersetRounds.blocks(in: live.exercises))
        #expect(state.exercises[1].rest == live.exercises[1].rest)
    }

    @Test(
        "A malformed replacement is ignored: a step not above zero, a load below zero, a last date not finite",
        arguments: malformed
    )
    func malformed_isIgnored(_ replacement: SwappedExercise) throws {
        let live = try Engine.live()
        let envelope = Engine.envelope(Self.swap(inProgram: true, with: replacement), 10, seq: 2)
        #expect(!envelope.isWellFormed)
        let (state, effects) = WorkoutEngine.reduce(live, envelope)
        let unchanged = state == live
        #expect(unchanged && effects.isEmpty)
        let oracleIgnores = ModelOracle.replay([Engine.started(), envelope]) == live
        #expect(oracleIgnores)
    }

    @Test("A zero load and a well-formed history are accepted")
    func edgeValues_areWellFormed() {
        let zero = SwappedExercise(equipment: .bodyweight, step: .pounds(2.5), load: .zero, lastPerformance: Self.last)
        #expect(Engine.envelope(Self.swap(with: zero), 10, seq: 2).isWellFormed)
        #expect(Engine.envelope(Self.swap(with: nil), 10, seq: 2).isWellFormed)
    }

    @Test("The engine and the model oracle agree on swaps with and without a replacement")
    func oracle_agrees() {
        let log = [Engine.started(Self.withDrop())] + EventBuilders.log(
            from: [
                Engine.logged(0, 0, at: 10),
                Self.swap(inProgram: true),
                Self.swap(1, inProgram: true, with: nil),
                Self.swap(0, to: ExerciseID(EventBuilders.uuid(0x1C)))
            ],
            firstSeq: 2,
            startingAt: Engine.at(10)
        )
        let engine = WorkoutEngine.replay(log)
        let oracle = ModelOracle.replay(log)
        let agree = engine == oracle
        #expect(agree)
        #expect(engine?.programUpdates.count == 1)
    }
}
