import Foundation
import LedgerDomain

/// What `HistoryStore` follows (F13 S1, N2): the History list's entries and the settings, in one task group for as
/// long as `HistoryRoot`'s task runs. The entries are observed where they are stored
/// (`WorkoutRepository.observeHistoryEntries()`), so a workout finished, edited or deleted, the oldest included,
/// reaches the list while it is up; the settings say the units, and the first day of the week, which regroups it.
///
/// Every change marks one channel that keeps only the newest mark, and one loop rebuilds the model off the main
/// actor, so a change that moves both sources at once costs one or two rebuilds and never two at a time.
extension HistoryStore {
    func run() async {
        sources = HistorySources()
        let (marks, mark) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.follow(self.workouts.observeHistoryEntries(), mark) { $0.entries = $1 } }
            group.addTask { await self.follow(self.settings.observe(), mark) { $0.settings = $1 } }
            for await _ in marks {
                await rebuild()
            }
        }
    }

    /// Keeps each value of a store's observation with `keep` and marks the change. An observation that ends while
    /// the task still runs has failed.
    private func follow<Value: Sendable>(
        _ values: AsyncStream<Value>,
        _ mark: AsyncStream<Void>.Continuation,
        keep: (inout HistorySources, Value) -> Void
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
            logger.log.error("A store's observation ended while History was on screen")
            sources.hasEnded = true
            mark.yield()
        }
    }

    /// Builds the model from what the sources last said, once both have spoken, and shows it.
    private func rebuild() async {
        guard !sources.hasEnded else {
            fail()
            return
        }
        guard let entries = sources.entries, let settings = sources.settings else {
            return
        }
        let model = await Self.model(HistoryInput(
            entries: entries,
            units: settings.units,
            weekStart: settings.weekStart,
            now: date.now,
            calendar: calendar,
            locale: locale
        ))
        guard !Task.isCancelled else {
            return
        }
        show(model)
    }

    /// The model, built off the main actor: a thousand workouts' rows take more than a frame. A model that a change
    /// overtook while it was built is shown, and the change's turn builds the next.
    @concurrent
    private nonisolated static func model(_ input: HistoryInput) async -> HistoryModel {
        HistoryPresentation.make(input)
    }
}

/// What `HistoryStore` knows of its sources during one run: each is nil until it has spoken.
nonisolated struct HistorySources {
    var entries: [HistoryEntry]?
    var settings: Settings?
    /// A store's observation ended by itself: the list can no longer follow it.
    var hasEnded = false
}
