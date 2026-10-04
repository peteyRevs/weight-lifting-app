import Foundation
@testable import LedgerDomain
import Testing

/// The four splits and the role table against the brief's lists (`TemplateOracle`), and the preview onboarding's
/// last step shows (the data half of F08 criterion 3).
@Suite("ProgramTemplates · splits, roles and preview", .tags(.domain))
struct ProgramTemplatesSplitsTests {
    @Test("A block has the brief's program name, days, tags and exercises, in order", arguments: TemplateCase.pairs)
    func program_everyGoalAndSplit_isTheBriefsTemplate(_ block: TemplateCase) throws {
        let catalog = try BundledCatalog.byID()
        let expected = TemplateOracle.split(for: block.days)
        let program = try block.program()
        #expect(program.name == expected.name)
        #expect(program.days.map(\.name) == expected.days.map(\.name))
        #expect(program.days.map(\.tag) == expected.days.map(\.tag))
        let names = program.days.map { day in day.slots.map { catalog[$0.exerciseID]?.name ?? "?" } }
        #expect(names == expected.days.map(\.exercises))
    }

    @Test(
        "A slot prescribes what the role table gives its role for the goal; the seed takes spec §6.4",
        arguments: TemplateCase.pairs
    )
    func program_everySlot_takesItsRolesScheme_exceptTheSeed(_ block: TemplateCase) throws {
        let table = try #require(TemplateOracle.roleTable[block.goal])
        let isSeed = block.goal == .both && block.days == .four
        let expected = try TemplateOracle.split(for: block.days).days.map { day in
            try day.roles.map { try #require(table[$0]) }
        }
        let schemes = try block.program().days.map { $0.slots.map(TemplateOracle.Scheme.init) }
        #expect(schemes.map(\.count) == expected.map(\.count))
        if isSeed {
            #expect(Array(schemes.joined()) == TemplateOracle.seedRows.map(\.scheme))
            #expect(schemes != expected)
        } else {
            #expect(schemes == expected)
        }
    }

    @Test("Only the 4-day split has supersets and a drop set", arguments: TemplateCase.pairs)
    func program_supersetsAndDropSets_areTheFourDaySplitsOnly(_ block: TemplateCase) throws {
        let slots = try block.program().days.flatMap(\.slots)
        #expect(slots.count { $0.isSupersetWithPrevious } == (block.days == .four ? 2 : 0))
        #expect(slots.map(\.dropSets).reduce(0, +) == (block.days == .four ? 1 : 0))
        // A superset needs a lift before it.
        #expect(try block.program().days.allSatisfy { $0.slots.first?.isSupersetWithPrevious == false })
    }

    @Test("The splits train on the brief's weekdays", arguments: [
        (DaysPerWeek.three, [Weekday.monday, .wednesday, .friday]),
        (.four, [.monday, .wednesday, .friday, .saturday]),
        (.five, [.monday, .tuesday, .wednesday, .friday, .saturday]),
        (.six, [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
    ])
    func program_schedule_isOnTheBriefsWeekdays(days: DaysPerWeek, weekdays: [Weekday]) throws {
        let program = try TemplateCase(goal: .hypertrophy, days: days).program()
        let firstWeek = try #require(program.week(at: 0)).schedule
        #expect(firstWeek.keys.sorted() == weekdays)
        #expect(weekdays.map { firstWeek[$0] } == program.days.map(\.id))
    }

    @Test("The 4-day preview is spec §6.7's step 3, Lower B without its abs")
    func preview_fourDay_matchesSpec67() {
        let preview = ProgramTemplates.preview(days: .four)
        #expect(preview.programName == "Upper / Lower")
        // Spec §6.7 writes each option as "label — sub", the label being the day's name with " · " for " — ".
        let options = preview.days.map { "\($0.name.replacing(" — ", with: " · ")) — \($0.exercises)" }
        #expect(options == [
            "Upper A · Push focus — Bench, incline, row, pulldown, laterals",
            "Lower A · Squat focus — Squat, RDL, leg press, calves",
            "Upper B · Pull focus — Weighted pull-up, OHP, row, curls",
            "Lower B · Hinge focus — Deadlift, front squat, leg curl"
        ])
        #expect(preview.days.map(\.tag) == ["UA", "LA", "UB", "LB"])
    }

    @Test(
        "Every split's preview is the brief's program name, day names, tags and lines",
        arguments: DaysPerWeek.allCases
    )
    func preview_everySplit_isTheBriefs(days: DaysPerWeek) {
        let expected = TemplateOracle.split(for: days)
        let preview = ProgramTemplates.preview(days: days)
        #expect(preview.programName == expected.name)
        #expect(preview.days.count == days.rawValue)
        #expect(preview.days.map(\.name) == expected.days.map(\.name))
        #expect(preview.days.map(\.tag) == expected.days.map(\.tag))
        #expect(preview.days.map(\.exercises) == expected.days.map(\.preview))
        #expect(Set(preview.days.map(\.tag)).count == days.rawValue)
    }

    @Test("The preview lists the days the generated program has, whatever the goal", arguments: TemplateCase.pairs)
    func preview_matchesTheGeneratedDays(_ block: TemplateCase) throws {
        let program = try block.program()
        let preview = ProgramTemplates.preview(days: block.days)
        #expect(preview.programName == program.name)
        #expect(preview.days.map(\.name) == program.days.map(\.name))
        #expect(preview.days.map(\.tag) == program.days.map(\.tag))
    }

    @Test("A day's preview line names one thing per lift: no line promises what its day lacks")
    func preview_linesCountTheDaysLifts() throws {
        for days in DaysPerWeek.allCases {
            let program = try TemplateCase(goal: .both, days: days).program()
            for (line, day) in zip(ProgramTemplates.preview(days: days).days, program.days) {
                #expect(line.exercises.split(separator: ", ").count == day.slots.count, "\(day.tag): \(line.exercises)")
            }
        }
    }
}
