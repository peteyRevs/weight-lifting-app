import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import Testing

/// F05 S2 close-out round, S2-4 as decided (refuse, don't truncate): U+0000 anywhere in any text column a
/// repository writes (program name, day name and tag, exercise name and short name, by save, seed and refresh)
/// throws `nulInText("table.column")` and changes no byte. The JSON array columns hold enum raw values and
/// UUIDs only, so no domain value can put a NUL there.
@Suite("Adversarial S2 close-out · NUL in text", .tags(.persistence), .timeLimit(.minutes(1)))
struct NulTextCloseoutAdversarialTests {
    static let texts = ["\u{0}", "\u{0}lead", "trail\u{0}", "mid\u{0}dle", "e\u{0}\u{301}", "\u{0}\u{0}"]

    enum Column: String, CaseIterable, Sendable {
        case programName, dayName, dayTag
    }

    static func program(_ base: Program, _ column: Column, _ text: String) throws -> Program {
        var days = base.days
        switch column {
        case .programName:
            return try base.rebuilt(name: text)
        case .dayName:
            days[1] = DayTemplate(id: days[1].id, name: text, tag: days[1].tag, slots: days[1].slots)
        case .dayTag:
            days[1] = DayTemplate(id: days[1].id, name: days[1].name, tag: text, slots: days[1].slots)
        }
        return try base.rebuilt(days: days)
    }

    @Test(
        "NUL in a program's text throws by column, as a new program and as an edit, and writes nothing",
        arguments: Column.allCases,
        texts
    )
    func programText_isRefused(column: Column, text: String) async throws {
        let expected: LedgerPersistenceError = switch column {
        case .programName: .nulInText("program.name")
        case .dayName: .nulInText("day_template.name")
        case .dayTag: .nulInText("day_template.tag")
        }
        let stack = try await S2Kit.stack()
        let base = try S2Kit.program(1, weeks: 2, days: 2, slotsPerDay: 1, isActive: true)
        let broken = try Self.program(base, column, text)
        await #expect(throws: expected) { try await stack.programs.save(broken) }
        #expect(try await S2Kit.count(stack.queue, "program") == 0)
        try await stack.programs.save(base)
        let before = try await ProgramRoundTripAdversarialTests.dump(stack.queue)
        stack.clock.advance()
        await #expect(throws: expected) { try await stack.programs.save(broken) }
        #expect(try await ProgramRoundTripAdversarialTests.dump(stack.queue) == before)
        #expect(try await stack.programs.active() == base)
    }

    @Test(
        "NUL in an exercise's name or short name throws by column through save, seed and refresh",
        arguments: texts
    )
    func exerciseText_isRefused(text: String) async throws {
        let kit = try S2CatalogKit()
        let catalog = CatalogRefreshCloseoutAdversarialTests.catalog
        var named = catalog[0]
        named.name = text
        var short = catalog[0]
        short.shortName = text
        await #expect(throws: LedgerPersistenceError.nulInText("exercise.name")) {
            try await kit.exercises.save(named)
        }
        await #expect(throws: LedgerPersistenceError.nulInText("exercise.short_name")) {
            try await kit.exercises.seedIfNeeded([short], version: 1)
        }
        #expect(try await kit.dump().isEmpty)
        try await kit.exercises.seedIfNeeded(catalog, version: 1)
        let before = try await kit.dump()
        var refreshed = catalog
        refreshed[1].name = "Bench Press (v2)"
        refreshed[0] = short
        await #expect(throws: LedgerPersistenceError.nulInText("exercise.short_name")) {
            try await kit.exercises.seedIfNeeded(refreshed, version: 2)
        }
        await #expect(throws: LedgerPersistenceError.nulInText("exercise.name")) {
            try await kit.exercises.save(named)
        }
        #expect(try await kit.dump() == before, "a refused refresh or save wrote")
    }

    @Test("Other control characters and lookalikes of NUL are stored whole")
    func otherControls_roundTrip() async throws {
        let kit = try S2CatalogKit()
        for (index, text) in ["\u{1}", "\u{7F}", "\u{2400}", "\\0", "\u{FEFF}x", "\u{1F}\u{9}\u{D}"].enumerated() {
            let exercise = S2Kit.exercise(200 + index, "a\(text)b", short: text, isCustom: true)
            try await kit.exercises.save(exercise)
            #expect(try await kit.exercise(200 + index) == exercise)
        }
    }
}
