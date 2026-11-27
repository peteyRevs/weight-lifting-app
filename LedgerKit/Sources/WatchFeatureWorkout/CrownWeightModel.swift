import Foundation
import LedgerDomain

/// The Digital Crown's weight (F18 criterion 4; R1 D10), in the workout's unit. It reads no clock: the view says
/// when the crown comes to rest (`rotationEnded()`, from `onIdle`). Turning moves only the number on screen; at rest
/// the turn is one commit on the exercise's step, and none when it came back to where it began; not turning, the
/// number follows the workout, so a change made on the phone shows here.
///
/// A change that arrives mid-turn is kept, not shown, so the number does not jump under the finger and the change is
/// not lost. At rest the lifter's turn wins: it is sent after the change, the newest word on the set, as a "+" on the
/// phone is planned on the change before it and lands after it. A turn that changed nothing gives way to the change;
/// a turn whose set was logged or left meanwhile is dropped, as the phone's stepper sends nothing for a logged row.
nonisolated struct CrownWeightModel: Equatable, Sendable {
    /// The set a turn changes, as the engine's events name it; what the crown reads there; and what a turn sends.
    struct Target: Equatable, Sendable {
        let exerciseIndex: Int
        let setID: SetID
    }

    struct Reading: Equatable, Sendable {
        let target: Target
        let weight: Weight
        let step: Weight
        let units: Units
    }

    struct Commit: Equatable, Sendable {
        let target: Target
        let weight: Weight
    }

    /// The crown's binding: the shown weight in the workout's unit (`digitalCrownRotation`'s `Double`).
    private(set) var value: Double = 0
    private(set) var isRotating = false
    /// What the number stands for: the reading when the turn began, or the latest while the crown is at rest; and
    /// the workout's latest, which a turn in progress holds back.
    private(set) var reading: Reading?
    private var latest: Reading?

    /// The shown number as a weight on the exercise's step; nil with no set to change.
    var weight: Weight? {
        reading.map { Self.weight(value, on: $0) }
    }

    /// The workout's reading now: shown at once while the crown is at rest, kept for its end while it turns.
    mutating func follow(_ next: Reading?) {
        latest = next
        if !isRotating {
            show(next)
        }
    }

    /// `onChange`: the crown is at `next`. With no set to change, the number stays where it is.
    mutating func rotate(to next: Double) {
        isRotating = reading != nil
        value = isRotating ? next : value
    }

    /// `onIdle`: the turn is over. Returns the change to send, once; nil when nothing turned, when the turn came
    /// back to the set's weight, or when its set is no longer the one to log. Then the number shows the workout.
    mutating func rotationEnded() -> Commit? {
        guard isRotating, let reading else {
            return nil
        }
        isRotating = false
        let turned = Self.weight(value, on: reading)
        let hasMoved = value != Self.number(reading.weight, in: reading.units) && turned != reading.weight
        guard latest?.target == reading.target, hasMoved else {
            show(latest)
            return nil
        }
        self.reading = latest.map { Reading(target: $0.target, weight: turned, step: $0.step, units: $0.units) }
        value = Self.number(turned, in: reading.units)
        return Commit(target: reading.target, weight: turned)
    }

    private mutating func show(_ next: Reading?) {
        reading = next
        if let next {
            value = Self.number(next.weight, in: next.units)
        }
    }

    /// `value` read in the reading's unit and put on its step, exactly (`Weight.rounded(toStep:)`): a crown with
    /// detents rests on a step, and a `Double` that strays from one by a rounding error lands back on it.
    static func weight(_ value: Double, on reading: Reading) -> Weight {
        let raw: Weight = reading.units == .lb ? .pounds(Decimal(value)) : .kilograms(Decimal(value))
        return raw.rounded(toStep: reading.step)
    }

    static func number(_ weight: Weight, in units: Units) -> Double {
        NSDecimalNumber(decimal: weight.shownValue(in: units)).doubleValue
    }
}
