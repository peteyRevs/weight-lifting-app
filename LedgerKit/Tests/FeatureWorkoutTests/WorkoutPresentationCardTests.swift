@testable import FeatureWorkout
import Foundation
import LedgerDesign
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S5, criteria 2, 6 and 12: the page's model, word for word. The presentation is pure: the workout, the
/// row chosen, the locale and the calendar are arguments. The workout is the spec's five straight-set
/// exercises in pounds (`EventBuilders.seedSession`): Bench 5 × 5 @ 185, Incline DB 3 × 10 @ 55,
/// Chest-Supported Row 4 × 8 @ 70, Lat Pulldown 3 × 12 @ 100, Cable Lateral Raise 3 × 15 @ 15.
@Suite("WorkoutPresentation · the page", .tags(.feature))
struct WorkoutPresentationCardTests {
    static let context = WorkoutPresentation.Context(locale: Fixtures.locale, calendar: Fixtures.calendar)

    static func page(
        _ state: WorkoutState,
        selection: WorkoutSelection? = nil,
        isBusy: Bool = false
    ) -> WorkoutPageModel {
        WorkoutPresentation.page(state, selection: selection, isBusy: isBusy, context)
    }

    static func set(_ exercise: Int, _ row: Int) -> SetID {
        EventBuilders.setID(exercise, row)
    }

    /// The seed workout, its bench press last done on August 12 as 5 × 5 @ 180 lb.
    static func seedWithHistory() throws -> WorkoutState {
        var state = EventBuilders.seedSession()
        let august12 = try #require(Fixtures.calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 12,
            hour: 18
        )))
        state.exercises[0].lastPerformance = LastPerformance(date: august12, sets: 5, reps: 5, load: .pounds(180))
        return state
    }

    // MARK: Criterion 2: the card

    @Test("The card of the first exercise reads as the brief writes it, every word")
    func card_justStarted_isWordForWord() throws {
        let card = try #require(try Self.page(Self.seedWithHistory()).card)
        #expect(card.exerciseIndex == 0)
        #expect(card.eyebrow == "Exercise 1 of 5")
        #expect(card.title == "Barbell Bench Press")
        #expect(card.targetLabel == "TARGET")
        #expect(card.target == "5 × 5 @ 185 lb · RPE 8")
        #expect(card.lastLabel == "Last")
        #expect(card.last == "Aug 12 · 5×5 @ 180 lb")
        #expect(card.repeatLast == "Repeat")
        #expect([card.columns.number, card.columns.weight, card.columns.reps] == ["#", "lb", "reps"])
        #expect(card.addSet == "+ Add set")
        #expect(card.rows.map(\.label) == ["1", "2", "3", "4", "5"])
        #expect(card.rows.map(\.weight) == ["185", "185", "185", "185", "185"])
        #expect(card.rows.map(\.reps) == ["5", "5", "5", "5", "5"])
        #expect(card.rows.map(\.state) == [.active, .pending, .pending, .pending, .pending])
        #expect(card.rows.map(\.id) == (0 ..< 5).map { Self.set(0, $0) })
    }

    @Test("Without a last workout the line reads \"No history yet\" and there is no Repeat")
    func card_noHistory_hasNoRepeat() throws {
        let card = try #require(Self.page(EventBuilders.seedSession()).card)
        #expect(card.last == "No history yet")
        #expect(card.repeatLast == nil)
        #expect(card.lastLabel == "Last")
    }

    @Test("The day of \"Last\" is the day in the calendar's time zone, not the device's")
    func card_last_usesTheCalendarHandedIn() throws {
        var state = EventBuilders.seedSession()
        // 23:30 UTC on August 12 is already August 13 in Tokyo.
        let late = try #require(Fixtures.calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 12, hour: 23, minute: 30)
        ))
        state.exercises[0].lastPerformance = LastPerformance(date: late, sets: 3, reps: 8, load: .pounds(52.5))
        var tokyo = Fixtures.calendar
        tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let there = WorkoutPresentation.Context(locale: Fixtures.locale, calendar: tokyo)
        #expect(Self.page(state).card?.last == "Aug 12 · 3×8 @ 52.5 lb")
        #expect(WorkoutPresentation.page(state, selection: nil, isBusy: false, there).card?
            .last == "Aug 13 · 3×8 @ 52.5 lb")
    }

    @Test("Each row's check says what it will do, and VoiceOver's summary names the set, its weight and its reps")
    func card_rows_speakAndSendTheirOwn() throws {
        var state = EventBuilders.seedSession()
        state.exercises[0].sets[0].doneAt = Fixtures.now
        state.exercises[0].sets[1].weight = .pounds(187.5)
        state.exercises[0].sets[1].reps = .one
        state.cursor = Cursor(exerciseIndex: 0, setIndex: 1)
        let card = try #require(Self.page(state).card)
        #expect(card.rows.map(\.state) == [.done, .active, .pending, .pending, .pending])
        #expect(card.rows.map(\.checkLabel) == ["Undo set 1", "Log set 2", "Log set 3", "Log set 4", "Log set 5"])
        #expect(card.rows.prefix(3).map(\.summary) == [
            "Set 1, 185 pounds, 5 reps", "Set 2, 187.5 pounds, 1 rep", "Set 3, 185 pounds, 5 reps"
        ])
        #expect(card.rows[0].check == .unlog(exerciseIndex: 0, setID: Self.set(0, 0)))
        #expect(card.rows[1].check == .log(exerciseIndex: 0, setID: Self.set(0, 1)))
        #expect(card.rows[1].weight == "187.5")
    }

    @Test("The steppers stand under the shown row: the exercise's step, one rep, and the row's values spoken")
    func card_steppers_areTheShownRows() throws {
        var state = EventBuilders.seedSession()
        state.exercises[1].sets[1].weight = .pounds(57.5)
        let chosen = WorkoutSelection(exerciseIndex: 1, setID: Self.set(1, 1))
        let card = try #require(Self.page(state, selection: chosen).card)
        #expect(card.title == "Incline DB Press")
        #expect(card.rows.map(\.state) == [.pending, .active, .pending])
        let steppers = try #require(card.steppers)
        #expect(steppers.setID == Self.set(1, 1))
        #expect(steppers.weightStep == "2.5 LB")
        #expect(steppers.repStep == "1 REP")
        #expect(steppers.weight == "57.5 pounds")
        #expect(steppers.reps == "10 reps")
    }

    @Test("A drop set is \"D\", and a set added after it takes the next number")
    func card_dropSet_isD() throws {
        var state = EventBuilders.session([
            .init("Barbell Curl", .barbell, sets: 2, reps: 12, pounds: 75, restSeconds: 60, dropSet: true)
        ])
        state.exercises[0].sets[2].weight = .pounds(65)
        state.exercises[0].sets[2].doneAt = Fixtures.now
        state.exercises[0].sets.append(
            LoggedSet(id: SetID(EventBuilders.uuid(0xADD)), weight: .pounds(65), reps: Reps(clamping: 12), kind: .added)
        )
        let card = try #require(Self.page(state).card)
        #expect(card.rows.map(\.label) == ["1", "2", "D", "3"])
        #expect(card.rows.map(\.checkLabel) == ["Log set 1", "Log set 2", "Undo drop set", "Log set 3"])
        #expect(card.rows[2].summary == "Drop set, 65 pounds, 12 reps")
        state.exercises[0].sets[2].doneAt = nil
        #expect(Self.page(state).card?.rows[2].checkLabel == "Log drop set")
    }

    @Test("In kilograms the target, the column, the step and the spoken weight are kilograms")
    func card_kilograms_readsKilograms() throws {
        var state = EventBuilders.seedSession()
        state.units = .kg
        state.exercises[0].targetLoad = .kilograms(85)
        state.exercises[0].step = .kilograms(2.5)
        state.exercises[0].sets[0].weight = .kilograms(82.5)
        state.exercises[0].lastPerformance = LastPerformance(
            date: Fixtures.now.addingTimeInterval(-7 * 86400), sets: 5, reps: 5, load: .kilograms(82.5)
        )
        let card = try #require(Self.page(state).card)
        #expect(card.target == "5 × 5 @ 85 kg · RPE 8")
        #expect(card.columns.weight == "kg")
        #expect(card.last == "Sep 9 · 5×5 @ 82.5 kg")
        #expect(card.rows[0].weight == "82.5")
        #expect(card.rows[0].summary == "Set 1, 82.5 kilograms, 5 reps")
        #expect(card.steppers?.weightStep == "2.5 KG")
        #expect(card.steppers?.weight == "82.5 kilograms")
    }

    @Test("A half-point target effort reads with its half")
    func card_target_halfPointEffort() throws {
        var state = EventBuilders.seedSession()
        state.exercises[0].rpe = try #require(RPE(8.5))
        state.exercises[0].targetLoad = .pounds(52.5)
        #expect(Self.page(state).card?.target == "5 × 5 @ 52.5 lb · RPE 8.5")
    }
}
