@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S6 adversarial round 1: the whole screen against the tester's own, for days drawn from seeds, and the
/// superset letters and headers for every grouping of up to six slots (criteria 2 to 5 of the slice; product
/// spec §7.7 rule 44). Seeds 1 to 25.
@Suite("Adversarial F11 S6 · the Day editor's model on seeded days", .tags(.feature))
nonisolated struct DayEditorModelAdversarialTests {
    static let seeds: ClosedRange<UInt64> = 1 ... 25

    /// The weeks of `program` that are not a deload, or all of them.
    static func weeks(of program: Program, deloads: Bool) -> [Int] {
        program.weeks.indices.filter { program.weeks[$0].isDeload == deloads }
    }

    @Test("Every seeded day, in both units, outside a deload week, with each slot open, is the tester's screen")
    func seededDays_outsideADeload_agreeWithTheTestersScreen() throws {
        var differences: [String] = []
        var compared = 0
        for seed in Self.seeds {
            let (program, dayID) = try AdvDay.random(seed: seed)
            let slots = program.days[1].slots
            for units in Units.allCases {
                for week in Self.weeks(of: program, deloads: false) {
                    for opened in [nil] + slots.map(\.id) {
                        let input = AdvDay.input(
                            program, day: dayID, exercises: AdvDay.stored(), units: units, week: week, open: opened
                        )
                        differences += AdvDayScreen.differences(input).map { "seed \(seed) \(units) w\(week): \($0)" }
                        compared += 1
                    }
                }
            }
        }
        let agrees = differences.isEmpty
        #expect(agrees, "\(differences.count) differ: \(differences.prefix(4))")
        #expect(compared > 600)
    }

    @Test("In a deload week the rows, the meta line and the panel count that week's own sets, load and RPE")
    func seededDays_inADeloadWeek_agreeWithTheTestersScreen() throws {
        var differences: [String] = []
        var compared = 0
        for seed in Self.seeds {
            let (program, dayID) = try AdvDay.random(seed: seed)
            let slots = program.days[1].slots
            for units in Units.allCases {
                for week in Self.weeks(of: program, deloads: true) {
                    for opened in [nil] + slots.map(\.id) {
                        let input = AdvDay.input(
                            program, day: dayID, exercises: AdvDay.stored(), units: units, week: week, open: opened
                        )
                        differences += AdvDayScreen.differences(input).map { "seed \(seed) \(units) w\(week): \($0)" }
                        compared += 1
                    }
                }
            }
        }
        let agrees = differences.isEmpty
        #expect(agrees, "\(differences.count) differ: \(differences.prefix(4))")
        #expect(compared > 100)
    }

    @Test(
        "A week before the block reads as week 1 and one after it as the last week",
        arguments: [1, 7, 23] as [UInt64]
    )
    func weekOutOfRange_readsAsTheNearestWeek(seed: UInt64) throws {
        let (program, dayID) = try AdvDay.random(seed: seed)
        let open = program.days[1].slots.first?.id
        for week in [Int.min, -1000, -1, program.weeks.count, program.weeks.count + 1, 1000, Int.max] {
            let input = AdvDay.input(program, day: dayID, exercises: AdvDay.stored(), week: week, open: open)
            var nearest = input
            nearest.weekIndex = week < 0 ? 0 : program.weeks.count - 1
            let isNearest = DayEditorPresentation.make(input) == DayEditorPresentation.make(nearest)
            #expect(isNearest, "week \(week)")
            let expected = "Week \(nearest.weekIndex + 1)"
            #expect(AdvDay.content(input)?.header.meta.hasPrefix(expected) == true, "week \(week)")
        }
    }

    // MARK: - Letters and headers

    /// A day of `count` plain slots joined by the bits of `pattern`: bit i joins slot i + 1 to slot i.
    static func day(count: Int, pattern: Int) throws -> (Program, DayTemplate) {
        let slots = try (0 ..< count).map { place in
            try AdvProgram.slot(place, exercise: place, joined: place > 0 && (pattern >> (place - 1)) & 1 == 1)
        }
        let day = AdvProgram.day(1, slots: slots)
        return try (AdvProgram.program(weeks: 2, days: [day]), day)
    }

    static func exercises() -> [ExerciseID: Exercise] {
        Dictionary(uniqueKeysWithValues: (0 ..< 40).map { AdvProgram.exercise($0) }.map { ($0.id, $0) })
    }

    @Test("Every grouping of one to six slots has DayEditing's groups, lettered A, B, … with the rest after the last")
    func everyGrouping_upToSixSlots_isLetteredAsTheDomainGroupsIt() throws {
        var wrong: [String] = []
        var groupings = 0
        for count in 1 ... 6 {
            for pattern in 0 ..< (1 << (count - 1)) {
                let (program, day) = try Self.day(count: count, pattern: pattern)
                let input = AdvDay.input(program, day: day.id, exercises: Self.exercises())
                let content = try #require(AdvDay.content(input))
                let groups = DayEditing.groups(of: day)
                var indices: [String] = []
                var notes: [String?] = []
                var rests: [Bool] = []
                for (place, ids) in groups.enumerated() {
                    let letters = ["A", "B", "C", "D", "E", "F"]
                    indices += ids.indices.map { ids.count > 1 ? "\(place + 1)\(letters[$0])" : "\(place + 1)" }
                    notes.append(
                        ids
                            .count > 1 ? "\(ids.count) exercises back to back · rest after \(letters[ids.count - 1])" :
                            nil
                    )
                    rests += ids.indices.map { $0 == ids.count - 1 }
                }
                let rows = content.groups.flatMap(\.rows)
                let isRight = content.groups.map { $0.rows.map(\.id) } == groups
                    && rows.map(\.index) == indices
                    && content.groups.map { $0.header?.note } == notes
                    && content.groups.map { $0.header?.title } == notes.map { $0 == nil ? nil : "SUPERSET" }
                    && rows.map { $0.sub.hasSuffix("1:30 rest") } == rests
                    && rows.map { $0.sub.hasSuffix("· no rest") } == rests.map { !$0 }
                    && content.groups.map(\.id) == groups.map(\.first)
                if !isRight {
                    wrong.append("\(count) slots, pattern \(pattern): \(rows.map(\.index))")
                }
                groupings += 1
            }
        }
        let allRight = wrong.isEmpty
        #expect(allRight, "\(wrong.prefix(4))")
        #expect(groupings == 63)
    }

    @Test("A stored day whose first slot is joined to nothing before it is drawn as its normal form")
    func firstSlotJoined_isDrawnAsItsNormalForm() throws {
        var (program, day) = try Self.day(count: 3, pattern: 0b10)
        program.days[0].slots[0].isSupersetWithPrevious = true
        let input = AdvDay.input(program, day: day.id, exercises: Self.exercises(), open: day.slots[0].id)
        let rows = AdvDay.rows(input)
        #expect(rows.map(\.index) == ["1", "2A", "2B"])
        #expect(AdvDay.panel(input)?.supersetActions.map(\.title) == ["Superset with next"])
        #expect(AdvDay.panel(input)?.moveUp == nil)
    }

    @Test("A superset of thirty exercises is drawn without a trap and every row keeps an index of its own")
    func supersetOfThirty_isDrawn() throws {
        let (program, day) = try Self.day(count: 30, pattern: Int.max)
        let input = AdvDay.input(program, day: day.id, exercises: Self.exercises(), open: day.slots[29].id)
        let rows = AdvDay.rows(input)
        #expect(rows.count == 30)
        #expect(Set(rows.map(\.index)).count == 30)
        #expect(rows.prefix(5).map(\.index) == ["1A", "1B", "1C", "1D", "1E"])
        #expect(rows.allSatisfy { !$0.index.isEmpty && !$0.spokenLabel.isEmpty })
        let note = AdvDay.content(input)?.groups.first?.header?.note ?? ""
        #expect(note.hasPrefix("30 exercises back to back · rest after "))
        #expect(note.count > "30 exercises back to back · rest after ".count)
    }
}
