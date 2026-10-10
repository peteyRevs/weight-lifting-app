import Foundation

/// The rest panel (F10 S6; v2 "Active workout", the floating card) at one moment: the time the shown rest
/// has left, the set that comes next, and its two buttons. Every string is final. The moment is the one
/// the presentation was handed (`WorkoutPresentation.rest`); the model holds no clock and no rest, and the
/// view decides nothing.
nonisolated struct RestPanelModel: Equatable, Sendable {
    /// "1:15", by the whole second, rounded up; "0:00" once the rest is over.
    let clock: String
    /// The share of the rest still to go, 0…1: the ring's arc.
    let fraction: Double
    /// "Resting" while time is left, then "Rest over".
    let status: String
    /// "1 minute, 15 seconds": the time left as VoiceOver reads it; empty once the rest is over, when the
    /// status says so.
    let spokenTime: String
    let isOver: Bool
    /// The set the lifter does next; nil when no row is shown (every set of the shown exercise is logged).
    let next: NextSet?
    /// "+30s".
    let extend: String
    /// "Add 30 seconds": what VoiceOver reads for "+30s".
    let extendLabel: String
    /// "Skip rest".
    let skip: String
    /// False while a discard runs or the cover is closing: neither button answers.
    let isEnabled: Bool

    nonisolated struct NextSet: Equatable, Sendable {
        /// "Set 3 · 180 lb × 5".
        let line: String
        /// "Set 3, 180 pounds, 5 reps": the same, as VoiceOver reads a set's row.
        let spoken: String
    }
}
