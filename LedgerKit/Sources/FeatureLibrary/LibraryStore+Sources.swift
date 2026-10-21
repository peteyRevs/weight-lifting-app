import Foundation
import LedgerDomain

/// What `LibraryStore` follows (F12 S1, N1): the exercises, the settings and the newest finished workout, in one
/// task group for as long as `LibraryRoot`'s task runs, and the stats the rows show, read again on every run and
/// whenever the newest workout changes (a workout finished, edited or deleted). No stats query is observed: the
/// newest workout is the signal, as it is Today's.
///
/// Every change marks one channel that keeps only the newest mark, and one loop rebuilds the rows, so a change
/// that moves two sources at once costs one or two rebuilds and never two at a time. An edit of an older workout
/// in History shows at the next run.
extension LibraryStore {
    /// How many finished workouts are followed: a workout finished meanwhile is the newest.
    static let followedWorkouts = 1
    /// How many exercises RECENTLY LOGGED shows.
    static let recentLimit = 5

    func run() async {
        sources = LibrarySources()
        let (marks, mark) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.followExercises(mark) }
            group.addTask { await self.followSettings(mark) }
            group.addTask { await self.followRecentWorkouts(mark) }
            for await _ in marks {
                await rebuild()
            }
        }
    }

    /// A custom exercise saved (F12 S3) or a catalog upgrade: its row, or the rows' order, changes.
    private func followExercises(_ mark: AsyncStream<Void>.Continuation) async {
        await follow(exercises.observeAll(), mark) { $0.exercises = $1 }
    }

    /// The units say how each PR is written.
    private func followSettings(_ mark: AsyncStream<Void>.Continuation) async {
        await follow(settings.observe(), mark) { $0.units = $1.units }
    }

    /// A workout was finished, edited or deleted: the recent exercises, their sessions and the PRs may have
    /// changed with it.
    private func followRecentWorkouts(_ mark: AsyncStream<Void>.Continuation) async {
        await follow(workouts.observeRecent(limit: Self.followedWorkouts), mark) { kept, _ in
            kept.hasHeardWorkouts = true
            kept.forgetStats()
        }
    }

    /// Keeps each value of a store's observation with `keep` and marks the change. An observation that ends while
    /// the task still runs has failed.
    private func follow<Value: Sendable>(
        _ values: AsyncStream<Value>,
        _ mark: AsyncStream<Void>.Continuation,
        keep: (inout LibrarySources, Value) -> Void
    ) async {
        for await value in values {
            guard !Task.isCancelled else {
                return
            }
            keep(&sources, value)
            mark.yield()
        }
        if !Task.isCancelled {
            // Logged here, once, and not by each rebuild that then finds it ended.
            logger.log.error("A store's observation ended while the Library was on screen")
            sources.hasEnded = true
            mark.yield()
        }
    }

    /// Writes the rows from what the sources last said, once all three have spoken, reading the stats first when
    /// they are not known, and shows them under the filter.
    private func rebuild() async {
        guard !sources.hasEnded else {
            fail()
            return
        }
        guard let exercises = sources.exercises, let units = sources.units, sources.hasHeardWorkouts,
              let stats = await readStats()
        else {
            return
        }
        rows = LibraryPresentation.rows(LibraryInput(
            exercises: exercises,
            recent: stats.recent,
            sessions: stats.sessions,
            bestSets: stats.bestSets,
            units: units,
            locale: locale
        ))
        show()
    }

    /// The stats as last read, or read now. Nil when the read failed, which is logged and shown, and when the
    /// run's task was cancelled meanwhile, which shows nothing. A read that a change overtook is shown and not
    /// kept: the change has marked the channel, so the next turn reads again.
    private func readStats() async -> LibraryStats? {
        if let kept = sources.stats {
            return kept
        }
        let staleCount = sources.staleCount
        do {
            let recent = try await stats.recentlyLogged(limit: Self.recentLimit)
            var sessions: [ExerciseID: Int] = [:]
            for id in recent {
                sessions[id] = try await stats.sessionCount(exerciseID: id)
            }
            let read = try await LibraryStats(recent: recent, sessions: sessions, bestSets: stats.bestSets())
            guard !Task.isCancelled else {
                return nil
            }
            if sources.staleCount == staleCount {
                sources.stats = read
            }
            return read
        } catch {
            guard !Task.isCancelled else {
                return nil
            }
            logger.log.error("The Library's stats could not be read: \(String(describing: error), privacy: .public)")
            fail()
            return nil
        }
    }
}

/// What the stats say of the exercises: the recent ones, their sessions, and every best set.
nonisolated struct LibraryStats: Sendable {
    let recent: [ExerciseID]
    let sessions: [ExerciseID: Int]
    let bestSets: [ExerciseID: BestSet]
}

/// What `LibraryStore` knows of its sources during one run: each is nil (or false) until it has spoken.
nonisolated struct LibrarySources {
    var exercises: [Exercise]?
    var units: Units?
    var hasHeardWorkouts = false
    /// The stats as last read; nil when the newest workout has changed since.
    var stats: LibraryStats?
    /// Counts the changes that made `stats` stale, so that a read one of them overtook is not kept.
    private(set) var staleCount = 0
    /// A store's observation ended by itself: the rows can no longer follow it.
    var hasEnded = false

    mutating func forgetStats() {
        stats = nil
        staleCount += 1
    }
}
