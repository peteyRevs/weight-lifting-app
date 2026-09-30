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
}
