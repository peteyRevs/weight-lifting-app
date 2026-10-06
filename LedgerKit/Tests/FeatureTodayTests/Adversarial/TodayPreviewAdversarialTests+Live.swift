@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// S3 criterion 4: the card of a live workout shows that workout, "its name and its exercises".
nonisolated extension TodayPreviewAdversarialTests {
    static func targets(_ workout: WorkoutState, _ units: Units) -> [String] {
        workout.exercises.map {
            "\($0.name): \($0.targetSets) × \($0.targetReps) @ \($0.targetLoad.formatted(in: units))"
        }
    }

    static func names(_ card: TodayModel.UpNext) -> [String] {
        card.rows.map { "\($0.name): \($0.scheme)" }
    }

    @Test("A live workout's card shows its own exercises and targets, in the lifter's units", arguments: Units.allCases)
    func liveWorkout_showsItsOwnExercises(_ units: Units) throws {
        let program = try Support.seed()
        let now = try Support.moment(Support.civil(2026, 9, 16))
        var lines: [String] = []
        for index in [0, 3, 7] {
            for day in program.days {
                let start = now.addingTimeInterval(-600)
                let live = try Support.live(program, week: index, tag: day.tag, number: 6, start: start)
                let input = try Support.input(program, now: now, settings: Support.settings(units), session: live)
                let card = try Support.upNext(TodayPresentation.make(input))
                if Self.names(card) != Self.targets(live, units) || card.title != day.name {
                    lines.append("week \(index + 1) \(day.tag): \(card.title) \(Self.names(card).prefix(2))")
                }
            }
        }
        let agrees = lines.isEmpty
        #expect(agrees, "\(lines.count) of 12 workouts disagree:\n\(lines.prefix(4).joined(separator: "\n"))")
    }

    @Test("A live workout shows a swapped exercise as swapped, and an exercise the catalog no longer holds")
    func liveWorkout_showsWhatItHolds() throws {
        let program = try Support.seed()
        let now = try Support.moment(Support.civil(2026, 9, 16))
        var live = try Support.live(program, week: 0, tag: "LA", number: 6, start: now.addingTimeInterval(-5))
        live.exercises[0].exerciseID = Fixtures.CatalogID.frontSquat
        live.exercises[0].name = "Front Squat"
        live.name = "Renamed — after the start"
        var input = try Support.input(program, now: now, session: live)
        input.exercises[Fixtures.CatalogID.legPress] = nil
        let card = try Support.upNext(TodayPresentation.make(input))
        #expect(card.title == "Renamed — after the start")
        #expect(card.rows.map(\.name) == ["Front Squat", "Romanian Deadlift", "Leg Press", "Standing Calf Raise"])
        #expect(card.rows.map(\.scheme) == ["5 × 5 @ 250", "3 × 8 @ 205", "3 × 12 @ 320", "4 × 12 @ 160"])
    }

    @Test("A live workout with no exercises, or one this program does not hold, still offers Resume")
    func liveWorkoutOfNoProgram_stillOffersResume() throws {
        let program = try Support.seed()
        let now = try Support.moment(Support.civil(2026, 9, 16))
        var empty = try Support.lifted(
            number: 6,
            start: now.addingTimeInterval(-7),
            lifts: [],
            name: "Ad hoc",
            tag: "AH"
        )
        empty.phase = .live
        empty.endedAt = nil
        let bare = try Support.upNext(TodayPresentation.make(Support.input(program, now: now, session: empty)))
        #expect(bare.action.action == TodayModel.Action(title: "Resume · 0:07", route: .resumeWorkout))
        #expect(bare.title == "Ad hoc")
        #expect(bare.rows.isEmpty)
        var foreign = try Support.live(program, week: 1, tag: "UB", number: 7, start: now.addingTimeInterval(-7))
        let other = WorkoutSource(
            programID: TodayScenario.otherProgram,
            weekIndex: 1,
            dayTemplateID: program.days[2].id
        )
        foreign.source = other
        let card = try Support.upNext(TodayPresentation.make(Support.input(program, now: now, session: foreign)))
        #expect(card.action.action.route == .resumeWorkout)
        #expect(card.rows.count == 4)
        let later = try Support.live(program, week: 1, tag: "UB", number: 8, start: now.addingTimeInterval(-7))
        let ahead = try Support.upNext(TodayPresentation.make(Support.input(program, now: now, session: later)))
        print("TodayPreviewAdversarialTests live metas: no source \(bare.meta ?? "nil"); another program "
            + "\(card.meta ?? "nil"); week 2's Upper B on a week-1 day \(ahead.meta ?? "nil")")
    }
}
