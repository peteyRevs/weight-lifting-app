@testable import FeatureToday
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F09 S3, gate G2: the brief's worked examples (body criteria 1, 3, 4 and 6), text for text and number for
/// number, in pounds and in kilograms. The seed program (spec §6.4) begins on Monday 2026-09-14. Every expected
/// text is the brief's "Copy (exact)"; every number is worked out by hand in the comment beside it.
@Suite("Adversarial F09 S3 · the brief's worked examples", .tags(.feature))
nonisolated struct TodayWorkedExamplesAdversarialTests {
    typealias Support = TodayAdversarial

    /// Wednesday 2026-09-16, 12:00 UTC: Lower A in week 1.
    static func wednesday(_ hour: Int = 12, _ minute: Int = 0) throws -> Date {
        try Support.moment(Support.civil(2026, 9, 16), hour, minute)
    }

    @Test("Criterion 1: Wednesday 16 September, week 1: the header, the strip and the Up-next card, in pounds")
    func wednesdayOfWeekOne_offersLowerA() throws {
        let program = try Support.seed()
        let model = try TodayPresentation.make(Support.input(program, now: Self.wednesday(5, 20)))
        #expect(model.header.date == "Wednesday, September 16")
        #expect(model.header.title == "Lower A")
        #expect(model.header.settings == TodayModel.Action(title: "Settings", route: .settings))
        #expect(model.weekStrip.map(\.weekday) == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(model.weekStrip.map(\.date) == ["14", "15", "16", "17", "18", "19", "20"])
        #expect(model.weekStrip.map(\.mark) == [.planned, .rest, .today, .rest, .planned, .planned, .rest])
        let card = try Support.upNext(model)
        #expect(card.eyebrow == "UP NEXT")
        // Squat 5×(42+180) + RDL 3×(42+120) + superset (3+4)×42 + 4 rounds×90 = 2250 s = 37.5 → 38 min.
        #expect(card.meta == "Week 1 of 8 · ~38 min")
        #expect(card.title == "Lower A — Squat focus")
        #expect(card.rows.map(\.name) == ["Back Squat", "Romanian Deadlift", "Leg Press", "Standing Calf Raise"])
        #expect(card.rows.map(\.scheme) == ["5 × 5 @ 250", "3 × 8 @ 205", "3 × 12 @ 320", "4 × 12 @ 160"])
        let lowerA = try Support.day("LA", in: program)
        let route = TodayRoute.startWorkout(program: program.id, weekIndex: 0, day: lowerA.id)
        #expect(card.action == .start(TodayModel.Action(title: "Start workout", route: route)))
    }

    @Test("Criterion 1 in kilograms: the same card, its loads converted and still without a unit")
    func wednesdayOfWeekOne_inKilograms_convertsTheLoads() throws {
        let input = try Support.input(Support.seed(), now: Self.wednesday(), settings: Support.settings(.kg))
        let card = try Support.upNext(TodayPresentation.make(input))
        // 250 lb = 113.398 kg, 205 lb = 92.986 kg, 320 lb = 145.150 kg, 160 lb = 72.575 kg (× 0.45359237).
        #expect(card.rows.map(\.scheme) == ["5 × 5 @ 113.4", "3 × 8 @ 93", "3 × 12 @ 145.1", "4 × 12 @ 72.6"])
        #expect(card.meta == "Week 1 of 8 · ~38 min")
    }

    @Test("Criterion 1: Monday's session, once logged, marks Monday done; the other days keep their marks")
    func mondayLogged_marksMondayDone() throws {
        let program = try Support.seed()
        let monday = try Support.moment(Support.civil(2026, 9, 14), 7)
        let upperA = try Support.finished(Support.live(program, week: 0, tag: "UA", number: 1, start: monday))
        let model = try TodayPresentation.make(Support.input(program, now: Self.wednesday(), week: [upperA]))
        #expect(model.weekStrip.map(\.mark) == [.done, .rest, .today, .rest, .planned, .planned, .rest])
        #expect(model.stats.sessions.value == "1")
        #expect(model.stats.sessions.unit == "/4")
    }

    @Test("Criterion 3: a workout live for three minutes reads Resume · 3:00 and carries its start")
    func liveForThreeMinutes_readsResume() throws {
        let program = try Support.seed()
        let now = try Self.wednesday()
        let live = try Support.live(program, week: 0, tag: "LA", number: 7, start: now.addingTimeInterval(-180))
        let card = try Support.upNext(TodayPresentation.make(Support.input(program, now: now, session: live)))
        let resume = TodayModel.Action(title: "Resume · 3:00", route: .resumeWorkout)
        #expect(card.action == .resume(resume, startedAt: now.addingTimeInterval(-180)))
        #expect(card.eyebrow == "UP NEXT")
        #expect(card.title == "Lower A — Squat focus")
        #expect(card.meta == "Week 1 of 8 · ~38 min")
        #expect(card.rows.map(\.scheme) == ["5 × 5 @ 250", "3 × 8 @ 205", "3 × 12 @ 320", "4 × 12 @ 160"])
    }

    @Test("Criterion 3: the same workout finished in the next update flips the card to Logged")
    func liveWorkoutFinished_flipsToLogged() throws {
        let program = try Support.seed()
        let now = try Self.wednesday()
        let live = try Support.live(program, week: 0, tag: "LA", number: 7, start: now.addingTimeInterval(-1462))
        let done = Support.finished(live, after: 1462)
        let model = try TodayPresentation.make(Support.input(program, now: now, session: done))
        let card = try Support.logged(model)
        #expect(card.action == TodayModel.Action(title: "View session", route: .openWorkout(done.id)))
        #expect(model.weekStrip.map(\.mark) == [.planned, .rest, .done, .rest, .planned, .planned, .rest])
        #expect(model.stats.sessions.value == "1")
    }

    @Test("Criterion 4: today's session finished today is the Logged card, text for text", arguments: Units.allCases)
    func lowerAFinishedToday_isLogged(_ units: Units) throws {
        let program = try Support.seed()
        let start = try Self.wednesday(6)
        let done = try Support.finished(
            Support.live(program, week: 0, tag: "LA", number: 4, start: start),
            after: 24 * 60 + 22
        )
        let input = try Support.input(program, now: Self.wednesday(), settings: Support.settings(units), week: [done])
        let card = try Support.logged(TodayPresentation.make(input))
        #expect(card.eyebrow == "LOGGED · WEEK 1")
        #expect(card.elapsed == "24:22")
        #expect(card.title == "Lower A — Squat focus")
        // 5×5×250 + 3×8×205 + 3×12×320 + 4×12×160 = 30,370 lb = 13,775.6 kg; 5 + 3 + 3 + 4 = 15 sets.
        let stats = units == .lb ? "15 of 15 sets · 30,370 lb moved" : "15 of 15 sets · 13,776 kg moved"
        #expect(card.stats == stats)
        #expect(card.action == TodayModel.Action(title: "View session", route: .openWorkout(done.id)))
        #expect(card.next == "Next: Friday · UB")
    }

    @Test("Criterion 6: Monday of week 8 reads Deload in the meta and shows the deload prescription")
    func mondayOfWeekEight_isADeload() throws {
        let program = try Support.seed()
        let now = try Support.moment(Support.civil(2026, 11, 2))
        let model = try TodayPresentation.make(Support.input(program, now: now))
        let card = try Support.upNext(model)
        // Bench 4×(42+150) + incline 2×(42+90) + row 3×(42+90) + superset 4×42 + 2 rounds×75 = 1746 s → 29.
        #expect(card.meta == "Week 8 of 8 · Deload · ~29 min")
        #expect(card.title == "Upper A — Push focus")
        // Bench 180 + 7×5 = 215 → ×0.85 = 182.75 → 185. Incline 50 + 2×2.5 = 55 at 11 reps → 46.75 → 47.5.
        // Row 65 + 7×2.5 = 82.5 → 70.125 → 70. Pulldown 105 at 13 → 89.25 → 90. Raise 17.5 at 16 → 14.875 → 15.
        let schemes = ["4 × 5 @ 185", "2 × 11 @ 47.5", "3 × 8 @ 70", "2 × 13 @ 90", "2 × 16 @ 15"]
        #expect(card.rows.map(\.scheme) == schemes)
        let everyRowIsADeload = card.rows.allSatisfy(\.isDeload)
        #expect(everyRowIsADeload)
        #expect(model.header.title == "Upper A")
        #expect(model.stats.sessions.unit == "/3")
        let upperA = try Support.day("UA", in: program)
        #expect(card.action.action.route == .startWorkout(program: program.id, weekIndex: 7, day: upperA.id))
    }
}
