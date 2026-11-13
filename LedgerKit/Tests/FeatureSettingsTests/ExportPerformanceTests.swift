import Darwin
@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerFakes
import LedgerTestSupport
import Testing

/// F14 S2, N17 (amended): 10,000 sets written to the export's file in under 200 ms, the median of 5 runs, and the
/// footprint retained after the writes under 5 MB, a smoke figure (the file is streamed workout by workout, never one
/// `String`). Nightly lane only.
@Suite(
    "Export performance",
    .tags(.feature, .performance),
    .enabled(if: TestLane.runsSlowTests, "a .performance test: nightly lane only")
)
struct ExportPerformanceTests {
    static let budget: Duration = .milliseconds(200)
    static let memoryBudget = 5 * 1024 * 1024

    /// 400 workouts of 5 exercises of 5 sets: 10,000 sets, a week apart from 2018.
    static func history() throws -> [WorkoutState] {
        let template = try Fixtures.seedSession()
        let start = Fixtures.date(2018, 1, 1, hour: 6)
        return (0 ..< 400).map { number in
            var workout = template
            workout.exercises = (0 ..< 5).map { place in
                var exercise = template.exercises[place % template.exercises.count]
                exercise.sets = (0 ..< 5).map { index in
                    LoggedSet(
                        id: SetID(UUID()),
                        weight: .pounds(Decimal(100 + index * 5)),
                        reps: Reps(clamping: 5 + index),
                        kind: .working,
                        doneAt: start
                    )
                }
                return exercise
            }
            workout.startedAt = start.addingTimeInterval(Double(number) * 7 * 86400)
            workout.phase = .finished
            return workout
        }
    }

    /// This process's memory footprint, in bytes.
    static func footprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    @Test("N17. 10,000 sets are written in under 200 ms (median of 5), retaining under 5 MB after the write")
    func tenThousandSets_withinBudget() throws {
        let workouts = try Self.history()
        #expect(workouts.reduce(0) { $0 + $1.totalSets } == 10000)
        let directory = FileManager.default.temporaryDirectory.appending(path: "ExportPerformance-\(UUID().uuidString)")
        defer { try? ExportFile.clear(directory) } // a leftover temporary directory fails nothing
        let clock = ContinuousClock()
        let plan = ExportFile.Plan(name: "perf.csv", units: .lb, calendar: Fixtures.calendar, directory: directory)
        _ = try ExportFile.write(workouts, as: plan) // warm-up, untimed
        let before = Self.footprint()
        let runs = try (0 ..< 5).map { _ in
            try clock.measure { _ = try ExportFile.write(workouts, as: plan) }
        }
        // A smoke figure (N17 as amended): what the writes retain, not their peak.
        let added = Self.footprint() - before
        let verdict = PerformanceRunner.verdict(runs, budget: Self.budget, statistic: .median)
        #expect(verdict.isWithinBudget, "\(verdict)")
        #expect(added < Self.memoryBudget, "\(added) bytes") // bytes, not a timing
    }
}
