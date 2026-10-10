@testable import FeatureWorkout
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S6, criteria 1 to 4 and 11: the rest panel's model, a pure reading of the workout at the moment it
/// is handed. The rest is the Domain's (`shownRest`); the model only writes it.
@Suite("WorkoutPresentation · rest", .tags(.feature))
struct WorkoutPresentationRestTests {
    typealias Plans = WorkoutRestPlanTests

    static func panel(
        _ state: WorkoutState,
        after seconds: TimeInterval = 0,
        selection: WorkoutSelection? = nil,
        isBusy: Bool = false,
        locale: Locale = Fixtures.locale
    ) -> RestPanelModel? {
        WorkoutPresentation.rest(
            state, at: Fixtures.now.addingTimeInterval(seconds), selection: selection, isBusy: isBusy, locale: locale
        )
    }

    @Test("While a rest runs: the time left as m:ss, the ring's share, Resting, the next set and the two buttons")
    func resting() throws {
        let model = try #require(Self.panel(Plans.resting(secondsLeft: 75)))
        #expect(model.clock == "1:15")
        #expect(model.fraction == 0.5)
        #expect(model.status == "Resting")
        #expect(model.spokenTime == "1 minute, 15 seconds")
        #expect(!model.isOver)
        #expect(model.next?.line == "Set 2 · 185 lb × 5")
        #expect(model.next?.spoken == "Set 2, 185 pounds, 5 reps")
        #expect([model.extend, model.extendLabel, model.skip] == ["+30s", "Add 30 seconds", "Skip rest"])
        #expect(model.isEnabled)
    }

    @Test("The time left is the wall clock's at the moment handed in: 40 s later it reads 40 s less", arguments: [
        (0.0, "1:15", "1 minute, 15 seconds"), (0.4, "1:15", "1 minute, 15 seconds"),
        (40.0, "0:35", "35 seconds"), (74.5, "0:01", "1 second"), (15.0, "1:00", "1 minute")
    ])
    func wallClock(after: TimeInterval, clock: String, spoken: String) throws {
        let model = try #require(Self.panel(Plans.resting(secondsLeft: 75), after: after))
        #expect(model.clock == clock)
        #expect(model.spokenTime == spoken)
        #expect(!model.isOver)
    }

    @Test("At zero and after: 0:00, an empty ring and Rest over, with the buttons still there", arguments: [
        75.0, 76, 4000
    ])
    func over(after: TimeInterval) throws {
        let model = try #require(Self.panel(Plans.resting(secondsLeft: 75), after: after))
        #expect(model.clock == "0:00")
        #expect(model.fraction == 0)
        #expect(model.status == "Rest over")
        #expect(model.spokenTime.isEmpty)
        #expect(model.isOver)
        #expect(model.next?.line == "Set 2 · 185 lb × 5")
        #expect([model.extend, model.skip] == ["+30s", "Skip rest"])
    }

    @Test("No rest shown, no panel: a fresh workout, auto rest off, a skipped rest, a set logged after its end")
    func noPanel() {
        #expect(Self.panel(Plans.Plans.seed) == nil)
        var off = Plans.resting(secondsLeft: 75)
        off.autoRest = false
        off.rest = nil
        #expect(Self.panel(off) == nil)
        var stale = Plans.resting(secondsLeft: -75)
        stale.exercises[0].sets[1].doneAt = Fixtures.now.addingTimeInterval(-10)
        #expect(Self.panel(stale) == nil)
    }

    @Test("The screen draws a panel only when it is handed a moment; busy disables its buttons")
    func screen_needsAMoment() {
        let state = Plans.resting(secondsLeft: 75)
        func rest(now: Date?, isBusy: Bool = false) -> RestPanelModel? {
            let screen = WorkoutPresentation.screen(
                .loaded(state), now: now, isBusy: isBusy, locale: Fixtures.locale, calendar: Fixtures.calendar
            )
            guard case let .workout(model) = screen else {
                return nil
            }
            return model.rest
        }
        #expect(rest(now: nil) == nil)
        #expect(rest(now: Fixtures.now)?.clock == "1:15")
        #expect(rest(now: Fixtures.now)?.isEnabled == true)
        #expect(rest(now: Fixtures.now, isBusy: true)?.isEnabled == false)
    }

    @Test("The next set is the shown row: the lifter's choice, kilograms, a drop set, and none when none is left")
    func nextSet() throws {
        var state = Plans.resting(secondsLeft: 75)
        let chosen = WorkoutSelection(exerciseIndex: 0, setID: Plans.Plans.set(0, 3))
        #expect(Self.panel(state, selection: chosen)?.next?.line == "Set 4 · 185 lb × 5")
        // In kilograms, with a drop set as the next row.
        state.units = .kg
        state.exercises[0].sets[1].weight = .kilograms(82.5)
        #expect(Self.panel(state)?.next?.line == "Set 2 · 82.5 kg × 5")
        state.exercises[0].sets[1].kind = .drop
        #expect(Self.panel(state)?.next?.line == "Drop set · 82.5 kg × 5")
        #expect(Self.panel(state)?.next?.spoken == "Drop set, 82.5 kilograms, 5 reps")
        state.units = .lb
        state.exercises[0].sets[1].weight = .pounds(150)
        #expect(Self.panel(state)?.next?.line == "Drop set · 150 lb × 5")
        // A set after a drop set takes the next number, as its row does.
        let third = WorkoutSelection(exerciseIndex: 0, setID: Plans.Plans.set(0, 2))
        #expect(Self.panel(state, selection: third)?.next?.line == "Set 2 · 185 lb × 5")
        // Every set of the shown exercise logged: the panel names no set.
        var done = Plans.resting(secondsLeft: 75)
        for exercise in done.exercises.indices {
            for set in done.exercises[exercise].sets.indices {
                done.exercises[exercise].sets[set].doneAt = Fixtures.now.addingTimeInterval(-200)
            }
        }
        let model = try #require(Self.panel(done))
        #expect(model.next == nil)
        #expect(model.status == "Resting")
    }

    @Test("After the last set of an exercise the next set is the next exercise's first, as the engine moves on")
    func nextSet_isTheNextExercises() {
        var state = Plans.Plans.seed
        for set in state.exercises[0].sets.indices {
            state.exercises[0].sets[set].doneAt = Fixtures.now.addingTimeInterval(-100)
        }
        state.cursor = Cursor(exerciseIndex: 1, setIndex: 0)
        state.rest = RestTimer(endsAt: Fixtures.now.addingTimeInterval(50), total: .seconds(150))
        #expect(Self.panel(state)?.next?.line == "Set 1 · 55 lb × 10")
    }

    @Test("The spoken time is written in the locale handed in, never the device's")
    func spokenTime_takesTheLocale() throws {
        let german = try #require(Self.panel(Plans.resting(secondsLeft: 75), locale: Locale(identifier: "de_DE")))
        #expect(german.spokenTime == "1 Minute und 15 Sekunden")
        #expect(german.clock == "1:15")
    }

    @Test("A rest whose dates are no dates gives a model and does not trap")
    func total() {
        var state = Plans.resting(secondsLeft: 75)
        state.rest = RestTimer(endsAt: .distantFuture, total: .seconds(-5))
        #expect(Self.panel(state)?.fraction == 0)
        let never = Date(timeIntervalSinceReferenceDate: .nan)
        #expect(WorkoutPresentation.rest(
            Plans.resting(secondsLeft: 75), at: never, selection: nil, isBusy: false, locale: Fixtures.locale
        )?.clock == "0:00")
    }
}
