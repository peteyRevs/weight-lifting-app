import Foundation
import GRDB
import LedgerDomain
@testable import LedgerPersistence
import LedgerTestSupport
import Testing

/// Invalid stored program data is surfaced as an error, never a crash: every column is read strictly, and the
/// rows are validated through `Slot.init` and `Program.init` as on construction. The damaged row is kept, and a
/// save of a valid program repairs it, since a save compares stored rows as column values and never decodes them.
@Suite("GRDBProgramRepository · invalid stored data", .tags(.persistence), .timeLimit(.minutes(1)))
struct DamagedProgramRowTests {
    /// The error a damage must surface as.
    enum Surfaced: Equatable, Sendable {
        case persistence(LedgerPersistenceError)
        case slot(SlotValidationError)
        case program(ProgramValidationError)

        init?(_ error: any Error) {
            switch error {
            case let error as LedgerPersistenceError: self = .persistence(error)
            case let error as SlotValidationError: self = .slot(error)
            case let error as ProgramValidationError: self = .program(error)
            default: return nil
            }
        }
    }

    /// An `UPDATE` of the stored contract program, and what reading it must throw.
    struct Damage: Sendable, CustomStringConvertible {
        let description: String
        let surfaced: Surfaced
    }

    static let stored = Result { try ProgramRepositoryContract.program() }
    static let unknownDay = DayTemplateID(EventBuilders.uuid(0xDA7))

    /// A damage to the first slot of the first day.
    static func slot(_ assignment: String, _ surfaced: Surfaced) -> Damage {
        let first = "position = 0 AND day_template_id = (SELECT id FROM day_template WHERE position = 0)"
        return Damage(description: "slot SET \(assignment) WHERE \(first)", surfaced: surfaced)
    }

    static let damages = [
        slot("rpe_x2 = 7", .slot(.rpeOutOfRange(3.5))),
        slot("sets = 99", .slot(.setsOutOfRange(99))),
        slot("rest_seconds = 100", .slot(.restOutOfRange(seconds: 100))),
        slot("step_e7g = 0", .slot(.nonPositiveStep(.zero))),
        slot("progression = 'wave'", .persistence(.malformedColumn("slot.progression"))),
        slot("sets = 'x'", .persistence(.malformedColumn("slot.sets"))),
        slot("sets = 3.5", .persistence(.malformedColumn("slot.sets"))),
        slot("is_superset_with_previous = 'yes'", .persistence(.malformedColumn("slot.is_superset_with_previous"))),
        slot("start_load_e7g = 0.5", .persistence(.malformedColumn("slot.start_load_e7g"))),
        Damage(
            description: "program SET start_date = '2026-13-01'",
            surfaced: .persistence(.malformedColumn("program.start_date"))
        ),
        Damage(description: "program SET goal = 'power'", surfaced: .persistence(.malformedColumn("program.goal"))),
        Damage(
            description: "program SET days_per_week = 'four'",
            surfaced: .persistence(.malformedColumn("program.days_per_week"))
        ),
        Damage(
            description: "program_week SET week_index = 9 WHERE week_index = 3",
            surfaced: .program(.nonContiguousWeeks(indices: [0, 1, 2, 4, 5, 6, 7, 9]))
        ),
        Damage(
            description: "program_week SET deleted_at = 'then' WHERE week_index > 0",
            surfaced: .program(.tooFewWeeks(count: 1))
        ),
        Damage(
            description: "program_week SET tue = '\(ColumnCodec.text(unknownDay))' WHERE week_index = 0",
            surfaced: .program(.danglingSchedule(weekIndex: 0, dayTemplateID: unknownDay))
        ),
        Damage(
            description: "program_week SET wed = 'not-a-uuid' WHERE week_index = 0",
            surfaced: .persistence(.malformedIdentifier("not-a-uuid"))
        ),
        Damage(
            description: "day_template SET name = x'80' WHERE position = 1",
            surfaced: .persistence(.malformedColumn("day_template.name"))
        ),
        Damage(
            description: "slot_miss SET week_index = 'two' WHERE rowid = 1",
            surfaced: .persistence(.malformedColumn("slot_miss.week_index"))
        )
    ]

    @Test(
        "A damaged row fails every read by name, ends observeActive, is kept, and a save repairs it",
        arguments: damages
    )
    func damagedRow_failsReads_isKept_andASaveRepairsIt(_ damage: Damage) async throws {
        let repositories = try await Repositories.withProgramExercises()
        let programs = repositories.programs
        let program = try Self.stored.get()
        try await programs.save(program)
        try await repositories.execute("UPDATE \(damage)")
        let reads: [@Sendable () async throws -> Program?] = [
            { try await programs.active() },
            { try await programs.program(id: program.id) }
        ]
        for read in reads {
            do {
                let value = try await read()
                Issue.record("read \(String(describing: value)) instead of throwing \(damage.surfaced)")
            } catch {
                #expect(Surfaced(error) == damage.surfaced, "threw \(error)")
            }
        }
        var emitted = 0
        for await _ in programs.observeActive() {
            emitted += 1
        }
        #expect(emitted == 0)
        await #expect(throws: (any Error).self, "the damage is kept") { try await programs.active() }
        try await programs.save(program)
        #expect(try await programs.active() == program)
    }
}
