@testable import FeatureProgram
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F11 S6 adversarial round 2: the rest a superset shows, the estimate and the set counts after the Domain
/// took them over (criteria 11 to 13 of the slice after round 1). The three callers of the group's rest must
/// agree: the Day editor's row, the workout built from the same day, and `TimeEstimate.minutes`. The expected
/// values are the tester's own: the longest of the members' rests, decision #14's formula written out here,
/// and a plain sum of sets. Seeds 1 to 40.
@Suite("Adversarial F11 S6 · a superset's rest, the estimate and the set counts", .tags(.feature))
nonisolated struct DayEditorSupersetRestAdversarialTests {
    /// A day of `count` slots joined by the bits of `pattern`, with rests and sets drawn from `seed`; slot
    /// `drop`, if any, ends on a drop set.
    static func day(count: Int, pattern: Int, seed: UInt64) throws -> DayTemplate {
        var rng = SplitMix64(seed: seed)
        let slots = try (0 ..< count).map { place in
            try AdvProgram.slot(
                place,
                exercise: place,
                sets: Int.random(in: 1 ... 6, using: &rng),
                rest: 30 + 15 * Int.random(in: 0 ... 18, using: &rng),
                joined: place > 0 && (pattern >> (place - 1)) & 1 == 1,
                drop: Int.random(in: 0 ... 3, using: &rng) == 0 ? 1 : 0
            )
        }
        return AdvProgram.day(1, slots: slots)
    }

    /// Decision #14 as it stood before this round, written out: every set and drop set takes 42 s, and every
    /// group rests once a round for its longest member's rest.
    static func minutes(_ day: DayTemplate, _ shown: [SlotID: Prescription]) -> Int {
        var seconds = 0
        let slots = Dictionary(uniqueKeysWithValues: day.slots.map { ($0.id, $0) })
        for ids in DayEditing.groups(of: day) {
            let members = ids.compactMap { slots[$0] }
            let sets = members.map { shown[$0.id]?.sets ?? $0.sets }
            let work = zip(sets, members).reduce(0) { $0 + ($1.0 + $1.1.dropSets) * 42 }
            let rounds = (sets.max() ?? 0) + (members.map(\.dropSets).max() ?? 0)
            seconds += work + rounds * (members.map { (shown[$0.id]?.rest ?? $0.rest).seconds }.max() ?? 0)
        }
        return (seconds + 30) / 60
    }

    /// The label of the rest each group of the day's workout takes after a round, by the call the engine's
    /// reducer makes when a round's last set is logged.
    static func workoutRests(_ program: Program, _ day: DayTemplate) throws -> [String] {
        let session = try SessionBuilder.build(
            program: program, weekIndex: 0, day: day, exercises: DayEditorModelAdversarialTests.exercises(),
            history: [:], settings: .default, id: WorkoutID(Fixtures.uuid(9100)), device: Fixtures.deviceID,
            now: Fixtures.now
        )
        return SupersetRounds.blocks(in: session.exercises).map {
            SupersetRounds.groupRest(block: $0, exercises: session.exercises).label
        }
    }

    @Test("Every grouping of up to six slots with rests that differ shows the longest, as the workout rests")
    func everyGrouping_withDifferingRests_showsTheRestTheWorkoutTakes() throws {
        var wrong: [String] = []
        var groups = 0
        for count in 1 ... 6 {
            for pattern in 0 ..< (1 << (count - 1)) {
                let day = try Self.day(count: count, pattern: pattern, seed: UInt64(count * 100 + pattern))
                let program = try AdvProgram.program(weeks: 2, days: [day])
                let input = AdvDay.input(program, day: day.id, exercises: DayEditorModelAdversarialTests.exercises())
                let content = try #require(AdvDay.content(input))
                let slots = Dictionary(uniqueKeysWithValues: day.slots.map { ($0.id, $0) })
                let longest = DayEditing.groups(of: day).map { ids in
                    ids.compactMap { slots[$0]?.rest }.max()?.label ?? "?"
                }
                let drawn = content.groups.map { group in
                    group.rows.last.map { String($0.sub.split(separator: " · ").last ?? "") } ?? "?"
                }
                let silent = content.groups.flatMap { $0.rows.dropLast() }.allSatisfy { $0.sub.hasSuffix("· no rest") }
                let isRight = try drawn == longest.map { "\($0) rest" } && silent
                    && Self.workoutRests(program, day) == longest
                    && TimeEstimate.minutes(day: day, prescriptions: [:]) == Self.minutes(day, [:])
                if !isRight {
                    wrong.append("\(count) slots, pattern \(pattern): drawn \(drawn), longest \(longest)")
                }
                groups += longest.count
            }
        }
        let allRight = wrong.isEmpty
        #expect(allRight, "\(wrong.prefix(3))")
        #expect(groups == 192)
    }

    @Test("The longest rest is shown wherever it stands in the superset: first, middle or last")
    func longestRest_atAnyPlaceOfTheSuperset_isShownAfterTheLast() throws {
        for place in 0 ..< 3 {
            let slots = try (0 ..< 3).map {
                try AdvProgram.slot($0, exercise: $0, rest: $0 == place ? 165 : 45 + 15 * $0, joined: $0 > 0)
            }
            let day = AdvProgram.day(1, slots: slots)
            let program = try AdvProgram.program(weeks: 2, days: [day])
            let exercises = DayEditorModelAdversarialTests.exercises()
            let input = AdvDay.input(program, day: day.id, exercises: exercises, open: slots[2].id)
            #expect(AdvDay.rows(input).map { $0.sub.hasSuffix("· 2:45 rest") } == [false, false, true], "\(place)")
            #expect(try Self.workoutRests(program, day) == ["2:45"], "\(place)")
            // The stepper edits the slot's own rest, and shows it: the row shows the group's.
            #expect(AdvDay.field(.rest, input)?.value == slots[2].rest.label, "\(place)")
            // Broken out, each row shows its own again.
            let alone = ProgramEditing.updateDay(program, day: day.id) {
                let first = DayEditing.setSuperset(false, slot: slots[1].id, in: $0)
                return DayEditing.setSuperset(false, slot: slots[2].id, in: first)
            }
            let own = AdvDay.rows(AdvDay.input(alone, day: day.id, exercises: exercises)).map(\.sub)
            #expect(own == slots.map { "Barbell · +5/wk · RPE 8 · \($0.rest.label) rest" }, "\(place)")
        }
    }

    @Test("The seed's supersets read 1:15 on Upper A and 1:30 on Lower A, and the workout rests the same")
    func seedSupersets_readTheWorkoutsRest() throws {
        let program = try Fixtures.seedProgram()
        #expect(try AdvDay.rows(AdvDay.seed(day: 0)).last?.sub == "Cable · Reps 15–17 · RPE 9 · 1:15 rest")
        #expect(try AdvDay.rows(AdvDay.seed(day: 1)).last?.sub == "Machine · Fixed · RPE 9 · 1:30 rest")
        let session = try SessionBuilder.build(
            program: program, weekIndex: 0, day: program.days[0], exercises: AdvDay.catalog(), history: [:],
            settings: .default, id: WorkoutID(Fixtures.uuid(9100)), device: Fixtures.deviceID, now: Fixtures.now
        )
        let rests = SupersetRounds.blocks(in: session.exercises).map {
            SupersetRounds.groupRest(block: $0, exercises: session.exercises).label
        }
        #expect(rests == ["2:30", "1:30", "1:30", "1:15"])
        #expect(SupersetRounds.groupRest(of: []) == .defaultRest)
    }
}

nonisolated extension DayEditorSupersetRestAdversarialTests {
    @Test("The estimate is decision #14's as before: 39, 38, 37, 31 for the seed, and the old formula on seeded days")
    func minutes_afterTheRefactor_areWhatTheyWere() throws {
        let program = try Fixtures.seedProgram()
        #expect(program.days.map { TimeEstimate.minutes(day: $0, prescriptions: [:]) } == [39, 38, 37, 31])
        var wrong: [String] = []
        for seed in 1 ... 40 as ClosedRange<UInt64> {
            let (random, dayID) = try AdvDay.random(seed: seed, missing: true)
            let day = try #require(random.days.first { $0.id == dayID })
            for week in random.weeks {
                var shown: [SlotID: Prescription] = [:]
                for slot in day.slots {
                    if let exercise = AdvDay.stored()[slot.exerciseID] {
                        shown[slot.id] = ProgressionRules.prescribe(
                            week: week, weekIndex: week.index, slot: slot, exercise: exercise, units: .lb
                        )
                    }
                }
                let sets = day.slots.reduce(0) { $0 + (shown[$1.id]?.sets ?? $1.sets) + $1.dropSets }
                let own = day.slots.reduce(0) { $0 + $1.sets + $1.dropSets }
                let isRight = TimeEstimate.minutes(day: day, prescriptions: shown) == Self.minutes(day, shown)
                    && TimeEstimate.minutes(day: day, prescriptions: [:]) == Self.minutes(day, [:])
                    && TimeEstimate.setCount(day: day, prescriptions: shown) == sets
                    && TimeEstimate.setCount(day: day, prescriptions: [:]) == own
                    && TimeEstimate.setCount(days: random.days) == own
                if !isRight {
                    wrong.append("seed \(seed) week \(week.index + 1)")
                }
            }
        }
        let allRight = wrong.isEmpty
        #expect(allRight, "\(wrong.prefix(4))")
    }

    @Test("Set counts: 58 for the seed's four days, 18 and 13 for Upper A in weeks 1 and 8, none for no slots")
    func setCount_forDaysAndForAWeek_isThePlainSum() throws {
        let input = try AdvProgram.seed()
        let program = input.program
        #expect(TimeEstimate.setCount(days: program.days) == 58)
        #expect(TimeEstimate.setCount(days: []) == 0)
        #expect(TimeEstimate.setCount(day: AdvProgram.day(7), prescriptions: [:]) == 0)
        #expect(program.days.map { TimeEstimate.setCount(day: $0, prescriptions: [:]) } == [18, 15, 15, 10])
        #expect(ProgramPresentation.make(input).days.summary == "4 days · 58 sets a week")
        #expect(try AdvDay.content(AdvDay.seed(day: 0))?.header.meta == "Week 1 · 5 exercises · 18 sets · ~39 min")
        // Week 8 is a deload: one set fewer for each of five exercises; Upper B keeps its drop set.
        #expect(try AdvDay.content(AdvDay.seed(day: 0, week: 7))?.header.meta.contains("· 13 sets ·") == true)
        #expect(try AdvDay.content(AdvDay.seed(day: 2, week: 7))?.header.meta.contains("· 11 sets ·") == true)
    }

    @Test("Criterion 13: two edits not marked relative, sent twice as a queue, give another program")
    func queueOfUnmarkedEdits_replayed_givesAnotherProgram() throws {
        let slot = try Slot(
            id: SlotID(Fixtures.uuid(51000)), exerciseID: AdvDay.exercise(0).id, sets: 3, reps: 8, repsHi: 12,
            rpe: 8, restSeconds: 90, progression: .fixed
        )
        let day = AdvProgram.day(1, slots: [slot])
        let program = try AdvProgram.program(weeks: 2, days: [day])
        let queue: [DayEditorEdit] = [
            .slot(.set(.repsHi(9), slot: slot.id), day: day.id),
            .slot(.setProgression(.double, slot: slot.id), day: day.id)
        ]
        #expect(queue.allSatisfy { !$0.isRelative })
        let once = queue.reduce(program) { $1.applied(to: $0) }
        let twice = queue.reduce(once) { $1.applied(to: $0) }
        // Once: the top goes to 9, and Double widens it to 10. Again: 9, and Double is already chosen.
        #expect(once.days[0].slots[0].repsHi == 10)
        #expect(twice.days[0].slots[0].repsHi == 9)
        // Each alone, drawn again over its own result, changes nothing: that is all the mark says.
        for edit in queue {
            let isSame = edit.applied(to: edit.applied(to: program)) == edit.applied(to: program)
            #expect(isSame)
        }
    }
}
