import Foundation
import LedgerDomain
import LedgerPersistence

/// The stores a history contract clause runs against (`WorkoutRepositoryContract`, `StatsQueriesContract`),
/// all over one fresh, empty store:
/// - `programs` accepts slots naming `ProgramRepositoryContract.exercises` (a GRDB database must hold them
///   first: `slot.exercise_id` is a foreign key);
/// - `stats` reads the current time as `StatsQueriesContract.now`.
public struct HistoryStores: Sendable {
    public let workouts: any WorkoutRepository
    public let stats: any StatsQueries
    public let programs: any ProgramRepository

    public init(workouts: any WorkoutRepository, stats: any StatsQueries, programs: any ProgramRepository) {
        self.workouts = workouts
        self.stats = stats
        self.programs = programs
    }

    /// Materialises `workout` with the receipt `WorkoutEngine.summary` computes for it, as F10 does.
    public func materialize(
        _ workout: WorkoutState,
        prs: [PersonalRecord] = [],
        slotUpdates: [Slot] = []
    ) async throws {
        try await workouts.materialize(
            workout,
            summary: WorkoutEngine.summary(workout, prs: prs),
            prs: prs,
            slotUpdates: slotUpdates
        )
    }
}

/// `WorkoutRepository`'s contract as named clauses (F05 S3): criterion 3's materialisation as an idempotent
/// upsert, what a stored workout reads back as, the newest-first lists, set edits, deletion, the misses of
/// `slotUpdates`, ids, text holding U+0000 and observation. F07's in-memory fake runs the same clauses.
public enum WorkoutRepositoryContract {
    public typealias Clause = ContractClause<HistoryStores>

    public static let clauses: [Clause] = [
        Clause("a materialised workout of five exercises reads back equal, its live-only fields reset", roundTrip),
        Clause("materialising a workout twice stores it once and changes nothing", materializeTwice),
        Clause("materialising a changed workout replaces its exercises and sets: removed, added, changed", replaces),
        Clause("a workout that is live, discarded or has no end throws notFinished; nothing is stored", notFinished),
        Clause(
            "recent and workouts(in:) are newest first by end date, then id; a limit below 1 gives none",
            newestFirst
        ),
        Clause("updateSets replaces one exercise's sets; an unknown exercise throws missingRow", updateSets),
        Clause("delete hides the workout, and materialising it again brings it back", deleteHides),
        Clause("slotUpdates write each stored slot's misses; an unknown slot is skipped", writesMisses),
        Clause("two exercises or two sets sharing an id throw duplicateIdentifier; nothing is stored", duplicateIDs),
        Clause(
            "an exercise or set id another workout holds, even deleted, is refused; it is unchanged",
            otherWorkoutsIDs
        ),
        Clause("a record naming another workout is refused; nothing is stored, and its records stay", foreignRecord),
        Clause("a name or tag holding U+0000 throws nulInText; nothing is stored", refusesNul),
        Clause("observeRecent emits the list now, then after each change of it, and for no other write", observeRecent)
    ]

    // MARK: Fixtures

    /// The exercises the contract's workouts perform, and its programs name.
    public static let exercises = ProgramRepositoryContract.exercises

    /// Criterion 3's workout, finished at `endedAt`: five exercises with a drop set, an added set, a set left
    /// undone, a set above 12 reps (no e1RM) and a kilogram load. Its first exercise came from a program slot.
    public static func workout(
        number: Int = 0,
        endedAt: Date = EventBuilders.start,
        minutes: Int = 60
    ) -> WorkoutState {
        var kilograms = Seeders.SetSpec(0, 15)
        kilograms.weight = .kilograms(12.5)
        let slot = SlotID(EventBuilders.uuid(0x5107))
        return Seeders.workout(number: number, endedAt: endedAt, minutes: minutes, [
            Seeders.ExerciseLog(exercises[0], slotID: slot, Array(repeating: .init(185, 5), count: 5)),
            Seeders.ExerciseLog(exercises[1], [.init(55, 10), .init(55, 10), .init(55, 9), .init(45, 10, .drop)]),
            Seeders.ExerciseLog(exercises[2], [.init(70, 8), .init(70, 8), .init(70, 8), .init(70, 8, done: false)]),
            Seeders.ExerciseLog(exercises[3], [.init(100, 12), .init(100, 12), .init(100, 13, .added)]),
            Seeders.ExerciseLog(exercises[4], [kilograms, kilograms, .init(20, 5, .warmup)])
        ])
    }

    /// `workout` as a history read returns it: the live-only fields (`cursor`, `rest`, `autoRest`,
    /// `programUpdates`, each exercise's `lastPerformance`) are not stored, so they come back reset.
    public static func stored(_ workout: WorkoutState) -> WorkoutState {
        var stored = workout
        stored.cursor = nil
        stored.rest = nil
        stored.autoRest = true
        stored.programUpdates = [:]
        for index in stored.exercises.indices {
            stored.exercises[index].lastPerformance = nil
        }
        return stored
    }

    /// `workout` edited everywhere a second materialisation must diff: its last exercise removed, a set removed
    /// from the first, a weight and a tick changed in the second, a set added to the third, and it renamed.
    public static func edited(_ workout: WorkoutState) -> WorkoutState {
        var edited = workout
        edited.exercises.removeLast()
        edited.exercises[0].sets.removeLast()
        edited.exercises[1].sets[0].weight = .pounds(57.5)
        edited.exercises[1].sets[2].doneAt = nil
        let added = SetID.derived(from: edited.exercises[2].id, index: 40)
        edited.exercises[2].sets.append(
            LoggedSet(id: added, weight: .pounds(75), reps: Reps(clamping: 6), kind: .added, doneAt: workout.endedAt)
        )
        edited.name = "Workout, revised"
        return edited
    }

    /// When a workout that starts at `start` and lasts `minutes` ends: what `Seeders.workout` takes. A workout's
    /// date is its start (product decision #26), so the clauses place starts on the edges they test.
    public static func ending(startedAt start: Date, minutes: Int = 60) -> Date {
        start.addingTimeInterval(60 * Double(minutes))
    }

    static func key(_ table: String, _ id: some TypedIdentifier) -> String {
        "\(table) \(id.rawValue.uuidString)"
    }

    // MARK: Clauses

    static func roundTrip(_ stores: HistoryStores) async throws -> String? {
        var workout = workout()
        workout.source = WorkoutSource(
            programID: ProgramID(EventBuilders.uuid(0x71)),
            weekIndex: 2,
            dayTemplateID: DayTemplateID(EventBuilders.uuid(0x72))
        )
        workout.cursor = Cursor(exerciseIndex: 1, setIndex: 2)
        workout.rest = RestTimer(endsAt: EventBuilders.start, total: .seconds(90))
        workout.autoRest = false
        workout.programUpdates = [SlotID(EventBuilders.uuid(0x73)): exercises[5].id]
        workout.exercises[0].lastPerformance = LastPerformance(
            date: EventBuilders.start,
            sets: 5,
            reps: 5,
            load: .pounds(180)
        )
        try await stores.materialize(workout)
        let unknown = try await stores.workouts.workout(id: Seeders.workoutID(404))
        return try await ContractCheck.first(
            ContractCheck.expect(stores.workouts.workout(id: workout.id), stored(workout), "workout(id:)"),
            ContractCheck.expect(unknown, nil, "workout(id:) of an unknown id")
        )
    }

    static func materializeTwice(_ stores: HistoryStores) async throws -> String? {
        let workout = workout()
        try await stores.materialize(workout)
        try await stores.materialize(workout)
        return try await ContractCheck.expect(stores.workouts.recent(limit: 10), [workout], "recent(limit: 10)")
    }

    static func replaces(_ stores: HistoryStores) async throws -> String? {
        let workout = workout()
        try await stores.materialize(workout)
        let edited = edited(workout)
        try await stores.materialize(edited)
        let afterEdit = try await stores.workouts.workout(id: workout.id)
        try await stores.materialize(workout)
        let afterRevert = try await stores.workouts.recent(limit: 10)
        return ContractCheck.first(
            ContractCheck.expect(afterEdit, edited, "workout(id:) after materialising the edit"),
            ContractCheck.expect(afterRevert, [workout], "recent after materialising the original again")
        )
    }

    static func notFinished(_ stores: HistoryStores) async throws -> String? {
        var live = workout()
        live.phase = .live
        var discarded = workout()
        discarded.phase = .discarded
        var endless = workout()
        endless.endedAt = nil
        for refused in [live, discarded, endless] {
            let issue = await ContractCheck.expectError(
                LedgerPersistenceError.notFinished(key("workout", refused.id))
            ) { try await stores.materialize(refused) }
            if let issue {
                return "\(refused.phase): \(issue)"
            }
        }
        return try await ContractCheck.expect(stores.workouts.recent(limit: 10), [], "recent after the refused calls")
    }
}

/// The list order.
extension WorkoutRepositoryContract {
    /// Lists are newest first by **start** (product decision #26), then by id. Each workout starts at its day and
    /// lasts an hour; a long one started an hour before the newest but ended after it, so it lists third.
    static func newestFirst(_ stores: HistoryStores) async throws -> String? {
        let start = EventBuilders.start
        let days = [0.0, 1, 2].map { start.addingTimeInterval(86400 * $0) }
        // The oldest has no exercises, and the middle one an exercise with no sets: both read back as stored.
        var all = days.enumerated().map { workout(number: $0, endedAt: ending(startedAt: $1)) }
        all[0].exercises = []
        all[1].exercises[3].sets = []
        // Two start at the same instant: they list by id, whichever was stored first.
        let twin = workout(number: 3, endedAt: ending(startedAt: days[2]))
        let long = workout(
            number: 4,
            endedAt: ending(startedAt: days[2].addingTimeInterval(-3600), minutes: 180),
            minutes: 180
        )
        for workout in [twin, long, all[1], all[2], all[0]] {
            try await stores.materialize(workout)
        }
        let workouts = stores.workouts
        let wide = try await workouts.workouts(in: days[0] ..< days[2].addingTimeInterval(1))
        return try await ContractCheck.first(
            ContractCheck.expect(workouts.recent(limit: 2), [all[2], twin], "recent(limit: 2), a tie by id"),
            ContractCheck.expect(workouts.recent(limit: 3), [all[2], twin, long], "recent(limit: 3), by start"),
            ContractCheck.expect(workouts.recent(limit: 0), [], "recent(limit: 0)"),
            ContractCheck.expect(workouts.recent(limit: -1), [], "recent(limit: -1)"),
            ContractCheck.expect(workouts.workouts(in: days[1] ..< days[2]), [long, all[1]], "a half-open range"),
            ContractCheck.expect(wide, [all[2], twin, long, all[1], all[0]], "a range holding all five")
        )
    }
}
