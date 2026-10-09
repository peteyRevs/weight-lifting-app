#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    extension RenderingSuites {
        /// F11 S8 adversarial round 1, criterion 2: `.toggleStyle(.ledger)` measured from what is drawn, not
        /// from the colours the style says it uses: the knob against what it stands on and the filled track
        /// against the ground, in both themes with and without Increase Contrast; each state unlike the
        /// others; and VoiceOver's switch, which sets the binding once for one double-tap.
        @Suite("Adversarial F11 S8 · LedgerToggleStyle", .tags(.design))
        struct LedgerToggleAdversarialTests {
            static let longLabel = "Keep the screen awake for as long as a workout is running, also while resting"

            private static func toggle(_ isOn: Bool, _ title: String = "Drop set") -> some View {
                Toggle(isOn: .constant(isOn)) { Text(verbatim: title) }.toggleStyle(.ledger)
            }

            private static func sample(_ buffer: PixelBuffer, isOn: Bool) -> AdvToggleSample {
                let row = buffer.height / 2
                let trailing = buffer.width
                let knob = isOn ? trailing - 16 : trailing - 36
                let track = isOn ? trailing - 40 : trailing - 12
                return AdvToggleSample(
                    knob: AdvForm.color(buffer.pixel(column: knob, row: row)),
                    track: AdvForm.color(buffer.pixel(column: track, row: row)),
                    ground: AdvForm.color(buffer.pixel(column: trailing - 70, row: row))
                )
            }

            @Test(
                "As drawn, the knob has 3:1 against what it stands on and the on track 3:1 against the ground",
                arguments: [ColorScheme.light, .dark]
            )
            func knobAndTrack_drawn_meetThreeToOne(_ scheme: ColorScheme) throws {
                let cell = SnapshotAppearance(scheme, .large)
                for contrast in [ColorSchemeContrast.standard, .increased] {
                    let off = try Self.sample(AdvForm.drawn(Self.toggle(false), cell, contrast: contrast), isOn: false)
                    let offRatio = off.knob.contrast(on: off.track)
                    #expect(offRatio >= 3, "off \(scheme) \(contrast): knob \(off.knob) on \(off.track), \(offRatio)")
                    #expect(off.track.matches(off.ground), "off \(scheme) \(contrast): the track is not filled")
                    let drawnOn = try Self.sample(
                        AdvForm.drawn(Self.toggle(true), cell, contrast: contrast),
                        isOn: true
                    )
                    let knobRatio = drawnOn.knob.contrast(on: drawnOn.track)
                    let trackRatio = drawnOn.track.contrast(on: drawnOn.ground)
                    #expect(knobRatio >= 3, "on \(scheme) \(contrast): knob \(drawnOn.knob) on \(drawnOn.track)")
                    #expect(trackRatio >= 3, "on \(scheme) \(contrast): track \(drawnOn.track) on \(drawnOn.ground)")
                }
            }

            @Test(
                "On, off and each of them disabled are four drawings, in both themes, also under Increase Contrast",
                arguments: [ColorScheme.light, .dark]
            )
            func fourStates_areFourDrawings(_ scheme: ColorScheme) throws {
                let cell = SnapshotAppearance(scheme, .large)
                for contrast in [ColorSchemeContrast.standard, .increased] {
                    let drawings = try [
                        AdvForm.drawn(Self.toggle(false), cell, contrast: contrast),
                        AdvForm.drawn(Self.toggle(true), cell, contrast: contrast),
                        AdvForm.drawn(Self.toggle(false).disabled(true), cell, contrast: contrast),
                        AdvForm.drawn(Self.toggle(true).disabled(true), cell, contrast: contrast)
                    ]
                    for first in drawings.indices {
                        for second in drawings.indices where second > first {
                            let differs = drawings[first] != drawings[second]
                            #expect(differs, "\(scheme) \(contrast): states \(first) and \(second) look alike")
                        }
                    }
                    // A disabled switch still shows its knob.
                    let disabledOff = Self.sample(drawings[2], isOn: false)
                    let isVisible = !disabledOff.knob.matches(disabledOff.ground)
                    #expect(isVisible, "\(scheme) \(contrast): the disabled knob is not drawn")
                }
            }

            @Test(
                "In every cell the track keeps its size at the trailing edge, whatever the label's length",
                arguments: AdvForm.cells
            )
            func track_everyCell_staysAtTheTrailingEdge(_ cell: SnapshotAppearance) throws {
                for title in ["Drop set", Self.longLabel] {
                    let buffer = try AdvForm.drawn(Self.toggle(true, title), cell)
                    let found = Self.sample(buffer, isOn: true)
                    #expect(buffer.width == AdvForm.width && buffer.height >= 44, "\(cell)")
                    #expect(found.track.contrast(on: found.ground) >= 3, "\(cell) «\(title.prefix(8))»: no track")
                    #expect(found.knob.contrast(on: found.track) >= 3, "\(cell) «\(title.prefix(8))»: no knob")
                    // The track's last column is the row's last: nothing pushes it out or in.
                    let row = buffer.height / 2
                    let end = AdvForm.color(buffer.pixel(column: buffer.width - 2, row: row))
                    #expect(end.matches(found.track), "\(cell) «\(title.prefix(8))»: the track ends early")
                }
            }

            @Test("Right to left the track stands at the left edge and the on knob at its left end")
            func rightToLeft_mirrorsTheSwitch() throws {
                let buffer = try AdvForm.drawn(Self.toggle(true).environment(\.layoutDirection, .rightToLeft))
                let row = buffer.height / 2
                let ground = AdvForm.color(buffer.pixel(column: 70, row: row))
                let track = AdvForm.color(buffer.pixel(column: 40, row: row))
                let knob = AdvForm.color(buffer.pixel(column: 16, row: row))
                #expect(track.contrast(on: ground) >= 3, "the track is not at the left edge")
                #expect(knob.contrast(on: track) >= 3, "the on knob is not at the track's left end")
            }

            @Test(
                "In every cell VoiceOver finds what it finds in the system's switch, a 44 pt target inside the row",
                arguments: AdvForm.cells
            )
            func switch_everyCell_isTheSystemsToVoiceOver(_ cell: SnapshotAppearance) {
                for isOn in [false, true] {
                    let plain = Toggle(isOn: .constant(isOn)) { Text(verbatim: Self.longLabel) }
                    let system = plain.toggleStyle(.switch).accessibilityElements(cell)
                    let ledger = plain.toggleStyle(.ledger).accessibilityElements(cell)
                    #expect(system.count == 1 && ledger.count == 1, "\(cell): \(ledger)")
                    let isTheSame = ledger.map(\.label) == system.map(\.label)
                        && ledger.map(\.value) == system.map(\.value) && ledger.map(\.traits) == system.map(\.traits)
                    #expect(isTheSame, "\(cell) \(isOn): \(ledger) against \(system)")
                    #expect(ledger.map(\.value) == [isOn ? "1" : "0"] && ledger.map(\.label) == [Self.longLabel])
                    for element in ledger {
                        let isInside = element.frame.minX >= -0.001
                            && element.frame.maxX <= SnapshotConfig.phoneWidth + 0.001
                        #expect(isInside && element.frame.height >= 44 - 0.001, "\(cell): \(element.frame)")
                    }
                }
            }

            @Test("One double-tap sets the binding once, to the other state; a disabled switch sets nothing")
            func activation_setsTheBindingOnce() {
                let stored = AdvToggleStored()
                let binding = Binding(get: { stored.isOn }, set: {
                    stored.isOn = $0
                    stored.sets.append($0)
                })
                let toggle = Toggle(isOn: binding) { Text(verbatim: "Drop set") }.toggleStyle(.ledger)
                toggle.withLiveAccessibilityElements { read in
                    #expect(read().first?.accessibilityActivate() == true)
                    #expect(stored.sets == [true], "\(stored.sets)")
                    _ = read().first?.accessibilityActivate()
                    #expect(stored.sets == [true, false], "\(stored.sets)")
                }
                toggle.disabled(true).withLiveAccessibilityElements { read in
                    _ = read().first?.accessibilityActivate()
                    #expect(stored.sets == [true, false], "a disabled switch set the binding: \(stored.sets)")
                }
            }
        }
    }

    /// The middle row of the 52 pt track at the trailing edge: the knob's middle, a point of the track the
    /// knob does not cover, and the ground left of the track.
    struct AdvToggleSample {
        let knob: SRGB
        let track: SRGB
        let ground: SRGB
    }

    /// What a store's binding sees.
    final class AdvToggleStored {
        var isOn = false
        var sets: [Bool] = []
    }
#endif
