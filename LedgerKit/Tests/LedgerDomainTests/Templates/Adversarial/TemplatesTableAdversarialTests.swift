import Foundation
@testable import LedgerDomain
import Testing

/// F08 S1, G2 round 1: the whole input space (4 goals × 4 day counts × 2 units) against the tester's own
/// transcription of the brief's role table, its "Templates" list and spec §6.4 (`BriefTemplates`).
@Suite("Adversarial F08 S1 · every template against the brief", .tags(.domain))
struct TemplatesTableAdversarialTests {
    typealias Brief = BriefTemplates

    @Test("The transcription itself is whole: 32 inputs, 16 seed rows, every exercise in the tester's catalog rows")
    func transcription_isWhole() {
        #expect(Brief.Case.all.count == 32)
        #expect(Brief.upperLower.days.flatMap(\.lifts).count { $0.seed != nil } == 16)
        for days in DaysPerWeek.allCases {
            let split = Brief.split(days)
            #expect(split.days.count == days.rawValue)
            #expect(split.weekdays.count == days.rawValue)
            #expect(Brief.exerciseNames(days).isSubset(of: Brief.catalogRows.keys))
            #expect(split.days.allSatisfy { $0.lifts.first?.superset == false })
        }
        #expect(Set(DaysPerWeek.allCases.flatMap { Brief.exerciseNames($0) }) == Set(Brief.catalogRows.keys))
    }

    @Test(
        "Criteria 6 and 7: every slot of every day is the brief's, in every column but load and step",
        arguments: Brief.Case.all
    )
    func program_everySlot_matchesTheBrief(_ input: Brief.Case) throws {
        let program = try Brief.program(input)
        let exercises = try Brief.byID(Brief.catalog())
        let expected = try Brief.expectedSlots(goal: input.goal, days: input.days)
        try #require(program.days.count == expected.count, "\(input): \(program.days.map(\.name))")
        for (day, slots) in zip(program.days, expected) {
            let observed = day.slots.map { Brief.observed($0, exercises: exercises) }
            #expect(observed == slots, "\(input), \(day.name)")
        }
    }

    @Test("Every day carries the brief's name and tag, in the brief's order", arguments: Brief.Case.pounds)
    func program_dayNamesAndTags_matchTheBrief(_ input: Brief.Case) throws {
        let program = try Brief.program(input)
        let split = Brief.split(input.days)
        #expect(program.days.map(\.name) == split.days.map(\.name), "\(input)")
        #expect(program.days.map(\.tag) == split.days.map(\.tag), "\(input)")
        #expect(program.name == split.programName, "\(input)")
    }

    @Test(
        "Criteria 6 and 7, amendment 5: weeks 1–7 train every day; week 8 drops only the 4-day split's Saturday",
        arguments: Brief.Case.all
    )
    func program_schedule_matchesTheBrief(_ input: Brief.Case) throws {
        let program = try Brief.program(input)
        try #require(program.weeks.count == 8, "\(input)")
        for (index, week) in program.weeks.enumerated() {
            let expected = Brief.expectedSchedule(input.days, weekIndex: index).mapValues { program.days[$0].id }
            #expect(week.schedule == expected, "\(input), week \(index + 1)")
            #expect(week.index == index, "\(input)")
            #expect(week.isDeload == (index == 7), "\(input), week \(index + 1)")
            let trained = index == 7 && input.days == .four ? 3 : input.days.rawValue
            #expect(week.schedule.count == trained, "\(input), week \(index + 1)")
        }
    }

    @Test(
        "Criterion 4's data: the goal and day count are recorded, and the block is active and starts when asked",
        arguments: Brief.Case.all
    )
    func program_header_recordsThePicks(_ input: Brief.Case) throws {
        let start = Fixtures.civil(2027, 1, 3)
        let program = try Brief.program(input, startDate: start)
        #expect(program.id == Brief.programID)
        #expect(program.goal == input.goal)
        #expect(program.daysPerWeek == input.days.rawValue)
        #expect(program.startDate == start)
        #expect(program.isActive)
        #expect(program.weeks.count == ProgramTemplates.weekCount)
        #expect(ProgramTemplates.weekCount == 8)
    }

    @Test("Spec §6.4 by hand: both on four days in pounds, the rows a transcription slip would most likely miss")
    func bothFourDay_keyRows_areTheSeed() throws {
        let program = try Brief.program(Brief.Case(goal: .both, days: .four, units: .lb))
        let exercises = try Brief.byID(Brief.catalog())
        let rows = program.days.map { day in day.slots.map { Brief.observed($0, exercises: exercises).description } }
        #expect(rows == [
            [
                "Barbell Bench Press 5×5 (hi 7) RPE 8 150 s linear",
                "Incline DB Press 3×10 (hi 12) RPE 8 90 s double",
                "Chest-Supported Row 4×8 (hi 10) RPE 8 90 s linear",
                "Lat Pulldown 3×12 (hi 14) RPE 9 75 s double",
                "Cable Lateral Raise 3×15 (hi 17) RPE 9 60 s double superset"
            ],
            [
                "Back Squat 5×5 (hi 7) RPE 8 180 s linear",
                "Romanian Deadlift 3×8 (hi 10) RPE 8 120 s linear",
                "Leg Press 3×12 (hi 14) RPE 9 90 s double",
                "Standing Calf Raise 4×12 (hi 14) RPE 9 60 s fixed superset"
            ],
            [
                "Weighted Pull-Up 4×6 (hi 8) RPE 8 150 s linear",
                "Overhead Press 4×6 (hi 8) RPE 8 120 s linear",
                "Barbell Row 3×10 (hi 12) RPE 8 90 s linear",
                "Barbell Curl 3×12 (hi 14) RPE 9 60 s double drop 1"
            ],
            [
                "Deadlift 4×4 (hi 6) RPE 8 210 s linear",
                "Front Squat 3×8 (hi 10) RPE 8 120 s linear",
                "Seated Leg Curl 3×12 (hi 14) RPE 9 75 s double"
            ]
        ])
    }

    @Test(
        "The seed rows are the 4-day split's alone: both on 3, 5 and 6 days takes the role table for every lift",
        arguments: [DaysPerWeek.three, .five, .six]
    )
    func both_offTheFourDaySplit_takesTheRoleTable(_ days: DaysPerWeek) throws {
        let program = try Brief.program(Brief.Case(goal: .both, days: days, units: .lb))
        let exercises = try Brief.byID(Brief.catalog())
        let observed = program.days.flatMap(\.slots).map { Brief.observed($0, exercises: exercises) }
        let table = try #require(Brief.roleTable[.both])
        #expect(observed.allSatisfy { table.contains($0.scheme) }, "\(days): \(observed)")
        #expect(observed.allSatisfy { !$0.superset && $0.drop == 0 }, "\(days)")
    }

    @Test(
        "Other goals on four days keep §6.4's exercises, supersets and drop set and lose its prescriptions",
        arguments: [TrainingGoal.strength, .hypertrophy, .consistency]
    )
    func fourDay_otherGoals_keepFlagsAndTakeTheRoleTable(_ goal: TrainingGoal) throws {
        let program = try Brief.program(Brief.Case(goal: goal, days: .four, units: .lb))
        let seed = try Brief.program(Brief.Case(goal: .both, days: .four, units: .lb))
        let slots = program.days.flatMap(\.slots)
        let seedSlots = seed.days.flatMap(\.slots)
        #expect(slots.map(\.exerciseID) == seedSlots.map(\.exerciseID))
        #expect(slots.map(\.isSupersetWithPrevious) == seedSlots.map(\.isSupersetWithPrevious))
        #expect(slots.map(\.dropSets) == seedSlots.map(\.dropSets))
        #expect(slots.map(\.startLoad) == seedSlots.map(\.startLoad))
        #expect(slots.count { $0.isSupersetWithPrevious } == 2)
        #expect(slots.map(\.dropSets).reduce(0, +) == 1)
        // The calf raise is fixed only where the goal's accessory row says so (the brief's exception is §6.4's).
        let calf = try #require(program.days[1].slots.last)
        #expect(calf.progression == (goal == .consistency ? .fixed : goal == .strength ? .linear : .double))
    }
}

// MARK: - Onboarding's preview (criterion 3's data)

extension TemplatesTableAdversarialTests {
    @Test(
        "The preview lists the split's program name, and each day's name, tag and line, in order",
        arguments: DaysPerWeek.allCases
    )
    func preview_matchesTheBrief(_ days: DaysPerWeek) {
        let preview = ProgramTemplates.preview(days: days)
        let split = Brief.split(days)
        #expect(preview.programName == split.programName)
        #expect(preview.days.map(\.name) == split.days.map(\.name))
        #expect(preview.days.map(\.tag) == split.days.map(\.tag))
        #expect(preview.days.map(\.line) == split.days.map(\.line))
    }

    @Test("Spec §6.7's four lines, with Lower B as the brief corrects it")
    func preview_fourDay_isSpec67() {
        let preview = ProgramTemplates.preview(days: .four)
        let rows = preview.days.map { $0.name.replacing(" — ", with: " · ") + " — " + $0.line }
        #expect(rows == [
            "Upper A · Push focus — Bench, incline, row, pulldown, laterals",
            "Lower A · Squat focus — Squat, RDL, leg press, calves",
            "Upper B · Pull focus — Weighted pull-up, OHP, row, curls",
            "Lower B · Hinge focus — Deadlift, front squat, leg curl"
        ])
    }

    @Test("What the preview shows is what the program holds, for every goal", arguments: Brief.Case.all)
    func preview_agreesWithTheProgram(_ input: Brief.Case) throws {
        let preview = ProgramTemplates.preview(days: input.days)
        let program = try Brief.program(input)
        #expect(preview.programName == program.name, "\(input)")
        #expect(preview.days.map(\.name) == program.days.map(\.name), "\(input)")
        #expect(preview.days.map(\.tag) == program.days.map(\.tag), "\(input)")
    }

    @Test(
        "Tags are two capital letters, unique in a program, and names are unique and trimmed",
        arguments: DaysPerWeek.allCases
    )
    func preview_tagsAndNames_areWellFormed(_ days: DaysPerWeek) {
        let preview = ProgramTemplates.preview(days: days)
        #expect(Set(preview.days.map(\.tag)).count == days.rawValue)
        #expect(Set(preview.days.map(\.name)).count == days.rawValue)
        for day in preview.days {
            #expect(day.tag.count == 2 && day.tag.allSatisfy { $0.isUppercase && $0.isASCII }, "\(day.tag)")
            #expect(day.name == day.name.trimmingCharacters(in: .whitespacesAndNewlines) && !day.name.isEmpty)
            #expect(!day.line.isEmpty && day.line.first?.isUppercase == true, "\(day.line)")
        }
    }
}
