import Foundation
@testable import LedgerDomain
import Testing

@Suite("SessionBuilder edges (adversarial)", .tags(.domain))
struct SessionBuilderEdgeAdversarialTests {
    typealias Base = SessionBuilderAdversarialTests
}

extension SessionBuilderEdgeAdversarialTests {
    @Test("The same inputs build the same workout, with every child ID distinct (determinism).")
    func build_isDeterministic_withUniqueIDs() throws {
        let first = try Base.build(week: 4, day: Fixtures.upperA())
        let second = try Base.build(week: 4, day: Fixtures.upperA())
        #expect(first == second)
        let exerciseIDs = first.exercises.map(\.id)
        let setIDs = first.exercises.flatMap { $0.sets.map(\.id) }
        #expect(Set(exerciseIDs).count == exerciseIDs.count)
        #expect(Set(setIDs).count == setIDs.count)
    }

    @Test("A different workout ID derives different child IDs.")
    func build_differentWorkoutID_differentChildIDs() throws {
        let first = try Base.build(week: 0, day: Fixtures.upperA())
        let other = try Base.build(week: 0, day: Fixtures.upperA(), id: WorkoutID(Fixtures.uuid(9100)))
        let firstIDs = Set(first.exercises.flatMap { $0.sets.map(\.id) })
        let otherIDs = Set(other.exercises.flatMap { $0.sets.map(\.id) })
        #expect(firstIDs.isDisjoint(with: otherIDs))
        #expect(Set(first.exercises.map(\.id)).isDisjoint(with: other.exercises.map(\.id)))
    }

    @Test("A week outside the block is rejected.", arguments: [8, 9, -1, Int.max])
    func build_weekOutOfRange_throws(week: Int) {
        #expect(throws: SessionBuilderError.weekOutOfRange(week)) {
            try Base.build(week: week, day: Fixtures.upperA())
        }
    }

    @Test("A day that is not in the program is rejected.")
    func build_foreignDay_throws() throws {
        let stranger = DayTemplate(id: DayTemplateID(Fixtures.uuid(1200)), name: "Stranger", tag: "ST")
        #expect(throws: SessionBuilderError.dayNotInProgram(stranger.id)) {
            try Base.build(week: 0, day: stranger)
        }
    }

    @Test("A slot whose exercise is missing from the lookup is rejected.")
    func build_unknownExercise_throws() throws {
        var catalog = Fixtures.catalog
        catalog[Fixtures.inclineDB.id] = nil
        #expect(throws: SessionBuilderError.unknownExercise(Fixtures.inclineDB.id)) {
            try Base.build(week: 0, day: Fixtures.upperA(), exercises: catalog)
        }
    }

    @Test("Kilogram settings build kilogram rows and a kilogram drop row (decision #9).")
    func build_kilograms_usesKiloLoads() throws {
        var settings = Settings.default
        settings.units = .kg
        let bench = try #require(Base.build(week: 0, day: Fixtures.upperA(), settings: settings).exercises.first)
        #expect(bench.sets.allSatisfy { $0.weight.grams == 80000 })
        #expect(bench.step.grams == 2500)
        // Curl 35 kg, step 2.5 kg: 35 × 0.85 = 29.75 → 11.9 steps → 12 → 30 kg.
        let curl = try #require(Base.build(week: 0, day: Fixtures.upperB(), settings: settings).exercises.first)
        #expect(curl.sets.map(\.weight.grams) == [35000, 35000, 35000, 30000])
    }

    @Test("A drop row on a 1.25 lb step rounds the −15 % tie away from zero (rule 15, decision #3).")
    func build_dropRow_quarterStepTie() throws {
        // 212.5 × 0.85 = 180.625 lb = 144.5 steps of 1.25 → 145 → 181.25 lb.
        let slot = try Fixtures.slot(
            Fixtures.inclineDB, id: 1250, sets: 1, reps: 8, progression: .fixed,
            startLoad: pounds("212.5"), step: pounds("1.25"), dropSets: 1
        )
        let day = DayTemplate(id: DayTemplateID(Fixtures.uuid(1251)), name: "Micro", tag: "MI", slots: [slot])
        let program = try Program(
            id: Fixtures.programID, name: "Micro", startDate: Adversarial.startDay,
            weeks: [Fixtures.week(0), Fixtures.week(1)], days: [day]
        )
        let drop = try #require(Base.build(week: 0, day: day, program: program).exercises.first?.sets.last)
        #expect(drop.kind == .drop)
        #expect(drop.weight == pounds("181.25"))
    }

    @Test("Auto-rest is snapshotted from settings.")
    func build_autoRest_isSnapshotted() throws {
        var settings = Settings.default
        settings.autoRest = false
        #expect(try !Base.build(week: 0, day: Fixtures.upperA(), settings: settings).autoRest)
        #expect(try Base.build(week: 0, day: Fixtures.upperA()).autoRest)
    }

    @Test("A program day that is not scheduled this week can still be built (decision #18 off-schedule).")
    func build_unscheduledDay_isAllowed() throws {
        let upperA = try Fixtures.upperA()
        let upperB = try Fixtures.upperB()
        let weeks = (0 ..< 3).map { Fixtures.week($0, schedule: [.monday: upperA.id]) }
        let program = try Program(
            id: Fixtures.programID, name: "A only", startDate: Adversarial.startDay, weeks: weeks, days: [
                upperA,
                upperB
            ]
        )
        let workout = try Base.build(week: 1, day: upperB, program: program)
        #expect(workout.exercises.count == 1)
        #expect(workout.source?.dayTemplateID == upperB.id)
    }

    @Test("An empty day builds an empty live workout without throwing.")
    func build_emptyDay_isEmpty() throws {
        let empty = DayTemplate(id: DayTemplateID(Fixtures.uuid(1300)), name: "New day", tag: "D3")
        let weeks = (0 ..< 2).map { Fixtures.week($0) }
        let program = try Program(
            id: Fixtures.programID,
            name: "Empty",
            startDate: Adversarial.startDay,
            weeks: weeks,
            days: [empty]
        )
        let workout = try Base.build(week: 0, day: empty, program: program)
        #expect(workout.exercises.isEmpty)
        #expect(workout.totalSets == 0)
        #expect(workout.phase == .live)
    }

    @Test("Only a live workout for the same program, week and day is resumed (rule 17).")
    func resumable_sameSourceOnly() throws {
        let program = try Base.program()
        let upperA = try Fixtures.upperA()
        let live = try Base.build(week: 2, day: upperA)
        #expect(SessionBuilder.resumable(live, program: program, weekIndex: 2, day: upperA) == live)
        #expect(SessionBuilder.resumable(live, program: program, weekIndex: 3, day: upperA) == nil)
        #expect(try SessionBuilder.resumable(live, program: program, weekIndex: 2, day: Fixtures.upperB()) == nil)
        #expect(SessionBuilder.resumable(nil, program: program, weekIndex: 2, day: upperA) == nil)
        var finished = live
        finished.phase = .finished
        #expect(SessionBuilder.resumable(finished, program: program, weekIndex: 2, day: upperA) == nil)
        var adHoc = live
        adHoc.source = nil
        #expect(SessionBuilder.resumable(adHoc, program: program, weekIndex: 2, day: upperA) == nil)
    }
}
