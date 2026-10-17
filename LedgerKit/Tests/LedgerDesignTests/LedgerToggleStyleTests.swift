#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    extension RenderingSuites {
        /// F11 S8 criterion 2: `.toggleStyle(.ledger)` is SwiftUI's switch to VoiceOver, with its value; its
        /// tap flips the binding; the knob reads on what it stands on in both themes and under Increase
        /// Contrast; and nothing of it is orange.
        @Suite("LedgerToggleStyle", .tags(.design))
        struct LedgerToggleStyleTests {
            private static func toggle(_ isOn: Bool) -> some View {
                Toggle(isOn: .constant(isOn)) { Text(verbatim: "Drop set") }
            }

            private static func drawn(_ view: some View, _ scheme: ColorScheme = .dark) throws -> PixelBuffer {
                let image = RenderedImage.render(
                    view.background(LedgerColor.ground),
                    width: SnapshotConfig.phoneWidth,
                    colorScheme: scheme
                )
                return try #require(image.flatMap(PixelBuffer.init))
            }

            @Test("VoiceOver finds what it finds in SwiftUI's own switch: label, value and traits", arguments: [
                true, false
            ])
            func toggle_accessibility_isSwiftUIsSwitch(_ isOn: Bool) throws {
                for isEnabled in [true, false] {
                    let system = Self.toggle(isOn).toggleStyle(.switch).disabled(!isEnabled).accessibilityElements()
                    let ledger = Self.toggle(isOn).toggleStyle(.ledger).disabled(!isEnabled).accessibilityElements()
                    let expected = try #require(system.first)
                    let found = try #require(ledger.first)
                    #expect(system.count == 1 && ledger.count == 1, "\(system) \(ledger)")
                    #expect(found.label == "Drop set" && found.label == expected.label)
                    #expect(found.value == expected.value && found.value == (isOn ? "1" : "0"))
                    #expect(found.traits == expected.traits, "\(found.traits.rawValue) \(expected.traits.rawValue)")
                    #expect(found.traits.contains(.notEnabled) == !isEnabled)
                    expectTarget(found)
                }
            }

            @Test("VoiceOver's double-tap flips the switch, and the value it announces follows")
            func toggle_activated_flipsTheBinding() {
                ToggleHarness().withLiveAccessibilityElements { read in
                    #expect(read().map { $0.accessibilityValue ?? "" } == ["0"])
                    #expect(read().first?.accessibilityActivate() == true)
                    #expect(read().first?.accessibilityValue == "1")
                    _ = read().first?.accessibilityActivate()
                    #expect(read().first?.accessibilityValue == "0")
                }
            }

            @Test("A disabled switch does not flip")
            func toggle_disabled_doesNotFlip() {
                ToggleHarness().disabled(true).withLiveAccessibilityElements { read in
                    _ = read().first?.accessibilityActivate()
                    #expect(read().map { $0.accessibilityValue ?? "" } == ["0"])
                }
            }

            @Test("On and off are drawn differently and at one size; the knob stands at the trailing side when on")
            func toggle_onAndOff_differByFillAndSide() throws {
                for scheme in [ColorScheme.light, .dark] {
                    let drawnOff = try Self.drawn(Self.toggle(false).toggleStyle(.ledger), scheme)
                    let drawnOn = try Self.drawn(Self.toggle(true).toggleStyle(.ledger), scheme)
                    let isSameSize = drawnOff.width == drawnOn.width && drawnOff.height == drawnOn.height
                    #expect(isSameSize, "\(scheme)")
                    let differs = drawnOff != drawnOn
                    #expect(differs, "\(scheme)")
                    #expect(drawnOff.height >= 44, "\(scheme)")
                    // The middle row of the 52 pt track at the trailing edge: 3 pt in from each end is knob
                    // or not. Off, the knob (muted ink) is at the left; on, the knob (ground) is at the right.
                    let row = drawnOff.height / 2
                    let ground = drawnOff.pixel(column: 0, row: 0)
                    let left = drawnOff.width - 52 + 10
                    let right = drawnOff.width - 10
                    #expect(
                        drawnOff.pixel(column: left, row: row).differs(from: ground, by: 24),
                        "\(scheme): knob at the left"
                    )
                    #expect(
                        !drawnOff.pixel(column: right, row: row).differs(from: ground, by: 24),
                        "\(scheme): empty track"
                    )
                    #expect(
                        !drawnOn.pixel(column: right, row: row).differs(from: ground, by: 24),
                        "\(scheme): ground knob"
                    )
                    #expect(drawnOn.pixel(column: left, row: row).differs(from: ground, by: 24), "\(scheme): ink track")
                }
            }

            @Test("No pixel of the switch is orange, on or off, in either theme")
            func toggle_drawsNoAccent() throws {
                for scheme in [ColorScheme.light, .dark] {
                    for isOn in [true, false] {
                        let buffer = try Self.drawn(Self.toggle(isOn).toggleStyle(.ledger), scheme)
                        // The accent is #FF5B22: far more red than blue. Ink, paper and ground are near grey.
                        let isOrange = buffer.pixels.contains { Int($0.red) - Int($0.blue) > 60 }
                        #expect(!isOrange, "\(scheme) \(isOn)")
                    }
                }
            }

            @Test(
                "The knob has 3:1 against what it stands on, in both themes, with and without Increase Contrast",
                arguments: [true, false]
            )
            func knob_contrast_meetsThreeToOne(_ isOn: Bool) {
                for style in [UIUserInterfaceStyle.light, .dark] {
                    for high in [false, true] {
                        let resolve = { (color: Color) in IncreaseContrastTests.resolve(color, style, high: high) }
                        let ground = resolve(LedgerColor.ground)
                        let knob = resolve(LedgerToggleLook.knob(isOn: isOn, isEnabled: true))
                        // On, the knob stands on the track's fill; off, on the ground inside the outline.
                        let under = isOn
                            ? resolve(LedgerToggleLook.track(isOn: true, isEnabled: true)).composited(over: ground)
                            : ground
                        let ratio = knob.contrast(on: under)
                        #expect(ratio >= 3, "\(isOn ? "on" : "off") \(style.rawValue) high \(high): \(ratio):1")
                        if isOn {
                            // The filled track is what says "on": it has to stand out from the ground too.
                            #expect(under.contrast(on: ground) >= 3, "track \(style.rawValue) high \(high)")
                        }
                    }
                }
            }
        }
    }

    /// A switch wired to state, as a feature's store would wire it.
    private struct ToggleHarness: View {
        @State private var isOn = false

        var body: some View {
            Toggle(isOn: $isOn) { Text(verbatim: "Drop set") }
                .toggleStyle(.ledger)
        }
    }
#endif
