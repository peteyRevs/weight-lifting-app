import Foundation
@testable import LedgerDomain
import LedgerTestSupport
import Testing

/// G2, F10 S6 round 2: `WorkoutState.shownRest` under a wall clock that was set back, **as built and
/// recorded for F17** (ruling 21, the tester's question 7; with F10-S6-1). `shownRest` tells "a set was
/// logged after this rest ended" by comparing every set's `doneAt` with the rest's end. With the clock set
/// back by more than a rest between two logs, the earlier set's `doneAt` is later than the new rest's end,
/// and the rest that is running is not shown at all. When F17 rules on clocks, these change with it.
@Suite("WorkoutState.shownRest, the clock set back (adversarial)", .tags(.domain))
struct ShownRestClockAdversarialTests {
    static func after(_ events: [WorkoutEvent]) -> WorkoutState {
        var state = EventBuilders.seedSession()
        for (offset, event) in events.enumerated() {
            let envelope = EventBuilders.envelope(event, seq: UInt64(offset + 2), at: EventBuilders.start)
            state = WorkoutEngine.reduce(state, envelope).0 ?? state
        }
        return state
    }

    static func logged(_ set: Int, at seconds: Double) -> WorkoutEvent {
        let row = EventBuilders.seedSession().exercises[0].sets[set]
        return .setLogged(
            exerciseIndex: 0, setID: row.id, weight: row.weight, reps: row.reps,
            doneAt: EventBuilders.start.addingTimeInterval(seconds)
        )
    }

    @Test("As built (F17): the clock set back by less than the rest between two logs still shows the new rest")
    func setBack_lessThanTheRest_isShown() {
        // Set 1 at 1,000 s; the clock goes back 100 s; set 2 at 900 s rests until 1,050 s.
        let state = Self.after([Self.logged(0, at: 1000), Self.logged(1, at: 900)])
        #expect(state.shownRest?.endsAt == EventBuilders.start.addingTimeInterval(1050))
    }

    @Test("As built (F17): the clock set back by more than the rest between two logs hides the running rest")
    func setBack_moreThanTheRest_isHidden() {
        // Set 1 at 1,000 s; the clock goes back 400 s; set 2 at 600 s rests until 750 s, before set 1's time.
        let state = Self.after([Self.logged(0, at: 1000), Self.logged(1, at: 600)])
        #expect(state.rest?.endsAt == EventBuilders.start.addingTimeInterval(750), "the engine holds the rest")
        #expect(state.shownRest == nil, "and no screen shows it")
    }
}
