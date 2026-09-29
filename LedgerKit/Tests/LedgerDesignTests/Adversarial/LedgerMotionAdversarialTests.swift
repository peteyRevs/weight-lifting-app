import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

extension RenderingSuites {
    /// The buzz against spec §8.8: `@keyframes buzz { 0%,100% 0; 20% −3px; 40% 3px; 60% −2px; 80% 2px }`
    /// run as `buzz .38s ease 3`. CSS applies `ease` = cubic-bezier(.25, .1, .25, 1) to each keyframe
    /// interval, so halfway through an interval the value is 80.24 % of the way (ease(0.5) = 0.8024).
    @Suite("LedgerMotion (adversarial)", .tags(.design))
    struct LedgerMotionAdversarialTests {
        static let cycle = 0.38
        static let repeats = 3
        static let offsets: [CGFloat] = [-3, 3, -2, 2, 0]
        static let easeAtHalf = 0.802_403_387_6

        static func timeline(reduceMotion: Bool) -> KeyframeTimeline<BuzzFrame> {
            KeyframeTimeline(initialValue: BuzzFrame()) {
                LedgerMotion.buzzKeyframes(reduceMotion: reduceMotion)
            }
        }

        static func samples(_ timeline: KeyframeTimeline<BuzzFrame>, step: Double = 0.002) -> [(Double, BuzzFrame)] {
            stride(from: 0, through: cycle * Double(repeats), by: step).map { ($0, timeline.value(time: $0)) }
        }

        @Test(
            "The buzz is three 0.38 s cycles, 1.14 s in all, with or without Reduce Motion.",
            arguments: [false, true]
        )
        func buzz_duration_isThreeCycles(reduceMotion: Bool) {
            #expect(LedgerMotion.buzzCycle == Self.cycle)
            #expect(LedgerMotion.buzzRepeats == Self.repeats)
            #expect(abs(Self.timeline(reduceMotion: reduceMotion).duration - 1.14) < 0.001)
        }

        @Test("At each keyframe of each cycle the offset is −3, 3, −2, 2, 0 px and opacity stays 1.")
        func buzz_keyframeTimes_matchCSSKeyframes() {
            let timeline = Self.timeline(reduceMotion: false)
            #expect(timeline.value(time: 0) == BuzzFrame())
            for round in 0 ..< Self.repeats {
                for (index, offset) in Self.offsets.enumerated() {
                    let time = (Double(round) + Double(index + 1) * 0.2) * Self.cycle
                    let frame = timeline.value(time: time)
                    #expect(
                        abs(frame.offsetX - offset) < 0.01,
                        "cycle \(round) at \(time) s: \(frame.offsetX), CSS \(offset)"
                    )
                    #expect(frame.opacity == 1)
                }
            }
        }

        @Test("Between keyframes the offset follows CSS ease, not a linear or spring path.")
        func buzz_midInterval_followsCSSEase() {
            let timeline = Self.timeline(reduceMotion: false)
            let starts: [CGFloat] = [0] + Self.offsets.dropLast()
            for round in 0 ..< Self.repeats {
                for (index, target) in Self.offsets.enumerated() {
                    let time = (Double(round) + (Double(index) + 0.5) * 0.2) * Self.cycle
                    let start = starts[index]
                    let expected = start + (target - start) * Self.easeAtHalf
                    let actual = timeline.value(time: time).offsetX
                    #expect(abs(actual - expected) < 0.05, "at \(time) s: \(actual), CSS ease \(expected)")
                }
            }
        }

        @Test("With Reduce Motion nothing translates at any instant (criterion 7).")
        func buzz_reduceMotion_neverTranslates() {
            let moved = Self.samples(Self.timeline(reduceMotion: true)).filter { $0.1.offsetX != 0 }
            #expect(moved.isEmpty, "offset at \(moved.prefix(3).map(\.0))")
        }

        @Test("With Reduce Motion opacity pulses once in every cycle and ends fully opaque.")
        func buzz_reduceMotion_pulsesEveryCycle() {
            let timeline = Self.timeline(reduceMotion: true)
            let samples = Self.samples(timeline)
            for round in 0 ..< Self.repeats {
                let window = Double(round) * Self.cycle ..< Double(round + 1) * Self.cycle
                let lowest = samples.filter { window.contains($0.0) }.map(\.1.opacity).min() ?? 1
                #expect(lowest < 0.9, "cycle \(round): opacity never dips (min \(lowest))")
            }
            #expect(abs(timeline.value(time: 0).opacity - 1) < 0.001)
            #expect(abs(timeline.value(time: 1.14).opacity - 1) < 0.001)
        }

        @Test("Without Reduce Motion the shake never fades the view.")
        func buzz_fullMotion_neverFades() {
            let faded = Self.samples(Self.timeline(reduceMotion: false)).filter { $0.1.opacity != 1 }
            #expect(faded.isEmpty, "opacity changes at \(faded.prefix(3).map(\.0))")
        }

        @Test("At rest, .ledgerBuzz leaves the view exactly where and as opaque as it was.")
        func ledgerBuzz_atRest_leavesViewUntouched() throws {
            let plain = Color.white.frame(width: 20, height: 10).padding(6).background(Color.black)
            let buzzing = Color.white.frame(width: 20, height: 10).ledgerBuzz(trigger: 0).padding(6)
                .background(Color.black)
            let expected = try #require(Probe.buffer(plain, scale: 2))
            #expect(Probe.buffer(buzzing, scale: 2) == expected)
        }
    }
}
