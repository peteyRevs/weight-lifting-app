import Foundation
import LedgerDomain

/// What `LibraryStore` follows (F12 S1, N1; S3, N20): the exercises, the settings and the Library's stats, in one
/// task group for as long as `LibraryRoot`'s task runs. The stats are observed where they are read from
/// (`StatsQueries.observeLibraryStats`), as an exercise's history observes its sessions: a workout finished, edited
/// or deleted, the newest or an older one, reaches RECENTLY LOGGED, the session counts and the PRs while the
/// Library is up, and a write that changes none of them costs no rebuild.
///
/// Every change marks one channel that keeps only the newest mark, and one loop rebuilds the rows, so a change
/// that moves two sources at once costs one or two rebuilds and never two at a time.
extension LibraryStore {
    /// How many exercises RECENTLY LOGGED shows.
    static let recentLimit = 5

    func run() async {
        sources = LibrarySources()
        let (marks, mark) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.followExercises(mark) }
            group.addTask { await self.followSettings(mark) }
            group.addTask { await self.followStats(mark) }
            for await _ in marks {
                rebuild()
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

    /// A workout was finished, edited or deleted: the recent exercises, their sessions and the PRs, as they now
    /// stand. An observation whose read fails ends, which shows the failed state until the next run.
    private func followStats(_ mark: AsyncStream<Void>.Continuation) async {
        await follow(stats.observeLibraryStats(recentLimit: Self.recentLimit), mark) { $0.stats = $1 }
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

    /// Writes the rows from what the sources last said, once all three have spoken, and shows them under the
    /// filter.
    private func rebuild() {
        guard !sources.hasEnded else {
            fail()
            return
        }
        guard let exercises = sources.exercises, let units = sources.units, let read = sources.stats else {
            return
        }
        rows = LibraryPresentation.rows(LibraryInput(
            exercises: exercises,
            recent: read.recent,
            sessions: read.sessions,
            bestSets: read.bestSets,
            units: units,
            locale: locale
        ))
        show()
    }
}

/// What `LibraryStore` knows of its sources during one run: each is nil until it has spoken.
nonisolated struct LibrarySources {
    var exercises: [Exercise]?
    var units: Units?
    var stats: LibraryStats?
    /// A store's observation ended by itself: the rows can no longer follow it.
    var hasEnded = false
}
