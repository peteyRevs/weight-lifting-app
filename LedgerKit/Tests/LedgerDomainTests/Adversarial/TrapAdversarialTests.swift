import Foundation
@testable import LedgerDomain
import Testing

#if os(macOS)
    /// Inputs that other public APIs can legitimately produce must not trap. `WeekCalendar.weekIndex`
    /// documents negative indices for dates before `startDate` (decision #18), so the rules that take a
    /// week index are exercised with one in a child process (testing-strategy §2.1 exit tests).
    @Suite("Trap-freedom (adversarial)", .tags(.domain))
    struct TrapAdversarialTests {}

    extension TrapAdversarialTests {
        @Test("prescribe for a week before the block (index −1) returns week-0 values instead of trapping.")
        func prescribe_negativeWeek_doesNotTrap() async {
            await #expect(processExitsWith: .success) {
                // Spec §7.2: adv counts weeks i < −1 → none → load = start; held = (−2) ∈ misses → false.
                let slot = try Fixtures.slot(Fixtures.backSquat, id: 1700, startLoad: .pounds(250), misses: [0])
                let prescription = ProgressionRules.prescribe(
                    week: Fixtures.week(0), weekIndex: -1, slot: slot, exercise: Fixtures.backSquat, units: .lb
                )
                if prescription.load != .pounds(250) || prescription.isHeld {
                    exit(1)
                }
            }
        }

        @Test("skippedWeeks before the block has started is empty instead of trapping.")
        func skippedWeeks_beforeStart_doesNotTrap() async {
            await #expect(processExitsWith: .success) {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = Fixtures.utc
                let start = CivilDate(Fixtures.date(2026, 8, 17), in: calendar)
                let weeks = WeekCalendar(startDate: start, weekStart: .monday, calendar: calendar)
                let skipped = weeks.skippedWeeks(before: Fixtures.date(2026, 8, 1), trainedWeeks: [], weekCount: 8)
                if !skipped.isEmpty {
                    exit(1)
                }
            }
        }

        @Test("CivilDate rejects absurd year, month and day values with nil instead of trapping (ADR-007).")
        func civilDate_absurdComponents_doNotTrap() async {
            await #expect(processExitsWith: .success) {
                let absurd = [(Int.max, 1, 1), (Int.min, 1, 1), (2026, Int.max, 1), (2026, 1, Int.min)]
                if absurd.contains(where: { CivilDate(year: $0.0, month: $0.1, day: $0.2) != nil }) {
                    exit(1)
                }
            }
        }

        @Test("MissTracking.update for a week before the block does not trap.")
        func missTracking_negativeWeek_doesNotTrap() async {
            await #expect(processExitsWith: .success) {
                let slot = try Fixtures.slot(Fixtures.bench, id: 1701, sets: 1, reps: 5)
                let exercise = try Fixtures.workoutExercise(
                    Fixtures.bench,
                    index: 0,
                    sets: [Fixtures.set(1, pounds: 185, reps: 5)]
                )
                _ = MissTracking.update(slot: slot, exercise: exercise, weekIndex: -1, isDeload: false)
            }
        }
    }
#endif
