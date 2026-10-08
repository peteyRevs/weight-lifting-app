@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S6 adversarial round 1: the brief's worked examples on the spec's seed program, word for word
/// (criteria 7 and 8 of the brief; criteria 2 to 6 of the slice). Every expected text is written here from the
/// brief and product spec §3.4; the minutes are `TimeEstimate`'s (39 for Upper A, by S5's ruling).
@Suite("Adversarial F11 S6 · the seed program on the Day editor", .tags(.feature))
nonisolated struct DayEditorSeedAdversarialTests {
    @Test("Upper A's header reads Program, DAY 1 OF 4, Done, its name and tag, and week 1's counts")
    func seed_upperA_headerReadsAsTheBrief() throws {
        let content = try #require(try AdvDay.content(AdvDay.seed(day: 0)))
        #expect(content.header.back.title == "Program")
        #expect(content.header.back.action == .route(.closeDay))
        #expect(content.header.position == "DAY 1 OF 4")
        #expect(content.header.done.title == "Done")
        #expect(content.header.done.action == .route(.closeDay))
        #expect(content.header.name == "Upper A — Push focus")
        #expect(content.header.tag == "UA")
        #expect(content.header.meta == "Week 1 · 5 exercises · 18 sets · ~39 min")
        #expect(content.addExercise.title == "+ Add exercise from library")
        #expect(content.addExercise.action == .openLibrary)
    }

    @Test("Upper A's rows read 1, 2, 3, 4A, 4B with the spec's sub lines, schemes and loads")
    func seed_upperA_rowsReadAsTheSpec() throws {
        let content = try #require(try AdvDay.content(AdvDay.seed(day: 0)))
        let rows = content.groups.flatMap(\.rows)
        #expect(rows.map(\.index) == ["1", "2", "3", "4A", "4B"])
        #expect(rows.map(\.sub) == [
            "Barbell · +5/wk · RPE 8 · 2:30 rest",
            "Dumbbell · Reps 10–12 · RPE 8 · 1:30 rest",
            "Machine · +2.5/wk · RPE 8 · 1:30 rest",
            "Cable · Reps 12–14 · RPE 9 · no rest",
            "Cable · Reps 15–17 · RPE 9 · 1:15 rest"
        ])
        #expect(rows.map(\.scheme) == ["5×5", "3×10", "4×8", "3×12", "3×15"])
        #expect(rows.map(\.load) == ["180 lb", "50 lb", "65 lb", "100 lb", "12.5 lb"])
        #expect(rows.map(\.name).prefix(2) == ["Barbell Bench Press", "Incline DB Press"])
        #expect(content.groups.map { $0.header?.title } == [nil, nil, nil, "SUPERSET"])
        #expect(content.groups.last?.header?.note == "2 exercises back to back · rest after B")
        #expect(rows[3].spokenLabel == "4A, \(rows[3].name)")
        #expect(rows[3].spokenValue == "3×12 · 100 lb · Cable · Reps 12–14 · RPE 9 · no rest")
        #expect(rows.allSatisfy { $0.panel == nil && !$0.isOpen })
    }

    @Test("Criterion 7: Incline DB Press's strip reads W1 50 · W2 50 · W3 50 · W4 52.5 … and its reps follow rule 10")
    func seed_inclinePress_stripAndRepsReadAsTheBrief() throws {
        let details = try #require(try AdvDay.panel(AdvDay.seed(day: 0, open: 1))?.details)
        let strip = "W1 50 · W2 50 · W3 50 · W4 52.5 · W5 52.5 · W6 52.5 · W7 55 · W8 47.5 (deload)"
        #expect(details.strip.text == strip)
        #expect(details.strip.entries.map(\.text).joined(separator: " · ") == strip)
        #expect(details.strip.entries.map(\.isShown) == [true] + Array(repeating: false, count: 7))
        #expect(details.week.eyebrow == "WEEK 1")
        #expect(details.week.line == "3 × 10 @ 50 lb · RPE 8")
        var lines: [String] = []
        for week in 1 ..< 8 {
            try lines.append(#require(AdvDay.panel(AdvDay.seed(day: 0, week: week, open: 1))?.details).week.line)
        }
        #expect(lines == [
            "3 × 11 @ 50 lb · RPE 8", "3 × 12 @ 50 lb · RPE 8", "3 × 10 @ 52.5 lb · RPE 8",
            "3 × 11 @ 52.5 lb · RPE 8", "3 × 12 @ 52.5 lb · RPE 8", "3 × 10 @ 55 lb · RPE 8",
            "2 × 11 @ 47.5 lb · RPE 6"
        ])
    }

    @Test("Criterion 7: Back Squat in week 8 reads W8 240 (deload) under the eyebrow WEEK 8 · DELOAD")
    func seed_backSquat_weekEight_readsDeload() throws {
        let input = try AdvDay.seed(day: 1, week: 7, open: 0)
        let details = try #require(AdvDay.panel(input)?.details)
        #expect(details.week.eyebrow == "WEEK 8 · DELOAD")
        #expect(details.week.isDeload)
        #expect(details.week.line == "4 × 5 @ 240 lb · RPE 6")
        #expect(details.strip.entries.last?.text == "W8 240 (deload)")
        #expect(details.strip.text == "W1 250 · W2 255 · W3 260 · W4 265 · W5 270 · W6 275 · W7 280 · W8 240 (deload)")
        let row = try #require(AdvDay.rows(input).first)
        #expect(row.scheme == "4×5")
        #expect(row.load == "240 lb")
    }

    @Test("Criterion 7: the week after a missed one reads · HELD, and its load is the missed week's")
    func seed_benchPress_afterAMiss_readsHeld() throws {
        var input = try AdvDay.seed(day: 0, week: 3, open: 0)
        input.program.days[0].slots[0].misses = [2]
        let details = try #require(AdvDay.panel(input)?.details)
        #expect(details.week.eyebrow == "WEEK 4 · HELD")
        #expect(details.week.isHeld)
        #expect(details.week.line == "5 × 5 @ 190 lb · RPE 8")
        #expect(details.strip.entries.map(\.isHeld) == [false, false, false, true, false, false, false, false])
        #expect(details.strip.entries.map { $0.text.hasPrefix("W") } == Array(repeating: true, count: 8))
        #expect(details.strip.entries[2].text == "W3 190")
        #expect(details.strip.entries[3].text.hasPrefix("W4 190"))
        #expect(details.strip.entries[4].text == "W5 195")
        input.weekIndex = 2
        #expect(AdvDay.panel(input)?.details?.week.eyebrow == "WEEK 3")
    }

    @Test("Criterion 8: Bench Press's steppers read SETS 5, REPS 5, START LOAD 180 lb, TARGET RPE 8, REST 2:30")
    func seed_benchPress_steppersReadAsTheBrief() throws {
        let fields = try #require(try AdvDay.panel(AdvDay.seed(day: 0, open: 0))?.details).fields
        #expect(fields.map(\.label) == ["SETS", "REPS", "START LOAD", "TARGET RPE", "REST"])
        #expect(fields.map(\.value) == ["5", "5", "180 lb", "8", "2:30"])
        #expect(fields.map(\.spokenLabel) == ["Sets", "Reps", "Start load", "Target RPE", "Rest"])
        let double = try #require(try AdvDay.panel(AdvDay.seed(day: 0, open: 1))?.details).fields
        #expect(double.map(\.label) == ["SETS", "REP FLOOR", "TOP OF RANGE", "START LOAD", "TARGET RPE", "REST"])
        #expect(double.map(\.value) == ["3", "10", "12", "50 lb", "8", "1:30"])
        #expect(double.map(\.spokenLabel) == ["Sets", "Rep floor", "Top of range", "Start load", "Target RPE", "Rest"])
    }

    @Test("Criterion 8: rest reads 45s, 2 min and 2:30", arguments: [(45, "45s"), (120, "2 min"), (150, "2:30")])
    func seed_rest_readsAsTheBrief(seconds: Int, text: String) throws {
        var input = try AdvDay.seed(day: 0, open: 0)
        let open = try #require(input.openSlot)
        input.program.days[0] = DayEditing.set(.restSeconds(seconds), slot: open, in: input.program.days[0])
        #expect(AdvDay.field(.rest, input)?.value == text)
        #expect(AdvDay.rows(input).first?.sub == "Barbell · +5/wk · RPE 8 · \(text) rest")
    }
}

nonisolated extension DayEditorSeedAdversarialTests {
    @Test("The progression notes and the drop set read as the brief gives them")
    func seed_progressionAndDropSet_readAsTheBrief() throws {
        let linear = try #require(try AdvDay.panel(AdvDay.seed(day: 0, open: 0))?.details)
        #expect(linear.progression.title == "PROGRESSION")
        #expect(linear.progression.chips.map(\.title) == ["Linear", "Double", "Fixed"])
        #expect(linear.progression.chips.map(\.isSelected) == [true, false, false])
        #expect(linear.progression.note == "Adds 5 lb a week from 180 lb. A week with a missed set holds the load.")
        #expect(linear.dropSet.title == "Drop set")
        #expect(linear.dropSet.note == "One extra set at −15% after the last working set.")
        #expect(linear.dropSet.isOn == false)
        let double = try #require(try AdvDay.panel(AdvDay.seed(day: 0, open: 1))?.details)
        #expect(double.progression.note == "Adds a rep each week up to 12, then +2.5 lb back at 10.")
        let fixed = try #require(try AdvDay.panel(AdvDay.seed(day: 1, open: 3))?.details)
        #expect(fixed.progression.note == "Stays at 160 lb for the whole block.")
        #expect(try AdvDay.rows(AdvDay.seed(day: 1))[3].sub == "Machine · Fixed · RPE 9 · 1:30 rest")
        let curl = try AdvDay.seed(day: 2, open: 3)
        let dropped = try #require(AdvDay.panel(curl)?.details)
        #expect(dropped.dropSet.isOn)
        #expect(dropped.dropSet.note == "One extra set at −15%, straight after the last working set.")
        #expect(AdvDay.rows(curl)[3].sub == "Barbell · Reps 12–14 · drop · RPE 9 · 1 min rest")
        #expect(AdvDay.content(curl)?.header.meta == "Week 1 · 4 exercises · 15 sets · ~37 min")
    }

    @Test("Delete day reads Delete Lower B?, It's scheduled in 8 weeks, in 1 week, and nothing for nowhere")
    func seed_deleteDay_readsItsThreeForms() throws {
        var input = try AdvDay.seed(day: 3)
        var delete = try #require(AdvDay.content(input)?.deleteDay)
        #expect(delete.title == "Delete day")
        #expect(delete.confirmation.title == "Delete Lower B?")
        #expect(delete.confirmation.message == "It's scheduled in 7 weeks. Those days become rest.")
        #expect(delete.confirmation.confirm.title == "Delete")
        #expect(delete.confirmation.cancel == "Cancel")
        #expect(AdvDay.edit(of: delete.confirmation.confirm.action) == .deleteDay(input.day))
        input.program = ProgramEditing.setSchedule(input.program, week: 7, weekday: .sunday, day: input.day)
        delete = try #require(AdvDay.content(input)?.deleteDay)
        #expect(delete.confirmation.message == "It's scheduled in 8 weeks. Those days become rest.")
        for week in 1 ..< 8 {
            for weekday in Weekday.allCases {
                input.program = ProgramEditing.setSchedule(input.program, week: week, weekday: weekday, day: nil)
            }
        }
        input.program = ProgramEditing.setSchedule(input.program, week: 0, weekday: .sunday, day: input.day)
        delete = try #require(AdvDay.content(input)?.deleteDay)
        #expect(delete.confirmation.message == "It's scheduled in 1 week. Those days become rest.")
        input.program.weeks[0].schedule = [:]
        delete = try #require(AdvDay.content(input)?.deleteDay)
        #expect(delete.confirmation.message == nil)
        #expect(delete.confirmation.title == "Delete Lower B?")
        input.program = ProgramEditing.renameDay(input.program, day: input.day, to: "Arms")
        #expect(AdvDay.content(input)?.deleteDay.confirmation.title == "Delete Arms?")
    }

    @Test("The tester's own screen agrees with the model for every seed day, week, unit and open slot")
    func seed_everyDayWeekUnitAndOpenSlot_agreesWithTheTestersScreen() throws {
        var differences: [String] = []
        var compared = 0
        for place in 0 ..< 4 {
            let slots = try Fixtures.seedProgram().days[place].slots.count
            for units in Units.allCases {
                for week in 0 ..< 7 {
                    for open in [nil] + (0 ..< slots).map(Optional.some) {
                        let input = try AdvDay.seed(day: place, units: units, week: week, open: open)
                        differences += AdvDayScreen.differences(input).map { "day \(place) \(units) w\(week): \($0)" }
                        compared += 1
                    }
                }
            }
        }
        let agrees = differences.isEmpty
        #expect(agrees, "\(differences.count) differ: \(differences.prefix(4))")
        #expect(compared == 280)
    }
}
