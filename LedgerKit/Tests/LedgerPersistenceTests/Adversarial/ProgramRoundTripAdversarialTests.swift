import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S2 adversarial round 1, criterion 2: a program saved by `GRDBProgramRepository.save` reads back
/// `Equatable`-equal, misses included, through `active()`, `program(id:)` and a second repository.
@Suite("Adversarial S2 · program round trips", .tags(.persistence), .timeLimit(.minutes(1)))
struct ProgramRoundTripAdversarialTests {
    static func expectRoundTrip(_ program: Program, _ stack: S2Kit.Stack) async throws {
        try await stack.programs.save(program)
        #expect(try await stack.programs.program(id: program.id) == program)
        let fresh = GRDBProgramRepository(stack.queue)
        #expect(try await fresh.program(id: program.id) == program, "a second repository reads the same program")
        if program.isActive {
            #expect(try await fresh.active() == program)
        }
    }

    @Test("Criterion 2: 8 weeks × 4 days with misses round-trips, and the rows are exactly the program's")
    func eightByFour_roundTrips_withExactRows() async throws {
        let stack = try await S2Kit.stack()
        let program = try S2Kit.program(weeks: 8, days: 4, slotsPerDay: 6)
        #expect(program.days.flatMap(\.slots).contains { !$0.misses.isEmpty })
        try await Self.expectRoundTrip(program, stack)
        #expect(try await S2Kit.liveCounts(stack.queue) == S2Kit.expectedCounts([program]))
        #expect(try await S2Kit.count(stack.queue, "slot_miss") == S2Kit.expectedCounts([program])["slot_miss"])
    }

    @Test("Saving the same program twice changes nothing and adds no row")
    func savingTwice_isIdempotent() async throws {
        let stack = try await S2Kit.stack()
        let program = try S2Kit.program()
        try await stack.programs.save(program)
        let before = try await Self.dump(stack.queue)
        stack.clock.advance()
        try await stack.programs.save(program)
        #expect(try await Self.dump(stack.queue) == before, "an unchanged save rewrote a row")
        #expect(try await stack.programs.program(id: program.id) == program)
    }

    @Test("Misses of any week index (negative, beyond the block, Int extremes) round-trip")
    func misses_anyIndex_roundTrip() async throws {
        let stack = try await S2Kit.stack()
        var program = try S2Kit.program(weeks: 2, days: 1, slotsPerDay: 3)
        let odd: [Set<Int>] = [[], [-1, 0, 99], [Int.min, Int.max, 7, 1_000_000]]
        program = try program.rebuilt(days: [DayTemplate(
            id: program.days[0].id,
            name: program.days[0].name,
            tag: program.days[0].tag,
            slots: program.days[0].slots.enumerated().map { try $1.with(misses: odd[$0]) }
        )])
        try await Self.expectRoundTrip(program, stack)
    }

    @Test("Days in any order, empty days, unscheduled days and a day on all seven weekdays round-trip")
    func dayShapes_roundTrip() async throws {
        let stack = try await S2Kit.stack()
        let base = try S2Kit.program(weeks: 3, days: 5, slotsPerDay: 2)
        let reversed = Array(base.days.reversed())
        let empty = DayTemplate(id: S2Kit.dayID(999), name: "", tag: "", slots: [])
        let everyDay = Dictionary(uniqueKeysWithValues: Weekday.allCases.map { ($0, reversed[2].id) })
        let weeks = [
            Week(id: base.weeks[0].id, index: 0, schedule: everyDay),
            Week(id: base.weeks[1].id, index: 1, isDeload: true, schedule: [:]),
            Week(id: base.weeks[2].id, index: 2, schedule: [.sunday: empty.id, .monday: reversed[0].id])
        ]
        try await Self.expectRoundTrip(base.rebuilt(weeks: weeks, days: [empty] + reversed), stack)
    }

    @Test("A program with no days at all round-trips")
    func noDays_roundTrips() async throws {
        let stack = try await S2Kit.stack()
        let program = try S2Kit.program(weeks: 2, days: 0, slotsPerDay: 0)
        try await Self.expectRoundTrip(program, stack)
    }

    @Test("Text fields keep every character: emoji, combining marks, quotes, SQL and 10 000 characters")
    func text_roundTripsExactly() async throws {
        let names = [
            "Push 💪🏽 — «Force»", "e\u{301}le\u{301}vation", "Élévation", "'; DROP TABLE program; --",
            "100% _under_ \\ load", "tab\there\nnewline", String(repeating: "ß", count: 10000), ""
        ]
        let stack = try await S2Kit.stack()
        for (index, name) in names.enumerated() {
            let base = try S2Kit.program(index + 1, weeks: 2, days: 1, slotsPerDay: 1, isActive: false)
            let day = DayTemplate(id: base.days[0].id, name: name, tag: name, slots: base.days[0].slots)
            let program = try base.rebuilt(days: [day], name: name)
            try await stack.programs.save(program)
            let loaded = try await stack.programs.program(id: program.id)
            #expect(loaded?.name.unicodeScalars.elementsEqual(name.unicodeScalars) == true, "name \(index)")
            #expect(loaded?.days.first?.name.unicodeScalars.elementsEqual(name.unicodeScalars) == true)
            #expect(loaded?.days.first?.tag.unicodeScalars.elementsEqual(name.unicodeScalars) == true)
        }
    }

    /// Spec question S2-4, decided (orchestrator, 2026-09-30: refuse, don't truncate). GRDB binds a `String` as a
    /// C string (`sqlite3_bind_text(…, -1, …)`), so a name would be stored cut at its first NUL. The save is
    /// refused instead, and nothing is written. (Changed by the implementer in S2 fix round 1, as instructed; it
    /// documented the cut before.)
    @Test("A name holding NUL is refused, and nothing is written")
    func nul_cutsTheName() async throws {
        let stack = try await S2Kit.stack()
        let program = try S2Kit.program(weeks: 2, days: 1, slotsPerDay: 1).rebuilt(name: "nul\u{0}inside")
        await #expect(throws: LedgerPersistenceError.nulInText("program.name")) {
            try await stack.programs.save(program)
        }
        #expect(try await ProgramRoundTripAdversarialTests.dump(stack.queue).isEmpty, "something was written")
    }

    @Test("Start dates at the civil extremes and leap days, every goal and days-per-week value round-trip")
    func headerFields_roundTrip() async throws {
        let stack = try await S2Kit.stack()
        let dates = [
            CivilDate.min,
            .max,
            CivilDate(year: 2024, month: 2, day: 29),
            CivilDate(year: 999, month: 1, day: 9)
        ]
        let goals: [TrainingGoal?] = [nil] + TrainingGoal.allCases
        let perWeek: [Int?] = [nil, 0, 7, -1, Int.max, Int.min]
        for (index, date) in dates.compactMap(\.self).enumerated() {
            for (goalIndex, goal) in goals.enumerated() {
                let number = index * 10 + goalIndex + 1
                let program = try S2Kit.program(number, weeks: 2, days: 1, slotsPerDay: 1, isActive: false).rebuilt(
                    startDate: date, goal: .some(goal), daysPerWeek: .some(perWeek[number % perWeek.count])
                )
                try await Self.expectRoundTrip(program, stack)
            }
        }
    }

    /// Every column of every program table, for byte-level comparisons.
    static func dump(_ queue: DatabaseQueue) async throws -> [String] {
        try await queue.read { database in
            var rows: [String] = []
            for table in ["program", "program_week", "day_template", "slot", "slot_miss"] {
                let fetched = try Row.fetchAll(database, sql: "SELECT * FROM \(table) ORDER BY id")
                rows += fetched.map { "\(table) \($0.description)" }
            }
            return rows
        }
    }
}
