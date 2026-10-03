#if DEBUG
    import Foundation
    import LedgerDomain

    /// `ProgramRepository` in memory, keeping `ProgramRepositoryContract` (LedgerTestSupport) as the GRDB
    /// repository does: a save is re-validated through the models' `init`s, ids are shared by every program
    /// (one another program holds, even deleted or dropped, is refused), and deletion is soft. It does not check
    /// that slots name stored exercises, which only a database's foreign key can do.
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

        /// An empty repository, or one holding `programs`, saved in order. A program that would fail a save is
        /// left out.
        public init(programs: [Program] = []) {
            var initial = State()
            for program in programs {
                // A seed that fails validation is a fixture bug, which `FixturesTests` catches; the store
                // then starts without it.
                try? Self.store(program, in: &initial)
            }
            state = ObservedState(initial)
        }

        public func active() async throws -> Program? {
            state.read(\.active)
        }

        public func save(_ program: Program) async throws {
            try state.write { current in try Self.store(program, in: &current) }
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

        /// `WorkoutRepository.materialize`'s `slotUpdates` (rule 13): each live slot listed takes the listed
        /// misses, whole; a slot that is not stored is skipped.
        func writeMisses(of slots: [Slot]) {
            guard !slots.isEmpty else {
                return
            }
            let misses = Dictionary(slots.map { ($0.id, $0.misses) }) { _, last in last }
            state.write { current in
                for (id, stored) in current.programs where !stored.isDeleted {
                    var program = stored.program
                    for day in program.days.indices {
                        for index in program.days[day].slots.indices {
                            if let written = misses[program.days[day].slots[index].id] {
                                program.days[day].slots[index].misses = written
                            }
                        }
                    }
                    current.programs[id]?.program = program
                }
            }
        }
    }

    fileprivate extension InMemoryProgramRepository {
        /// Saves `program` into `state`, or throws and leaves it: re-validated first, then its ids checked, then
        /// its text, as the GRDB repository checks them.
        static func store(_ program: Program, in state: inout State) throws {
            let valid = try revalidated(program)
            try refuseOtherProgramsIDs(of: valid, in: state)
            try refuseNul(valid.name, "program.name")
            try refuseRepeats(valid.weeks.map(\.id), "program_week")
            try refuseRepeats(valid.days.map(\.id), "day_template")
            for day in valid.days {
                try refuseNul(day.name, "day_template.name")
                try refuseNul(day.tag, "day_template.tag")
            }
            try refuseRepeats(valid.days.flatMap(\.slots).map(\.id), "slot")
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

        static func refuseRepeats(_ ids: [some TypedIdentifier], _ table: String) throws(RepositoryError) {
            var seen = Set<UUID>()
            if let repeated = ids.first(where: { !seen.insert($0.rawValue).inserted }) {
                throw .duplicateIdentifier("\(table) \(repeated.rawValue.uuidString)")
            }
        }

        static func refuseNul(_ text: String, _ column: String) throws(RepositoryError) {
            if text.unicodeScalars.contains("\0") {
                throw .nulInText(column)
            }
        }
    }
#endif
