import SwiftUI

/// Motion tokens (docs/product-spec.md §8.8). Animations are explicit and respect Reduce Motion
/// (engineering-standards §7).
public nonisolated enum LedgerMotion {
    /// The default state-change animation.
    public static let snappy: Animation = .snappy

    /// One cycle of the buzz: `@keyframes buzz`, 0.38 s with CSS `ease`.
    public static let buzzCycle: TimeInterval = 0.38
    /// `buzz .38s ease 3`.
    public static let buzzRepeats = 3
    /// The x offsets at 20, 40, 60, 80 and 100 % of a cycle, starting from 0.
    static let buzzOffsets: [CGFloat] = [-3, 3, -2, 2, 0]
    /// Reduce Motion replaces the shake with one opacity dip per cycle.
    static let reducedMotionOpacity: Double = 0.4

    /// The buzz as keyframes over ``BuzzFrame``. With `reduceMotion` the offset track stays at 0
    /// for the whole run and the opacity track pulses instead, so no transform animates.
    @KeyframesBuilder<BuzzFrame>
    public static func buzzKeyframes(reduceMotion: Bool) -> some Keyframes<BuzzFrame> {
        KeyframeTrack(\BuzzFrame.offsetX) {
            for offset in shakeOffsets(reduceMotion: reduceMotion) {
                LinearKeyframe(offset, duration: buzzCycle / Double(buzzOffsets.count), timingCurve: .cssEase)
            }
        }
        KeyframeTrack(\BuzzFrame.opacity) {
            for opacity in pulseOpacities(reduceMotion: reduceMotion) {
                LinearKeyframe(opacity, duration: buzzCycle / 2, timingCurve: .cssEase)
            }
        }
    }

    static func shakeOffsets(reduceMotion: Bool) -> [CGFloat] {
        let cycles = Array(repeating: buzzOffsets, count: buzzRepeats).flatMap(\.self)
        return reduceMotion ? cycles.map { _ in 0 } : cycles
    }

    static func pulseOpacities(reduceMotion: Bool) -> [Double] {
        let dip = reduceMotion ? reducedMotionOpacity : 1
        return Array(repeating: [dip, 1], count: buzzRepeats).flatMap(\.self)
    }
}

/// The animated values of a buzz.
public nonisolated struct BuzzFrame: Equatable, Sendable {
    public var offsetX: CGFloat = 0
    public var opacity: Double = 1

    public init() {}
}

public extension View {
    /// Shakes the view horizontally each time `trigger` changes (the watch's visual stand-in for a
    /// haptic, §4.1); under Reduce Motion it pulses opacity instead.
    func ledgerBuzz(trigger: some Equatable & Sendable) -> some View {
        modifier(BuzzEffect(trigger: trigger))
    }
}

struct BuzzEffect<Trigger: Equatable & Sendable>: ViewModifier {
    let trigger: Trigger
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let reduced = reduceMotion
        content.keyframeAnimator(initialValue: BuzzFrame(), trigger: trigger) { view, frame in
            view.offset(x: frame.offsetX).opacity(frame.opacity)
        } keyframes: { _ in
            LedgerMotion.buzzKeyframes(reduceMotion: reduced)
        }
    }
}

private nonisolated extension UnitCurve {
    /// CSS `ease`, `cubic-bezier(.25, .1, .25, 1)`.
    static let cssEase = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.25, y: 0.1),
        endControlPoint: UnitPoint(x: 0.25, y: 1)
    )
}
