#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    extension RenderingSuites {
        /// `PillButton`'s two later states (F08 S2 fix round 1, review S2-SF5): disabled, it looks disabled; and
        /// `flush` stands the pill at an edge of its 44 pt target, so that a ghost pill's word lines up with the
        /// content beside it. Its trees are rows of `AccessibilityTreeTests`' table.
        @Suite("PillButtonStates", .tags(.design))
        struct PillButtonStateTests {
            nonisolated static let styles: [PillButton.Style] = [.outline, .filled, .ghost]

            /// `view` on the ground at its own size, 1×.
            private static func drawn(_ view: some View, _ scheme: ColorScheme = .dark) throws -> PixelBuffer {
                let image = RenderedImage.render(view.background(LedgerColor.ground), colorScheme: scheme)
                return try #require(image.flatMap(PixelBuffer.init))
            }

            /// The columns of `view` that hold ink: where its word is, in a target wider than the word.
            private static func ink(of view: some View) throws -> (columns: ClosedRange<Int>, width: Int) {
                let buffer = try drawn(view)
                let columns = try #require(buffer.inkedColumns(differingFrom: buffer.pixel(column: 0, row: 0)))
                return (columns, buffer.width)
            }

            @Test("A disabled pill looks different from an enabled one, in every style and theme", arguments: styles)
            func disabledPill_looksDisabled(_ style: PillButton.Style) throws {
                for scheme in [ColorScheme.light, .dark] {
                    let pill = PillButton("Finish", style: style) {}
                    #expect(try Self.drawn(pill, scheme) != Self.drawn(pill.disabled(true), scheme), "\(scheme)")
                }
            }

            @Test("A disabled pill keeps its size: disabling one moves nothing around it", arguments: styles)
            func disabledPill_keepsItsSize(_ style: PillButton.Style) throws {
                let pill = PillButton("Finish", style: style) {}
                let enabled = try Self.drawn(pill)
                let disabled = try Self.drawn(pill.disabled(true))
                #expect(enabled.width == disabled.width && enabled.height == disabled.height)
            }

            @Test("A disabled pill does nothing when VoiceOver activates it, and says it is dimmed", arguments: styles)
            func disabledPill_doesNothing(_ style: PillButton.Style) {
                var taps = 0
                let traits = PillButton("Finish", style: style) { taps += 1 }.disabled(true)
                    .withAccessibilityElements { elements in
                        for element in elements {
                            _ = element.accessibilityActivate()
                        }
                        return elements.map(\.accessibilityTraits)
                    }
                #expect(taps == 0)
                #expect(traits.count == 1 && traits.allSatisfy { $0.contains(.notEnabled) })
            }

            /// F10 S6, criterion 9: the full-width pill, a row's second action beside a `PrimaryButton`.
            @Test("A full-width pill takes the width it is offered and a primary button's height; a plain one neither")
            func fullWidthPill_fillsItsRow() throws {
                let offered = 180
                let full = try Self.drawn(PillButton("+30s", fillsWidth: true) {}.frame(width: CGFloat(offered)))
                let primary = try Self.drawn(PrimaryButton("Skip rest") {}.frame(width: CGFloat(offered)))
                #expect(full.width == offered && full.height == primary.height)
                // Its outline reaches both edges of the width: ink in the first and the last columns.
                let ground = full.pixel(column: 0, row: 0)
                let inked = try #require(full.inkedColumns(differingFrom: ground))
                #expect(inked.lowerBound <= 1 && inked.upperBound >= offered - 2, "\(inked)")
                let plain = try Self.drawn(PillButton("+30s") {}.frame(width: CGFloat(offered)))
                let plainInk = try #require(plain.inkedColumns(differingFrom: plain.pixel(column: 0, row: 0)))
                #expect(plainInk.count < offered / 2, "a pill that does not fill keeps its text's width")
                #expect(plain.height < full.height)
            }

            @Test("A full-width pill is one button, read by its title, and looks disabled when it is")
            func fullWidthPill_isAButton() throws {
                let pill = PillButton("+30s", fillsWidth: true) {}.frame(width: 180)
                let stops = pill.accessibilityElements(SnapshotAppearance(.light, .large))
                #expect(stops.map(\.label) == ["+30s"])
                #expect(stops.first?.traits.contains(.button) == true)
                let isSame = try Self.drawn(pill) == Self.drawn(pill.disabled(true))
                #expect(!isSame)
            }

            @Test("A short ghost pill stands in the middle of its target; flush, its word starts or ends at the edge")
            func flushGhostPill_standsAtTheEdgeOfItsTarget() throws {
                let centred = try Self.ink(of: PillButton("Back", style: .ghost) {})
                let leading = try Self.ink(of: PillButton("Back", style: .ghost, flush: .leading) {})
                let trailing = try Self.ink(of: PillButton("Back", style: .ghost, flush: .trailing) {})
                #expect(centred.width == 44, "control: the word is narrower than the 44 pt target")
                #expect(leading.width == 44 && trailing.width == 44, "the target is the same size wherever it stands")

                // A glyph's own side bearing is a point or two; the centred word starts several points in.
                #expect(leading.columns.lowerBound <= 2, "\(leading.columns)")
                #expect(trailing.columns.upperBound >= 44 - 3, "\(trailing.columns)")
                #expect(centred.columns.lowerBound >= 5, "\(centred.columns)")
                #expect(centred.columns.upperBound <= 44 - 6, "\(centred.columns)")
                #expect(leading.columns.count == centred.columns.count, "the same word, moved")
            }

            @Test("A flush pill keeps its 44 pt target and its label, at the default and the largest text size")
            func flushPill_keepsItsTarget() throws {
                for appearance in ComponentAccessibilityTests.sizes {
                    for edge in [HorizontalEdge.leading, .trailing] {
                        let pill = PillButton("Back", style: .ghost, flush: edge) {}
                        let elements = pill.accessibilityElements(appearance)
                        let button = try #require(elements.first)
                        #expect(elements.count == 1)
                        #expect(button.label == "Back")
                        expectButton(button)
                    }
                }
            }

            @Test("A pill wider than its target stands where it stood, flush or not: there is nothing to move")
            func widePill_standsTheSameFlushOrNot() throws {
                let title = "Repeat last session's sets"
                let plain = try Self.ink(of: PillButton(title) {})
                #expect(plain.width > 44, "control: the pill is wider than the target")
                for edge in [HorizontalEdge.leading, .trailing] {
                    // Not pixel for pixel: a one-line title set from an edge can sit a fraction of a point from
                    // where it sits centred in the same width.
                    let flush = try Self.ink(of: PillButton(title, flush: edge) {})
                    #expect(flush.width == plain.width, "\(edge)")
                    #expect(abs(flush.columns.lowerBound - plain.columns.lowerBound) <= 1, "\(edge)")
                    #expect(abs(flush.columns.upperBound - plain.columns.upperBound) <= 1, "\(edge)")
                }
            }
        }

        /// The gallery of those states in the phone matrix, light and dark × large, xLarge and accessibility3.
        /// `PillButtonGallery` and its references are as they were. Recorded on the PR plan's iPhone 17 (iOS 27.0).
        @Suite("PillButtonStatesSnapshots", .tags(.design, .snapshot))
        struct PillButtonStatesSnapshotTests {
            nonisolated static let phoneMatrix = SnapshotAppearance.phoneMatrix

            @Test("PillButton's disabled and flush states match their references", arguments: phoneMatrix)
            func pillButtonStates_appearance_matchesReference(_ appearance: SnapshotAppearance) {
                assertPhoneSnapshot(of: PillButtonStatesGallery().phonePage(), appearance)
            }
        }
    }
#endif
