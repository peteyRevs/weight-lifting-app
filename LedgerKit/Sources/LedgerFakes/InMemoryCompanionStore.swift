#if DEBUG
    import Foundation
    import LedgerDomain
    import Synchronization

    /// `CompanionStore` in memory, keeping `CompanionStoreContract` (LedgerTestSupport) as `GRDBCompanionStore` does:
    /// records and contexts are kept as their `CompanionCodec` bytes decode, and dates and weights pass
    /// `StorageBoundary` first, so the fake refuses what the database refuses, with the same error.
    public final class InMemoryCompanionStore: CompanionStore {
        private struct Stored {
            var logs: [WorkoutID: FinishedLogEntry] = [:]
            var acknowledged: Set<WorkoutID> = []
            var state = CompanionState.empty
            var lastPerformance: [ExerciseID: LastPerformance] = [:]
        }

        private let stored = Mutex(Stored())

        public init() {}

        public func saveFinishedLog(_ record: FinishedWorkoutRecord, createdAt: Date) async throws {
            let kept = try CompanionCodec.decode(FinishedWorkoutRecord.self, from: CompanionCodec.encode(record))
            _ = try StorageBoundary.seconds(createdAt)
            let new = FinishedLogEntry(record: kept, createdAt: createdAt, enqueuedAt: nil)
            stored.withLock { $0.logs[record.workoutID, default: new].record = kept }
        }

        public func unacknowledgedLogs() async throws -> [FinishedLogEntry] {
            stored.withLock { stored in
                stored.logs.filter { !stored.acknowledged.contains($0.key) }.values.sorted { left, right in
                    (left.createdAt, left.record.workoutID.rawValue.uuidString)
                        < (right.createdAt, right.record.workoutID.rawValue.uuidString)
                }
            }
        }

        public func markEnqueued(_ workouts: [WorkoutID], at date: Date) async throws {
            _ = try StorageBoundary.seconds(date)
            stored.withLock { stored in
                for id in workouts where stored.logs[id] != nil && stored.logs[id]?.enqueuedAt == nil {
                    stored.logs[id]?.enqueuedAt = date
                }
            }
        }

        public func acknowledge(_ workouts: [WorkoutID], at date: Date) async throws {
            _ = try StorageBoundary.seconds(date)
            stored.withLock { stored in stored.acknowledged.formUnion(workouts.filter { stored.logs[$0] != nil }) }
        }

        public func compactAcknowledged() async throws {
            stored.withLock { stored in
                stored.logs = stored.logs.filter { !stored.acknowledged.contains($0.key) }
                stored.acknowledged = []
            }
        }

        public func pruneArchives(now: Date) async throws {
            let cutoff = try StorageBoundary.seconds(now) - FinishedLogEntry.archiveRetention
            stored.withLock { stored in
                stored.logs = stored.logs.filter { $0.value.createdAt.timeIntervalSinceReferenceDate >= cutoff }
                stored.acknowledged.formIntersection(stored.logs.keys)
            }
        }

        /// Every stored log that names a HealthKit UUID, acknowledged or not, in no order: what
        /// `InMemoryWorkoutRepository.pendingHealth()` reads, as the database joins `finished_log`.
        func healthLogs() -> [PendingHealth] {
            stored.withLock { stored in
                stored.logs.values.compactMap { entry in
                    entry.record.healthKitUUID.map { uuid in
                        PendingHealth(
                            workoutID: entry.record.workoutID,
                            healthKitUUID: uuid,
                            createdAt: entry.createdAt
                        )
                    }
                }
            }
        }

        /// Forgets everything, as "Delete all data" empties the tables (`InMemoryDataReset`).
        func reset() {
            stored.withLock { $0 = Stored() }
        }

        public func state() async throws -> CompanionState {
            stored.withLock(\.state)
        }

        public func saveState(_ state: CompanionState) async throws {
            let context = try state.context.map { context in
                try CompanionCodec.decode(CompanionContext.self, from: CompanionCodec.encode(context))
            }
            let kept = CompanionState(context: context, programFileSHA256: state.programFileSHA256)
            stored.withLock { $0.state = kept }
        }

        public func replaceLastPerformance(_ performance: [ExerciseID: LastPerformance]) async throws {
            for line in performance.values {
                _ = try StorageBoundary.seconds(line.date)
                try line.load.checkStorable()
            }
            stored.withLock { $0.lastPerformance = performance }
        }

        public func lastPerformance() async throws -> [ExerciseID: LastPerformance] {
            stored.withLock(\.lastPerformance)
        }
    }
#endif
