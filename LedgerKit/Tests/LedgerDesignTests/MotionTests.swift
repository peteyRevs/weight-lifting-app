@testable import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

extension RenderingSuites {
    /// F06 criterion 7 and spec §8.8: the buzz is three 0.38 s x-shakes, and under Reduce Motion no
    /// transform animates, only opacity. The keyframes under test are the ones `ledgerBuzz` plays.
    @Suite("Motion", .tags(.design))
    struct MotionTests {
        /// Samples a keyframe timeline every millisecond from start to end.
        private func samples(reduceMotion: Bool) -> (duration: Double, frames: [BuzzFrame]) {
            let timeline = KeyframeTimeline(initialValue: BuzzFrame()) {
                LedgerMotion.buzzKeyframes(reduceMotion: reduceMotion)
            }
            let steps = Int((timeline.duration * 1000).rounded())
            return (timeline.duration, (0 ... steps).map { timeline.value(time: Double($0) / 1000) })
        }

        @Test("The buzz lasts three cycles of 0.38 s in both modes", arguments: [false, true])
        func buzz_duration_isThreeCycles(reduceMotion: Bool) {
            #expect(abs(samples(reduceMotion: reduceMotion).duration - 3 * 0.38) < 0.0001)
        }

        @Test("Without Reduce Motion the view shakes ±3 pt and keeps full opacity")
        func buzz_default_shakesHorizontally() {
            let frames = samples(reduceMotion: false).frames
            let offsets = frames.map(\.offsetX)
            #expect(abs((offsets.min() ?? 0) + 3) < 0.01)
            #expect(abs((offsets.max() ?? 0) - 3) < 0.01)
            #expect(frames.allSatisfy { $0.opacity == 1 })
        }

        @Test("With Reduce Motion no transform runs; opacity pulses instead")
        func buzz_reduceMotion_pulsesOpacityWithoutOffset() {
            let frames = samples(reduceMotion: true).frames
            #expect(frames.allSatisfy { $0.offsetX == 0 })
            #expect(abs((frames.map(\.opacity).min() ?? 1) - 0.4) < 0.01)
        }

        @Test("The buzz ends where it started", arguments: [false, true])
        func buzz_end_returnsToRest(reduceMotion: Bool) {
            #expect(samples(reduceMotion: reduceMotion).frames.last == BuzzFrame())
        }

        @Test("Each shake cycle follows the keyframe offsets -3, 3, -2, 2, 0")
        func buzz_cycleOffsets_matchSpecKeyframes() {
            let timeline = KeyframeTimeline(initialValue: BuzzFrame()) {
                LedgerMotion.buzzKeyframes(reduceMotion: false)
            }
            let step = 0.38 / 5
            let cycle = (1 ... 5).map { timeline.value(time: step * Double($0)).offsetX }
            #expect(zip(cycle, [-3, 3, -2, 2, 0] as [CGFloat]).allSatisfy { abs($0 - $1) < 0.01 }, "\(cycle)")
        }

        /// `accessibilityReduceMotion` is read-only in `EnvironmentValues`, so the Reduce Motion branch
        /// is covered through the keyframes above; this checks the modifier itself.
        @Test("At rest, ledgerBuzz leaves the view exactly as it was")
        func ledgerBuzz_atRest_rendersUnchanged() throws {
            let label = Text("185 × 5").ledgerFont(.numeralM).foregroundStyle(LedgerColor.ink)
                .padding(LedgerSpacing.s).background(LedgerColor.ground)
            let plain = try #require(RenderedImage.render(label).flatMap(PixelBuffer.init))
            let buzzing = try #require(RenderedImage.render(label.ledgerBuzz(trigger: 0)).flatMap(PixelBuffer.init))
            #expect(buzzing == plain)
        }
    }
}
