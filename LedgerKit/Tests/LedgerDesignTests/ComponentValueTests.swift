import LedgerDesign
import Testing

/// Review R2-S1: slice 2's value types are `nonisolated`, so code off the main actor (F10's
/// presentation values, value-only suites, actors) can store, compare and hash them. This file is
/// the guard: `SetRowPresentation`, `ValueChecker` and the suite only compile while that holds.
@Suite("ComponentValues", .tags(.design))
nonisolated struct ComponentValueTests {
    @Test("Slice 2's value types compare and hash off the main actor, in a struct and in an actor")
    func valueTypes_offTheMainActor_areEquatableAndHashable() async {
        let model = SetRowPresentation(
            state: .done, style: .filled, tint: .accent, direction: .increment, icon: .check, ring: .phone
        )
        #expect(model == model)
        #expect(model != SetRowPresentation(
            state: .active, style: .ghost, tint: .muted, direction: .decrement, icon: .swap, ring: .phone
        ))
        #expect(Set([SetRowState.pending, .active, .done, .done]).count == 3)
        #expect(await ValueChecker().isLogged(.done))
        #expect(await !(ValueChecker().isLogged(.active)))
    }
}

/// Slice 3's value types, held the same way: F09's week and stats, F10's progress, F18's rest ring.
@Suite("Slice3ComponentValues", .tags(.design))
nonisolated struct Slice3ComponentValueTests {
    @Test("Slice 3's value types compare and hash off the main actor, in a struct and in an actor")
    func valueTypes_offTheMainActor_areEquatableAndHashable() async {
        let day = WeekStrip.Day(weekday: "W", date: "19", mark: .today, accessibilitySummary: "Wednesday, August 19")
        let model = TodayPresentation(
            week: [day], mark: .today, segment: ProgressSegment(length: 5, state: .current), phase: .current,
            ring: .watch
        )
        #expect(model == model)
        #expect(model != TodayPresentation(
            week: [], mark: .done, segment: ProgressSegment(length: 3, state: .done), phase: .upcoming, ring: .phone
        ))
        #expect(Set([WeekStrip.Mark.rest, .planned, .today, .done, .done]).count == 4)
        #expect(Set([ProgressSegment.State.done, .current, .upcoming]).count == 3)
        #expect(await ValueChecker().isToday(day))
    }
}

/// A presentation value such as F09's and F10's: every slice-3 value type as a stored, compared property.
private nonisolated struct TodayPresentation: Equatable, Sendable {
    var week: [WeekStrip.Day]
    var mark: WeekStrip.Mark
    var segment: ProgressSegment
    var phase: ProgressSegment.State
    var ring: RestRingGeometry
}

/// A presentation value such as F10's: every slice-2 value type as a stored, compared property.
private nonisolated struct SetRowPresentation: Equatable, Sendable {
    var state: SetRowState
    var style: PillButton.Style
    var tint: Eyebrow.Tint
    var direction: SetRowSteppers.Direction
    var icon: LedgerIcon
    var ring: RestRingGeometry
}

/// An actor-isolated context, where a main-actor-isolated conformance would not compile.
private actor ValueChecker {
    func isLogged(_ state: SetRowState) -> Bool {
        state == .done
    }

    func isToday(_ day: WeekStrip.Day) -> Bool {
        day.mark == .today
    }
}
