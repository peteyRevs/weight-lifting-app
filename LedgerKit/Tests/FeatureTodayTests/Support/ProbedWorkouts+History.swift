import LedgerDomain

/// The History list's reads (F13 S1), which Today makes none of: straight through, as every other call.
extension ProbedWorkouts {
    func historyEntries() async throws -> [HistoryEntry] {
        try await base.historyEntries()
    }

    func observeHistoryEntries() -> AsyncStream<[HistoryEntry]> {
        base.observeHistoryEntries()
    }

    func observeWorkout(id: WorkoutID) -> AsyncStream<RecordedWorkout?> {
        base.observeWorkout(id: id)
    }
}
