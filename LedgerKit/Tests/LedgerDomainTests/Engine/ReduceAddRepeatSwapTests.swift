import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

@Suite("WorkoutEngine · setAdded, allSetsRepeated, exerciseSwapped (rules 6–8)", .tags(.domain))
struct ReduceAddRepeatSwapTests {
    private let newSetID = SetID(EventBuilders.uuid(0x5001))
    private let dip = ExerciseID(EventBuilders.uuid(0xE101))

    private func added(
        _ id: SetID,
        to exerciseIndex: Int = 0,
        kind: SetKind = .added,
        done: Bool = false
    ) -> WorkoutEvent {
        let set = LoggedSet(
            id: id,
            weight: .pounds(185),
            reps: Reps(clamping: 5),
            kind: kind,
            doneAt: done ? Engine.at(1) : nil
        )
        return .setAdded(exerciseIndex: exerciseIndex, set: set)
    }

    @Test("Rule 6: an added set is appended at the end as an undone .added row, and totalSets grows")
    func setAdded_appendsUndoneAddedRow() throws {
        let (state, _) = try Engine.run([added(newSetID, kind: .drop, done: true)])
        let rows = state.exercises[0].sets
        #expect(rows.count == 6)
        #expect(rows.last == LoggedSet(id: newSetID, weight: .pounds(185), reps: Reps(clamping: 5), kind: .added))
        #expect(state.totalSets == 19)
    }

    @Test("Rule 6: setAdded is idempotent by set ID across the whole workout")
    func setAdded_isIdempotentBySetID() throws {
        let once = try Engine.run([added(newSetID)]).state
        #expect(try Engine.run([added(newSetID), added(newSetID)]).state == once)
        #expect(try Engine.run([added(newSetID), added(newSetID, to: 2)]).state == once)
        #expect(try Engine.run([added(Engine.set(3, 0))]).state == (Engine.live()))
        #expect(try Engine.run([added(newSetID, to: 5)]).state == (Engine.live()))
    }

    @Test("Rule 7: repeat-last writes weight and reps into every row, drop rows included, and keeps done flags")
    func allSetsRepeated_writesEveryRow() throws {
        let session = EventBuilders.session([
            EventBuilders.ExerciseSpec("Curl", .barbell, sets: 2, reps: 12, pounds: 75, restSeconds: 60, dropSet: true)
        ])
        let (state, _) = try Engine.run([
            Engine.logged(0, 0, pounds: 75, reps: 12, at: 10),
            .allSetsRepeated(exerciseIndex: 0, weight: .pounds(70), reps: Reps(clamping: 10))
        ], on: session)
        let rows = state.exercises[0].sets
        #expect(rows.allSatisfy { $0.weight == .pounds(70) && $0.reps.value == 10 })
        #expect(rows.map(\.isDone) == [true, false, false])
        #expect(rows.map(\.kind) == [.working, .working, .drop])
        #expect(try Engine.run([.allSetsRepeated(exerciseIndex: 5, weight: .zero, reps: .one)])
            .state == (Engine.live()))
    }

    @Test("Rule 8: a swap replaces the exercise ID and name and keeps sets, rest, step, RPE and targets")
    func exerciseSwapped_replacesIdentityOnly() throws {
        let live = try Engine.live()
        let (state, _) = try Engine.run([
            .exerciseSwapped(exerciseIndex: 1, exerciseID: dip, name: "Weighted Dip", alsoUpdateProgram: false)
        ])
        var expected = live.exercises[1]
        expected.exerciseID = dip
        expected.name = "Weighted Dip"
        #expect(state.exercises[1] == expected)
        #expect(state.exercises[1].originalExerciseID == live.exercises[1].exerciseID)
        #expect(state.programUpdates.isEmpty)
        let outOfRange = WorkoutEvent.exerciseSwapped(
            exerciseIndex: 5,
            exerciseID: dip,
            name: "Dip",
            alsoUpdateProgram: true
        )
        #expect(try Engine.run([outOfRange]).state == live)
    }

    @Test("Criterion 12: a swap that also updates the program is carried through finish for F05")
    func criterion12_programUpdate_survivesFinish() throws {
        let live = try Engine.live()
        let slotID = try #require(live.exercises[0].slotID)
        let (state, effects) = try Engine.run([
            .exerciseSwapped(exerciseIndex: 0, exerciseID: dip, name: "Weighted Dip", alsoUpdateProgram: true),
            .finished(endedAt: Engine.at(600))
        ])
        #expect(state.phase == .finished)
        #expect(state.programUpdates == [slotID: dip])
        #expect(effects.contains(.materialize(state)))
    }

    @Test("The latest program swap per slot wins; a later one-off swap leaves it; an ad-hoc exercise records none")
    func programUpdates_latestPerSlot() throws {
        let row = ExerciseID(EventBuilders.uuid(0xE102))
        let slotID = try #require(try Engine.live().exercises[0].slotID)
        let (state, _) = try Engine.run([
            .exerciseSwapped(exerciseIndex: 0, exerciseID: dip, name: "Dip", alsoUpdateProgram: true),
            .exerciseSwapped(exerciseIndex: 0, exerciseID: row, name: "Row", alsoUpdateProgram: true),
            .exerciseSwapped(exerciseIndex: 0, exerciseID: dip, name: "Dip", alsoUpdateProgram: false)
        ])
        #expect(state.programUpdates == [slotID: row])
        #expect(state.exercises[0].exerciseID == dip)

        var adHoc = EventBuilders.seedSession()
        adHoc.exercises[0].slotID = nil
        let swapped = try Engine.run(
            [.exerciseSwapped(exerciseIndex: 0, exerciseID: dip, name: "Dip", alsoUpdateProgram: true)],
            on: adHoc
        )
        #expect(swapped.state.programUpdates.isEmpty)
        #expect(swapped.state.exercises[0].exerciseID == dip)
    }
}
