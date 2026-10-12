import Foundation
import LedgerDomain

/// What the rest panel's two buttons come to (F10 S6, criterion 5): one event each. In a file of its own
/// for the plan's length.
nonisolated extension WorkoutEditPlan {
    /// Rule 9 and decision #7: "+30s" carries what the panel showed at `now`, as the clock rule asks of the
    /// device that knows the screen (ADR-004): a rest still running, which the engine then extends, or
    /// "Rest over", after which it starts a rest of 30 s at `now`. With no rest shown there is no panel and
    /// no "+30s" to tap: a tap that waited behind a "Skip rest" comes to nothing.
    mutating func extendRest(in state: WorkoutState, at now: Date) {
        guard let shown = state.shownRest else {
            return
        }
        events.append(.restExtended(
            amount: Self.restExtension,
            extendsShownRest: shown.remaining(at: now) > .zero,
            tappedAt: now
        ))
    }

    /// What "+30s" adds.
    static let restExtension = Duration.seconds(30)

    /// Rule 9: the shown rest ends. A second tap, made before the panel went, finds no rest shown and sends
    /// nothing, so a double tap skips once.
    mutating func skipRest(in state: WorkoutState) {
        if state.shownRest != nil {
            events.append(.restSkipped)
        }
    }
}
