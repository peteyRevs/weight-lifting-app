@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport

/// The exercise store as the swap sheet reads it (F10 S8b): the scene's store, or one that holds its reads at
/// a gate, fails them, or no longer holds the exercise being swapped. It counts the reads of `all()`.
actor SwapExercises: ExerciseRepository {
    private let base: any ExerciseRepository
    private let gate: Gate?
    private var fails: Bool
    private let holdsTheExercise: Bool
    private(set) var catalogReads = 0

    init(base: any ExerciseRepository, gate: Gate? = nil, fails: Bool = false, holdsTheExercise: Bool = true) {
        self.base = base
        self.gate = gate
        self.fails = fails
        self.holdsTheExercise = holdsTheExercise
    }

    /// From now on every read answers.
    func heal() {
        fails = false
    }

    func all() async throws -> [Exercise] {
        catalogReads += 1
        await gate?.pass()
        if fails {
            throw SwapDoubleError()
        }
        return try await base.all()
    }

    func exercise(id: ExerciseID) async throws -> Exercise? {
        holdsTheExercise ? try await base.exercise(id: id) : nil
    }

    func search(_ query: String, equipment: Equipment?, muscle: MuscleGroup?) async throws -> [Exercise] {
        try await base.search(query, equipment: equipment, muscle: muscle)
    }

    func save(_ exercise: Exercise) async throws {
        try await base.save(exercise)
    }

    func seedIfNeeded(_ catalog: [Exercise], version: Int) async throws {
        try await base.seedIfNeeded(catalog, version: version)
    }

    nonisolated func observeAll() -> AsyncStream<[Exercise]> {
        base.observeAll()
    }
}

/// The stats the swap reads: the scene's, with a "Last" read that can fail and bests that answer each read
/// from a table and record what each read asked for.
actor SwapStats: StatsQueries {
    private let base: any StatsQueries
    private let failsLast: Bool
    private let bests: PersonalRecords.Bests?
    private(set) var bestsAsked: [Set<ExerciseID>] = []

    /// `bests` answers every read with its entries for the exercises asked for; nil fails every read.
    init(base: any StatsQueries, failsLast: Bool = false, bests: PersonalRecords.Bests? = .init()) {
        self.base = base
        self.failsLast = failsLast
        self.bests = bests
    }

    func bests(before _: WorkoutState, for exerciseIDs: Set<ExerciseID>) async throws -> PersonalRecords.Bests {
        bestsAsked.append(exerciseIDs)
        guard let bests else {
            throw SwapDoubleError()
        }
        return PersonalRecords.Bests(
            e1RM: bests.e1RM.filter { exerciseIDs.contains($0.key) },
            weightAtReps: bests.weightAtReps.filter { exerciseIDs.contains($0.key) }
        )
    }

    func lastPerformance(exerciseID: ExerciseID) async throws -> LastPerformance? {
        if failsLast {
            throw SwapDoubleError()
        }
        return try await base.lastPerformance(exerciseID: exerciseID)
    }

    func bestSet(exerciseID: ExerciseID) async throws -> (weight: Weight, reps: Reps)? {
        try await base.bestSet(exerciseID: exerciseID)
    }

    func bestSets() async throws -> [ExerciseID: BestSet] {
        try await base.bestSets()
    }

    func exerciseSessions(exerciseID: ExerciseID) async throws -> [ExerciseSession] {
        try await base.exerciseSessions(exerciseID: exerciseID)
    }

    nonisolated func observeExerciseSessions(exerciseID: ExerciseID) -> AsyncStream<[ExerciseSession]> {
        base.observeExerciseSessions(exerciseID: exerciseID)
    }

    nonisolated func observeLibraryStats(recentLimit: Int) -> AsyncStream<LibraryStats> {
        base.observeLibraryStats(recentLimit: recentLimit)
    }

    func bestE1RM(exerciseID: ExerciseID) async throws -> Weight? {
        try await base.bestE1RM(exerciseID: exerciseID)
    }

    func e1RMByWeek(
        exerciseID: ExerciseID,
        lastWeeks: Int,
        calendar: WeekCalendar
    ) async throws -> [WeekKey: Weight] {
        try await base.e1RMByWeek(exerciseID: exerciseID, lastWeeks: lastWeeks, calendar: calendar)
    }

    func weeklyVolume(in range: Range<Date>) async throws -> Volume {
        try await base.weeklyVolume(in: range)
    }

    func sessionsCompleted(in range: Range<Date>) async throws -> Int {
        try await base.sessionsCompleted(in: range)
    }

    func sessionCount(exerciseID: ExerciseID) async throws -> Int {
        try await base.sessionCount(exerciseID: exerciseID)
    }

    func personalRecords(exerciseID: ExerciseID) async throws -> [PersonalRecord] {
        try await base.personalRecords(exerciseID: exerciseID)
    }

    func recentlyLogged(limit: Int) async throws -> [ExerciseID] {
        try await base.recentlyLogged(limit: limit)
    }
}

extension WorkoutStore {
    /// What the shown card's "Swap exercise" sends: the shown exercise's place and id (review SF1), whether or
    /// not the button is drawn, so that a test can send it where the button is not; with no card shown, a place
    /// no workout has.
    var cardOpensSwap: WorkoutAction {
        guard let card = model.page?.card else {
            return .swap(.open(exerciseIndex: -1, exerciseID: ExerciseID(Fixtures.uuid(0))))
        }
        return .swap(.open(exerciseIndex: card.exerciseIndex, exerciseID: card.exerciseID))
    }
}
