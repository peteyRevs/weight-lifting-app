import Foundation
import LedgerDomain

/// What a save does beyond history, to the stores one database links to it (F10 S3 criteria 1 to 4 and 6): the
/// program changes of `programUpdates`, and the workout's event log dropped on request, all of it or nothing.
/// Separate from `clauses` because F05's in-memory oracle (`HistoryModel`) models neither a slot's exercise nor
/// the log: the GRDB repository and LedgerFakes' linked `InMemoryWorkoutRepository` run this list too.
///
/// A clause that fails names what differs in a line (`Program.difference(from:)`, a count, a flag), never a
/// whole program or workout: a failure's text goes into the result bundle for every case.
public extension WorkoutRepositoryContract {
    static let linkedClauses: [Clause] = [
        Clause(
            "programUpdates set the exercise of stored slots of the workout's own program, and nothing else of it",
            appliesProgramUpdates
        ),
        Clause(
            "an update of an ad-hoc workout, or naming an unstored slot, another program's slot or an unstored "
                + "exercise, is skipped; the workout and the other updates are stored",
            skipsWhatCannotBeApplied
        ),
        Clause("materialising the workout again changes nothing, the program included", programUpdatesTwice),
        Clause(
            "observeActive emits the program as a save left it, and nothing for a save that changes no program",
            observersHearTheSave
        ),
        Clause(
            "droppingLog drops that workout's log with the save, and no other's; again, with it gone, changes nothing",
            dropsTheLog
        ),
        Clause(
            "a save that is refused changes nothing: no workout, no miss, no program change, and the log whole",
            refusedSaveChangesNothing
        )
    ]
}

public extension Program {
    /// What differs between this program and `expected`, in a line, or `nil`: its slots' exercises and misses
    /// by name, anything else in a word. For a test to print in place of both programs.
    func difference(from expected: Program) -> String? {
        guard self != expected else {
            return nil
        }
        let wanted = Dictionary(expected.days.flatMap(\.slots).map { ($0.id, $0) }) { first, _ in first }
        var lines: [String] = []
        for (day, template) in days.enumerated() {
            for (position, slot) in template.slots.enumerated() {
                guard let other = wanted[slot.id] else {
                    lines.append("day \(day) slot \(position) is not expected")
                    continue
                }
                if slot.exerciseID != other.exerciseID {
                    lines.append("day \(day) slot \(position): exercise \(slot.exerciseID.rawValue)")
                }
                if slot.misses != other.misses {
                    lines.append("day \(day) slot \(position): misses \(slot.misses.sorted())")
                }
            }
        }
        guard !lines.isEmpty else {
            return "differs outside its slots' exercises and misses"
        }
        return lines.prefix(4).joined(separator: "; ")
    }
}

public extension WorkoutRepositoryContract {
    /// The contract workout, from week 3 of `program`'s first day.
    static func workout(of program: Program, number: Int = 0) -> WorkoutState {
        var workout = workout(number: number)
        workout.source = WorkoutSource(programID: program.id, weekIndex: 2, dayTemplateID: program.days[0].id)
        return workout
    }

    /// An exercise of the contract's six that `slot` does not hold.
    static func replacement(for slot: Slot) -> ExerciseID {
        let held = exercises.firstIndex { $0.id == slot.exerciseID } ?? 0
        return exercises[(held + 1) % exercises.count].id
    }

    /// A log of `count` envelopes for `workout`: the repository never reads one, so what they hold is no matter.
    static func log(of workout: WorkoutID, count: Int) -> [EventEnvelope] {
        EventBuilders.log(from: Array(repeating: .restSkipped, count: count), workoutID: workout)
    }
}

extension WorkoutRepositoryContract {
    /// `nil` when `stores`' program `id` is `expected`, else how it differs. Makes it the active one to read it.
    static func expectProgram(_ expected: Program, _ what: String, in stores: HistoryStores) async throws -> String? {
        try await stores.programs.setActive(expected.id)
        guard let stored = try await stores.programs.active() else {
            return "\(what): no active program"
        }
        var wanted = expected
        wanted.isActive = true
        return stored.difference(from: wanted).map { "\(what): \($0)" }
    }

    static func appliesProgramUpdates(_ stores: HistoryStores) async throws -> String? {
        let program = try ProgramRepositoryContract.program()
        try await stores.programs.save(program)
        var workout = workout(of: program)
        let (first, late) = (program.days[0].slots[0], program.days[2].slots[3])
        workout.programUpdates = [first.id: replacement(for: first), late.id: replacement(for: late)]
        var expected = program
        expected.days[0].slots[0].exerciseID = replacement(for: first)
        expected.days[2].slots[3].exerciseID = replacement(for: late)
        // The misses are written as before, on a slot that is swapped too and on one that is not.
        expected.days[0].slots[0].misses = [2, 5]
        expected.days[1].slots[1].misses = []
        try await stores.materialize(workout, slotUpdates: [expected.days[0].slots[0], expected.days[1].slots[1]])
        return try await ContractCheck.first(
            expectProgram(expected, "the program after the save", in: stores),
            ContractCheck.expect(stores.workouts.workout(id: workout.id) == stored(workout), true, "it is stored")
        )
    }

    static func skipsWhatCannotBeApplied(_ stores: HistoryStores) async throws -> String? {
        var own = try ProgramRepositoryContract.program()
        let other = try ProgramRepositoryContract.program(number: 1, isActive: false)
        try await stores.programs.save(own)
        try await stores.programs.save(other)
        let dropped = own.days[3].slots.removeLast() // a slot the program no longer has
        try await stores.programs.save(own)
        var workout = workout(of: own)
        let (applied, unknown) = (own.days[0].slots[0], own.days[1].slots[0])
        workout.programUpdates = [
            applied.id: replacement(for: applied),
            other.days[0].slots[0].id: replacement(for: other.days[0].slots[0]),
            SlotID(EventBuilders.uuid(0x73)): exercises[5].id,
            dropped.id: replacement(for: dropped),
            unknown.id: ExerciseID(EventBuilders.uuid(0x404))
        ]
        var adHoc = Self.workout(number: 2, endedAt: EventBuilders.start.addingTimeInterval(3600))
        adHoc.programUpdates = [own.days[0].slots[1].id: replacement(for: own.days[0].slots[1])]
        var stranger = Self.workout(of: other, number: 3) // another program's workout names this program's slot
        stranger.endedAt = EventBuilders.start.addingTimeInterval(7200)
        stranger.programUpdates = [own.days[0].slots[2].id: replacement(for: own.days[0].slots[2])]
        for saved in [workout, adHoc, stranger] {
            try await stores.materialize(saved)
        }
        var expected = own
        expected.days[0].slots[0].exerciseID = replacement(for: applied)
        return try await ContractCheck.first(
            ContractCheck.expect(stores.workouts.recent(limit: 10).count, 3, "the workouts stored"),
            expectProgram(expected, "the workout's program", in: stores),
            expectProgram(other, "the other program", in: stores)
        )
    }

    static func programUpdatesTwice(_ stores: HistoryStores) async throws -> String? {
        let program = try ProgramRepositoryContract.program()
        try await stores.programs.save(program)
        var workout = workout(of: program)
        let (first, same) = (program.days[0].slots[0], program.days[1].slots[2])
        // The second entry names the exercise its slot already holds.
        workout.programUpdates = [first.id: replacement(for: first), same.id: same.exerciseID]
        var expected = program
        expected.days[0].slots[0].exerciseID = replacement(for: first)
        expected.days[0].slots[0].misses = [4]
        let slots = [expected.days[0].slots[0]]
        try await stores.materialize(workout, slotUpdates: slots)
        let once = try await expectProgram(expected, "the program after one save", in: stores)
        try await stores.materialize(workout, slotUpdates: slots)
        _ = try await stores.workouts.materialize(workout, slotUpdates: slots, droppingLog: true)
        return try await ContractCheck.first(
            once,
            expectProgram(expected, "the program after three saves", in: stores),
            ContractCheck.expect(stores.workouts.recent(limit: 10) == [stored(workout)], true, "it is stored once")
        )
    }

    /// A screen that watches the active program (Today's next session) is told of the save's misses and swap,
    /// and of nothing when a workout is saved again. A stream keeps its newest value only, so this cannot show
    /// whether a store ever held half of a save: only a reader racing the save could.
    static func observersHearTheSave(_ stores: HistoryStores) async throws -> String? {
        let program = try ProgramRepositoryContract.program()
        try await stores.programs.save(program)
        var workout = workout(of: program)
        let slot = program.days[0].slots[0]
        workout.programUpdates = [slot.id: replacement(for: slot)]
        var expected = program
        expected.days[0].slots[0].exerciseID = replacement(for: slot)
        expected.days[0].slots[0].misses = [1, 3]
        var values = stores.programs.observeActive().makeAsyncIterator()
        let first = await values.next()
        try await stores.materialize(workout, slotUpdates: [expected.days[0].slots[0]])
        let second = await values.next()
        // A write that changes no program emits nothing: the next value is the next change.
        try await stores.materialize(workout, slotUpdates: [expected.days[0].slots[0]])
        var later = expected
        later.days[1].slots[0].misses = [6]
        try await stores.programs.save(later)
        let third = await values.next()
        func line(_ value: Program??, _ wanted: Program, _ what: String) -> String? {
            guard let emitted = value ?? nil else {
                return "\(what): no program"
            }
            return emitted.difference(from: wanted).map { "\(what): \($0)" }
        }
        return ContractCheck.first(
            line(first, program, "the first value"),
            line(second, expected, "the value after the save"),
            line(third, later, "the value after the next change")
        )
    }

    static func dropsTheLog(_ stores: HistoryStores) async throws -> String? {
        guard let events = stores.events else {
            return "the stores hold no event log"
        }
        let workout = workout(number: 1)
        let other = Seeders.workoutID(2)
        _ = try await events.append(log(of: workout.id, count: 3) + log(of: other, count: 2))
        let kept = try await stores.workouts.materialize(workout, slotUpdates: [], droppingLog: false)
        let logsAfterKeeping = try await Set(events.uncompactedWorkoutIDs())
        let dropped = try await stores.workouts.materialize(workout, slotUpdates: [], droppingLog: true)
        let logsAfterDropping = try await events.uncompactedWorkoutIDs()
        let again = try await stores.workouts.materialize(workout, slotUpdates: [], droppingLog: true)
        return try await ContractCheck.first(
            ContractCheck.expect(kept, false, "the answer when the log was not to be dropped"),
            ContractCheck.expect(logsAfterKeeping, [workout.id, other], "the logs after a save that keeps them"),
            ContractCheck.expect(dropped, true, "the answer when the log was dropped"),
            ContractCheck.expect(logsAfterDropping, [other], "the logs after the save that drops one"),
            ContractCheck.expect(again, true, "the answer when the log was already gone"),
            ContractCheck.expect(events.envelopes(for: workout.id).count, 0, "the envelopes left of the workout"),
            ContractCheck.expect(events.highestSeq(for: workout.id, device: EventBuilders.phone), nil, "its seq"),
            ContractCheck.expect(events.envelopes(for: other).count, 2, "the envelopes of the other workout"),
            ContractCheck.expect(stores.workouts.recent(limit: 10) == [workout], true, "the workout is stored once")
        )
    }

    static func refusedSaveChangesNothing(_ stores: HistoryStores) async throws -> String? {
        guard let events = stores.events else {
            return "the stores hold no event log"
        }
        let program = try ProgramRepositoryContract.program()
        try await stores.programs.save(program)
        var refused = workout(of: program)
        let slot = program.days[0].slots[0]
        refused.programUpdates = [slot.id: replacement(for: slot)]
        refused.exercises[4].name = "Lat\u{0}Pulldown" // refused after every other row of the workout is written
        var missed = slot
        missed.misses = [2, 5]
        var live = workout(of: program)
        live.phase = .live
        live.programUpdates = refused.programUpdates
        _ = try await events.append(log(of: refused.id, count: 3))
        let unnamed = await ContractCheck.expectError(RepositoryError.nulInText("workout_exercise.name")) {
            _ = try await stores.workouts.materialize(refused, slotUpdates: [missed], droppingLog: true)
        }
        let unfinished = await ContractCheck.expectError(RepositoryError.notFinished(key("workout", live.id))) {
            _ = try await stores.workouts.materialize(live, slotUpdates: [missed], droppingLog: true)
        }
        return try await ContractCheck.first(
            unnamed,
            unfinished,
            ContractCheck.expect(stores.workouts.recent(limit: 10).count, 0, "the workouts after the refused saves"),
            expectProgram(program, "the program after the refused saves", in: stores),
            ContractCheck.expect(events.envelopes(for: refused.id).count, 3, "the envelopes of the workout's log")
        )
    }
}
