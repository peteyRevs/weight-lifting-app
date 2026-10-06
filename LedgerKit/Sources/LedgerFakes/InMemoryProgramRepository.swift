#if DEBUG
    import Foundation
    import LedgerDomain

    /// `ProgramRepository` in memory, keeping `ProgramRepositoryContract` (LedgerTestSupport) as the GRDB
    /// repository does: a save is re-validated through the models' `init`s, ids are shared by every program
    /// (one another program holds, even deleted or dropped, is refused), weights are refused as the database's
    /// columns refuse them (`StorageBoundary`), and deletion is soft.
    ///
    /// Given an exercise store (as `InMemoryStores` gives it), `save` refuses a slot naming an exercise that store
    /// does not hold with `unknownExercise`, as the database's foreign key does (product decision #28). Without
    /// one, it checks no exercise. Only `save` checks: programs given to `init` are stored state, kept as given
    /// (like a database restored as it was).
    public final class InMemoryProgramRepository: ProgramRepository {
        struct Stored: Sendable {
            var program: Program
            var isDeleted = false
        }

        struct State: Sendable {
            var programs: [ProgramID: Stored] = [:]
            /// The program each week, day and slot id belongs to, kept after a drop or delete.
            var weekOwners: [WeekID: ProgramID] = [:]
            var dayOwners: [DayTemplateID: ProgramID] = [:]
            var slotOwners: [SlotID: ProgramID] = [:]

            var active: Program? {
                programs.values.first { !$0.isDeleted && $0.program.isActive }?.program
            }
        }

        private let state: ObservedState<State, Program?>
        private let exercises: InMemoryExerciseRepository?

        /// An empty repository, or one holding `programs`, stored in order with every check of a save but the
        /// exercise check (a program that would fail one is left out). With `exercises`, `save` refuses a slot
        /// naming an exercise that store does not hold.
        public init(programs: [Program] = [], exercises: InMemoryExerciseRepository? = nil) {
            var initial = State()
            for program in programs {
                // A seed that fails validation is a fixture bug, which `FixturesTests` catches; the store
                // then starts without it.
                try? Self.store(program, in: &initial, exercises: nil)
            }
            state = ObservedState(initial)
            self.exercises = exercises
        }

        public func active() async throws -> Program? {
            state.read(\.active)
        }

        public func save(_ program: Program) async throws {
            try state.write { current in try Self.store(program, in: &current, exercises: exercises) }
        }

        /// The read, the change and the save in one write, under the lock a workout's save takes
        /// (`writeSave`), so neither can come between the other's steps. The result is stored as `save`
        /// stores it, with its checks in its order, after the id check, and read back; when anything throws,
        /// the state stays as it was and no stream yields. `change` runs under the lock: it must not call this
        /// store, whose lock is not re-entrant.
        ///
        /// A task that is already cancelled throws `CancellationError` before anything is read, as the
        /// database's write does before it starts and while it waits. Nothing here suspends, so a task
        /// cancelled later stores its change whole, where the database rolls back.
        public func update(_ id: ProgramID, _ change: @Sendable (Program) throws -> Program) async throws -> Program {
            try Task.checkCancellation()
            return try state.write { current in
                guard let stored = current.programs[id], !stored.isDeleted else {
                    throw RepositoryError.missingRow("program \(id.rawValue.uuidString)")
                }
                let changed = try change(stored.program)
                guard changed.id == id else {
                    throw RepositoryError.duplicateIdentifier("program \(changed.id.rawValue.uuidString)")
                }
                try Self.store(changed, in: &current, exercises: exercises)
                return current.programs[id]?.program ?? changed
            }
        }

        public func setActive(_ id: ProgramID) async throws {
            try state.write { current throws(RepositoryError) in
                guard let stored = current.programs[id], !stored.isDeleted else {
                    throw .missingRow("program \(id.rawValue.uuidString)")
                }
                for key in current.programs.keys {
                    current.programs[key]?.program.isActive = key == id
                }
            }
        }

        public func delete(_ id: ProgramID) async throws {
            state.write { current in
                current.programs[id]?.isDeleted = true
                current.programs[id]?.program.isActive = false
            }
        }

        public func observeActive() -> AsyncStream<Program?> {
            state.observe(\.active)
        }

        /// What `WorkoutRepository.materialize` writes to the programs, in one step, so no reader of this store
        /// sees half of a save: the misses of its `slotUpdates`, then its workout's program updates.
        func writeSave(misses slots: [Slot], exercises updates: [SlotID: ExerciseID], inProgram program: ProgramID?) {
            guard !slots.isEmpty || !updates.isEmpty else {
                return
            }
            state.write { current in
                Self.writeMisses(of: slots, in: &current)
                if let program, var stored = current.programs[program], !stored.isDeleted {
                    writeExercises(updates, in: &stored.program)
                    current.programs[program] = stored
                }
            }
        }

        /// `slotUpdates` (rule 13): each live slot listed takes the listed misses, whole; a slot that is not
        /// stored is skipped.
        private static func writeMisses(of slots: [Slot], in state: inout State) {
            let misses = Dictionary(slots.map { ($0.id, $0.misses) }) { _, last in last }
            for (id, stored) in state.programs where !stored.isDeleted {
                var program = stored.program
                for day in program.days.indices {
                    for index in program.days[day].slots.indices {
                        if let written = misses[program.days[day].slots[index].id] {
                            program.days[day].slots[index].misses = written
                        }
                    }
                }
                state.programs[id]?.program = program
            }
        }

        /// Program updates (decision #13): each slot of `program` that `updates` names takes the listed
        /// exercise, and nothing else of it changes. As in the database, only a live slot of the workout's own
        /// program is touched (the caller passes none for an ad-hoc workout, or a program that is deleted or
        /// not stored), and only by an exercise the exercise store holds, when there is one to ask; every other
        /// entry is skipped.
        private func writeExercises(_ updates: [SlotID: ExerciseID], in program: inout Program) {
            for day in program.days.indices {
                for index in program.days[day].slots.indices {
                    if let exercise = updates[program.days[day].slots[index].id], exercises?.holds(exercise) ?? true {
                        program.days[day].slots[index].exerciseID = exercise
                    }
                }
            }
        }
    }

    fileprivate extension InMemoryProgramRepository {
        /// Saves `program` into `state`, or throws and leaves it, checked in the order the GRDB repository meets
        /// each fault: re-validated first, then ids another program holds, then each slot's exercise (when
        /// `exercises` is given), then each row as it is written: the program's name, the weeks (a repeated id),
        /// the days (a repeated id, then each one's name and tag), the slots (a repeated id, then each one's start
        /// load and step).
        static func store(_ program: Program, in state: inout State, exercises: InMemoryExerciseRepository?) throws {
            let valid = try revalidated(program)
            let slots = valid.days.flatMap(\.slots)
            try refuseOtherProgramsIDs(of: valid, in: state)
            if let exercises, let unknown = slots.map(\.exerciseID).first(where: { !exercises.holds($0) }) {
                throw RepositoryError.unknownExercise("exercise \(unknown.rawValue.uuidString)")
            }
            try RowChecks.refuseNul(valid.name, "program.name")
            try RowChecks.refuseRepeats(valid.weeks.map(\.id), "program_week")
            try RowChecks.refuseRepeats(valid.days.map(\.id), "day_template")
            for day in valid.days {
                try RowChecks.refuseNul(day.name, "day_template.name")
                try RowChecks.refuseNul(day.tag, "day_template.tag")
            }
            try RowChecks.refuseRepeats(slots.map(\.id), "slot")
            for slot in slots {
                try slot.startLoad?.checkStorable()
                try slot.step?.checkStorable()
            }
            if valid.isActive {
                for key in state.programs.keys {
                    state.programs[key]?.program.isActive = false
                }
            }
            state.programs[valid.id] = Stored(program: valid)
            for week in valid.weeks {
                state.weekOwners[week.id] = valid.id
            }
            for day in valid.days {
                state.dayOwners[day.id] = valid.id
                for slot in day.slots {
                    state.slotOwners[slot.id] = valid.id
                }
            }
        }

        /// `program` rebuilt through `Slot.init` and `Program.init`, so a field assigned out of range throws.
        static func revalidated(_ program: Program) throws -> Program {
            let days = try program.days.map { day in
                var valid = day
                valid.slots = try day.slots.map { slot in
                    try Slot(
                        id: slot.id,
                        exerciseID: slot.exerciseID,
                        sets: slot.sets,
                        reps: slot.reps,
                        repsHi: slot.repsHi,
                        rpe: slot.rpe.value,
                        restSeconds: slot.rest.seconds,
                        progression: slot.progression,
                        startLoad: slot.startLoad,
                        step: slot.step,
                        isSupersetWithPrevious: slot.isSupersetWithPrevious,
                        dropSets: slot.dropSets,
                        misses: slot.misses
                    )
                }
                return valid
            }
            return try Program(
                id: program.id,
                name: program.name,
                startDate: program.startDate,
                weeks: program.weeks,
                days: days,
                goal: program.goal,
                daysPerWeek: program.daysPerWeek,
                isActive: program.isActive
            )
        }

        /// Throws `duplicateIdentifier` for the smallest week, then day, then slot id another program holds.
        static func refuseOtherProgramsIDs(of program: Program, in state: State) throws(RepositoryError) {
            let slots = program.days.flatMap(\.slots).map(\.id)
            try refuse(program.weeks.map(\.id), heldIn: state.weekOwners, by: program.id, "program_week")
            try refuse(program.days.map(\.id), heldIn: state.dayOwners, by: program.id, "day_template")
            try refuse(slots, heldIn: state.slotOwners, by: program.id, "slot")
        }

        static func refuse<ID: TypedIdentifier>(
            _ ids: [ID],
            heldIn owners: [ID: ProgramID],
            by program: ProgramID,
            _ table: String
        ) throws(RepositoryError) {
            let taken = ids.filter { owners[$0].map { $0 != program } ?? false }.map(\.rawValue.uuidString)
            if let first = taken.min() {
                throw .duplicateIdentifier("\(table) \(first)")
            }
        }
    }
#endif
