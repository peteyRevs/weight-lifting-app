import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport

/// F10 S3 adversarial round 1: the stores one save reaches, behind their protocols. The database's five over
/// one queue, or LedgerFakes' linked ones: a test runs on both and compares them with each other and with
/// `LinkedModel`, written here from the brief's criteria 1 to 4.
struct LinkedStores: Sendable {
    enum Kind: String, Sendable, CaseIterable, CustomStringConvertible {
        case database, memory

        var description: String {
            rawValue
        }
    }

    let kind: Kind
    let exercises: any ExerciseRepository
    let programs: any ProgramRepository
    let workouts: any WorkoutRepository
    let events: any WorkoutEventStore
    /// The database beneath, for a dump of its tables or a trigger; `nil` for the fakes.
    let queue: DatabaseQueue?
    let clock: S2Kit.Clock

    /// Stores holding `LinkedFixture.exercises`, program 2 and, active, program 1.
    static func make(_ kind: Kind) async throws -> LinkedStores {
        let time = S2Kit.Clock()
        let built = try [LinkedFixture.program(2), LinkedFixture.program(1)]
        switch kind {
        case .database:
            let database = try LedgerDatabase.inMemory()
            let stores = LedgerStores(database, deviceID: S3Kit.device, now: { time.now })
            try await stores.exercises.seedIfNeeded(LinkedFixture.exercises, version: 1)
            for program in built {
                try await stores.programs.save(program)
            }
            return LinkedStores(
                kind: kind, exercises: stores.exercises, programs: stores.programs, workouts: stores.workouts,
                events: stores.events, queue: database, clock: time
            )
        case .memory:
            let seed = InMemoryStores.Seed(catalog: LinkedFixture.exercises, catalogVersion: 1, programs: built)
            let stores = InMemoryStores(seed: seed, now: { time.now })
            return LinkedStores(
                kind: kind, exercises: stores.exercises, programs: stores.programs, workouts: stores.workouts,
                events: stores.events, queue: nil, clock: time
            )
        }
    }

    /// Program `number` as stored, read by making it the active one for a moment; `nil` when it is deleted.
    func program(_ number: Int) async throws -> Program? {
        let wanted = S2Kit.programID(number)
        let active = try await programs.active()
        if active?.id == wanted {
            return active
        }
        do {
            try await programs.setActive(wanted)
        } catch RepositoryError.missingRow {
            return nil
        }
        let read = try await programs.active()
        if let active {
            try await programs.setActive(active.id)
        }
        return read
    }

    /// How many envelopes the log of `workout` holds.
    func logCount(_ workout: WorkoutState) async throws -> Int {
        try await events.envelopes(for: workout.id).count
    }

    /// How a save ended: whether the log went with it, or the error.
    func save(_ workout: WorkoutState, slots: [Slot] = [], droppingLog: Bool) async -> String {
        do {
            return try await "\(workouts.materialize(workout, slotUpdates: slots, droppingLog: droppingLog))"
        } catch {
            return "\(error)"
        }
    }

    /// Every row of every table of the database, metadata included, as text by table: for "nothing changed".
    func dump() async throws -> [String: [String]] {
        guard let queue else {
            return [:]
        }
        return try await queue.read { database in
            let tables = try String.fetchAll(
                database,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
            )
            var rows: [String: [String]] = [:]
            for table in tables {
                rows[table] = try Row.fetchAll(database, sql: "SELECT * FROM \(table) ORDER BY rowid")
                    .map(\.description)
            }
            return rows
        }
    }

    /// The tables whose rows differ between two dumps, with how many rows each held: a line, never the rows.
    static func difference(_ before: [String: [String]], _ after: [String: [String]]) -> String? {
        let changed = Set(before.keys).union(after.keys).sorted().filter { before[$0] != after[$0] }
        guard !changed.isEmpty else {
            return nil
        }
        return changed.map { table in
            let was = before[table] ?? []
            let now = after[table] ?? []
            let moved = zip(was, now).count(where: { $0 != $1 }) + abs(was.count - now.count)
            return "\(table): \(was.count) rows, then \(now.count), \(moved) differ"
        }.joined(separator: "; ")
    }
}

/// What the suites save: two programs of two days and three slots each over eight exercises, and finished
/// workouts numbered so that no two share an id or a date.
enum LinkedFixture {
    static let exercises = S2Kit.slotExercises
    /// An exercise no store holds.
    static let unknownExercise = ExerciseID(S3Kit.uuid(0xE, 404))
    /// A slot no program ever held.
    static let unknownSlot = SlotID(S3Kit.uuid(0x5, 404))

    static func program(_ number: Int) throws -> Program {
        try S2Kit.program(number, weeks: 3, days: 2, slotsPerDay: 3, isActive: number == 1)
    }

    /// Slot `index` (0 to 5, day by day) of program `number` as the fixture builds it.
    static func slot(_ index: Int, of number: Int = 1) throws -> Slot {
        try program(number).days.flatMap(\.slots)[index]
    }

    /// A stored exercise that `slot` does not hold.
    static func other(than slot: Slot, offset: Int = 1) -> ExerciseID {
        let ids = exercises.map(\.id)
        let index = ids.firstIndex(of: slot.exerciseID) ?? 0
        return ids[(index + offset) % ids.count]
    }

    /// Finished workout `number`, of week 1 of program `program`'s first day (or of no program), asking for
    /// `updates` to its program.
    static func workout(
        _ number: Int,
        ofProgram program: Int? = 1,
        updates: [SlotID: ExerciseID] = [:]
    ) -> WorkoutState {
        var workout = S3Kit.workout(number, endedAt: S3Kit.now.addingTimeInterval(Double(number) * 7200), [
            S3Kit.RowSpec(S3Kit.bench, [S3Kit.set(185, 5), S3Kit.set(185, 4)]),
            S3Kit.RowSpec(S3Kit.squat, [S3Kit.set(225, 5), S3Kit.set(225, 5, done: false)])
        ])
        workout.source = program.map {
            WorkoutSource(programID: S2Kit.programID($0), weekIndex: 1, dayTemplateID: S2Kit.dayID($0 * 100))
        }
        workout.programUpdates = updates
        return workout
    }

    /// A log of `count` envelopes for `workout`. A save never reads one, so what they hold is no matter.
    static func log(of workout: WorkoutState, count: Int = 4) -> [EventEnvelope] {
        EventBuilders.log(
            from: (0 ..< count).map { .exerciseSelected(exerciseIndex: $0, setIndex: 0) },
            device: S3Kit.device,
            workoutID: workout.id
        )
    }

    /// `slot` with `misses`, and every other field changed: a save may write its misses and nothing else.
    static func missing(_ slot: Slot, _ misses: Set<Int>) -> Slot {
        var changed = slot
        changed.misses = misses
        changed.exerciseID = other(than: slot, offset: 3)
        changed.isSupersetWithPrevious.toggle()
        return changed
    }
}

/// What differs between two programs, slot by slot, in a line: for a test to print in place of both.
enum LinkedDifference {
    static func of(_ actual: Program?, _ expected: Program?, _ label: String) -> String? {
        guard let actual, let expected else {
            return actual == nil && expected == nil ? nil : "\(label) is \(actual == nil ? "gone" : "stored")"
        }
        // Which program is the active one is not a save's to change, and reading one here can move it.
        var (read, model) = (actual, expected)
        (read.isActive, model.isActive) = (false, false)
        guard read != model else {
            return nil
        }
        let wanted = Dictionary(uniqueKeysWithValues: expected.days.flatMap(\.slots).map { ($0.id, $0) })
        var lines: [String] = []
        for slot in actual.days.flatMap(\.slots) {
            guard let other = wanted[slot.id] else {
                lines.append("slot \(name(slot.id)) is not expected")
                continue
            }
            if slot.exerciseID != other.exerciseID {
                lines.append("slot \(name(slot.id)) holds \(name(slot.exerciseID)), expected \(name(other.exerciseID))")
            }
            if slot.misses != other.misses {
                lines.append("slot \(name(slot.id)) misses \(slot.misses.sorted()), expected \(other.misses.sorted())")
            }
        }
        let count = "\(actual.days.flatMap(\.slots).count) slots for \(wanted.count)"
        return "\(label): " +
            (lines.isEmpty ? "differs outside its slots' exercises and misses, \(count)" : lines
                .joined(separator: ", "))
    }

    static func name(_ id: some TypedIdentifier) -> String {
        String(id.rawValue.uuidString.suffix(4))
    }
}
