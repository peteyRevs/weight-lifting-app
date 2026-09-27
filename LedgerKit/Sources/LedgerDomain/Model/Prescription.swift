import Foundation

/// What a slot asks for in a given week (spec §6.1 "Prescription", computed by
/// `ProgressionRules.prescribe`, spec §7.2).
public struct Prescription: Hashable, Sendable {
    public let load: Weight
    public let sets: Int
    public let reps: Int
    public let rpe: RPE
    public let rest: RestDuration
    public let step: Weight
    public let progression: Progression
    /// Spec §7.2 `held`: the previous week was missed, so the load holds (" · HELD").
    public let isHeld: Bool
    public let isDeload: Bool

    public init(
        load: Weight,
        sets: Int,
        reps: Int,
        rpe: RPE,
        rest: RestDuration,
        step: Weight,
        progression: Progression,
        isHeld: Bool,
        isDeload: Bool
    ) {
        self.load = load
        self.sets = sets
        self.reps = reps
        self.rpe = rpe
        self.rest = rest
        self.step = step
        self.progression = progression
        self.isHeld = isHeld
        self.isDeload = isDeload
    }

    /// Rule 14: "{sets} × {reps} @ {load} {unit} · RPE {rpe}", e.g. "5 × 5 @ 185 lb · RPE 8".
    public func targetLine(units: Units) -> String {
        TargetText.scheme(sets: sets, reps: reps, load: load, units: units) + " · RPE " + rpe.label
    }
}

/// Shared "{sets} × {reps} @ {load} {unit}" text for prescriptions (rule 14) and receipts (rule 30).
enum TargetText {
    static func scheme(sets: Int, reps: Int, load: Weight, units: Units) -> String {
        "\(sets) × \(reps) @ \(load.formatted(in: units)) \(units.rawValue)"
    }
}
