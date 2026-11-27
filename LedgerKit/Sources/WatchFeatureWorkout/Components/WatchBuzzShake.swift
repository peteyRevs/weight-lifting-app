import SwiftUI

/// The rest-over shake (spec §4.1, §8.8; F18 criterion 6): the prototype's `buzz .38s ease 3`, three short sideways
/// shakes, keyframed at 0, −3, 3, −2, 2 and 0 px (÷ 1.5) over each fifth of a shake. `cycles` counts the shakes
/// played, so animating it on by `shakes` plays them once more; at a whole number the screen stands still.
/// Under Reduce Motion the screen does not shake (criterion 15): `WatchRestScreen.shakes(atRestOver:reduceMotion:)`.
nonisolated struct WatchBuzzShake: GeometryEffect {
    static let shakes = 3.0
    /// How long the three shakes last, in seconds.
    static let duration = 0.38 * shakes
    /// One shake's keyframes, in points.
    static let keyframes: [CGFloat] = [0, -3, 3, -2, 2, 0].map { $0 / 1.5 }

    var cycles: Double

    var animatableData: Double {
        get { cycles }
        set { cycles = newValue }
    }

    func effectValue(size _: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: Self.offset(at: cycles), y: 0))
    }

    /// The sideways offset `cycles` into the shakes: straight between two keyframes.
    static func offset(at cycles: Double) -> CGFloat {
        guard cycles.isFinite else {
            return 0
        }
        let steps = Double(keyframes.count - 1)
        let phase = (cycles - cycles.rounded(.down)) * steps
        let index = min(Int(phase), keyframes.count - 2)
        let share = CGFloat(phase - Double(index))
        return keyframes[index] + (keyframes[index + 1] - keyframes[index]) * share
    }
}
