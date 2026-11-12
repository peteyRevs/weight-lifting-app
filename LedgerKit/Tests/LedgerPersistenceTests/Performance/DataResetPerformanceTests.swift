import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// F14 S3, N24: "Delete all data" over a 20,000-set history, the reseed of the catalog, `VACUUM` and the `TRUNCATE`
/// checkpoint included, under `PerformanceBudget.eraseAll` at the 95th percentile. The history is the record replay
/// suite's 400 workouts of 50 sets, with the bundled catalog, the seed program and changed settings, written once to a
/// template file; each run erases a fresh copy of it, so every run erases the whole history. Nightly lane only.
@Suite(
    "GRDBDataReset · erase timing",
    .tags(.persistence, .performance, .slow),
    .enabled(if: TestLane.runsSlowTests, "a .performance test: nightly lane only"),
    .timeLimit(.minutes(10))
)
struct DataResetPerformanceTests {
    /// The template: the history above, its WAL checkpointed into the file, so the file alone is the database.
    /// Returns the file and how many sets it holds.
    static func template(in directory: TemporaryDirectory) async throws -> (url: URL, sets: Int) {
        let url = directory.file("template/ledger.sqlite")
        let stores = try LedgerStores.open(at: url, kind: .phone, now: { EventBuilders.start }, newID: { UUID() })
        try await stores.exercises.seedIfNeeded(ExerciseCatalog.seed(), version: ExerciseCatalog.version)
        try await stores.programs.save(DataResetContract.program())
        for number in 0 ..< 400 {
            try await stores.workouts.materialize(RecordReplayPerformanceTests.workout(number), slotUpdates: [])
        }
        try await stores.settings.save(DataResetContract.changedSettings)
        let sets = try await stores.queue.writeWithoutTransaction { database in
            _ = try database.checkpoint(.truncate)
            return try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM logged_set") ?? 0
        }
        return (url, sets)
    }

    @Test("N24. Erasing 20,000 sets and reseeding, VACUUM and the checkpoint included, within budget at p95")
    func eraseAll_underBudget() async throws {
        let directory = TemporaryDirectory()
        defer { try? directory.remove() } // cleanup only: a leftover temporary file fails nothing
        let (template, sets) = try await Self.template(in: directory)
        #expect(sets == 20000)
        let clock = ContinuousClock()
        var erases: [Duration] = []
        for run in 0 ... PerformanceBudget.statsRuns { // the first run is the warm-up
            let url = directory.file("run-\(run)/ledger.sqlite")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // With its WAL companions: a WAL file is opened read-only first (the launch's preflight), which needs them.
            for suffix in ["", "-wal", "-shm"] {
                try FileManager.default.copyItem(
                    at: URL(filePath: template.path(percentEncoded: false) + suffix),
                    to: URL(filePath: url.path(percentEncoded: false) + suffix)
                )
            }
            let stores = try LedgerStores.open(at: url, kind: .phone, now: { EventBuilders.start }, newID: { UUID() })
            try await erases.append(clock.measure {
                try await stores.reset.eraseAll(restoring: DataResetContract.restored)
            })
            let left = try await stores.queue.read { database in
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM logged_set") ?? -1
            }
            #expect(left == 0, "run \(run)")
        }
        let runs = Array(erases.dropFirst())
        let verdict = PerformanceRunner.verdict(runs, budget: PerformanceBudget.eraseAll)
        #expect(verdict.isWithinBudget, "\(verdict)")
        Attachment.record("eraseAll: p95 \(verdict.percentile95), median \(verdict.median)", named: "erase-all.txt")
    }
}
