import CoreText
@testable import LedgerDesign
import LedgerSnapshotTesting
import SnapshotTesting
import SwiftUI
import Testing

extension RenderingSuites {
    @Suite("ArchivoFont", .tags(.design))
    struct ArchivoFontTests {
        @Test("Registration makes the bundled Archivo resolvable by its PostScript name")
        func registration_bundledFont_isResolvable() {
            #expect(FontRegistration.registerIfNeeded())
            #expect(ArchivoFont.isResolvable)
        }

        @Test("Registering again is a no-op that still reports success")
        func registration_repeatedCalls_keepSucceeding() {
            #expect(FontRegistration.registerIfNeeded())
            #expect(FontRegistration.registerIfNeeded())
        }

        @Test("The bundled file is the variable build: wght 100–900 and wdth 62–125")
        func font_variationAxes_matchFvarTable() throws {
            let font = ArchivoFont.make(size: 20, weight: 600, width: 100)
            let axes = try #require(CTFontCopyVariationAxes(font) as? [[String: Any]])
            let ranges = Dictionary(uniqueKeysWithValues: axes.compactMap { axis -> (Int, ClosedRange<Double>)? in
                guard let tag = axis[kCTFontVariationAxisIdentifierKey as String] as? Int,
                      let low = axis[kCTFontVariationAxisMinimumValueKey as String] as? Double,
                      let high = axis[kCTFontVariationAxisMaximumValueKey as String] as? Double
                else { return nil }
                return (tag, low ... high)
            })
            #expect(ranges[ArchivoFont.weightAxis] == 100 ... 900)
            #expect(ranges[ArchivoFont.widthAxis] == 62 ... 125)
        }

        @Test("Requested axis values reach Core Text", arguments: [(300.0, 88.0), (500, 100), (700, 112)])
        func make_axisValues_appliedToFont(weight: Double, width: Double) {
            let variation = variation(of: ArchivoFont.make(size: 20, weight: weight, width: width))
            #expect(variation[ArchivoFont.weightAxis] == weight)
            // wdth 100 is the default, which Core Text omits from the instance's variation dictionary.
            #expect(variation[ArchivoFont.widthAxis] ?? 100 == width)
        }

        @Test("Axis values outside the font's ranges are clamped, not ignored")
        func make_outOfRangeAxes_areClamped() {
            let low = variation(of: ArchivoFont.make(size: 20, weight: 20, width: 10))
            let high = variation(of: ArchivoFont.make(size: 20, weight: 2000, width: 400))
            #expect(low[ArchivoFont.weightAxis] == 100)
            #expect(low[ArchivoFont.widthAxis] == 62)
            #expect(high[ArchivoFont.weightAxis] == 900)
            #expect(high[ArchivoFont.widthAxis] == 125)
        }

        /// F06 criterion 1, risk R2: the width axis must render on this simulator, not just be
        /// accepted by Core Text. Runs in both the iOS and the watchOS plan.
        @Test("Spike: wdth 112 renders visibly wider glyphs than wdth 88 on this platform")
        func widthAxis_88versus112_rendersDifferentGlyphWidths() throws {
            let narrow = try inkedWidth(of: Self.spikeLine(width: 88))
            let wide = try inkedWidth(of: Self.spikeLine(width: 112))
            // Advance widths on the host differ by 26 % (160.3 vs 201.7 pt for "0123456789" at 30 pt).
            #expect(Double(wide) > Double(narrow) * 1.15, "wdth 88: \(narrow) px, wdth 112: \(wide) px")

            let evidence = try #require(RenderedImage.render(Self.spikeSheet))
            assertSnapshot(of: evidence, as: .png, named: SnapshotConfig.platform)
        }

        @Test("Spike: wght 700 lays down more ink than wght 300 on this platform")
        func weightAxis_300versus700_rendersDifferentStrokes() throws {
            let light = try inkCoverage(of: Text("0123456789").font(LedgerFont.archivo(
                size: 30,
                weight: 300,
                width: 100
            )))
            let bold = try inkCoverage(of: Text("0123456789").font(LedgerFont.archivo(
                size: 30,
                weight: 700,
                width: 100
            )))
            #expect(Double(bold) > Double(light) * 1.3, "wght 300: \(light), wght 700: \(bold) inked pixels")
        }

        @Test("Numeral roles use tabular figures; other roles keep proportional ones")
        func numeralRoles_digits_haveEqualAdvances() throws {
            let ones = try #require(RenderedImage.render(Text("1111").font(LedgerFont.font(.numeralM, size: 24))))
            let eights = try #require(RenderedImage.render(Text("8888").font(LedgerFont.font(.numeralM, size: 24))))
            #expect(ones.width == eights.width)

            let proportionalOnes = try #require(RenderedImage.render(Text("1111").font(LedgerFont.font(
                .body,
                size: 15
            ))))
            let proportionalEights = try #require(RenderedImage.render(Text("8888").font(LedgerFont.font(
                .body,
                size: 15
            ))))
            #expect(proportionalOnes.width < proportionalEights.width)
        }

        // MARK: - Helpers

        static func spikeLine(width: CGFloat) -> some View {
            Text("0123456789")
                .font(LedgerFont.archivo(size: 30, weight: 700, width: width))
                .foregroundStyle(LedgerColor.ink)
                .padding(LedgerSpacing.s)
                .background(LedgerColor.ground)
        }

        static var spikeSheet: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach([62, 88, 100, 112, 125] as [CGFloat], id: \.self) { width in
                    HStack(alignment: .firstTextBaseline, spacing: LedgerSpacing.s) {
                        Text("wdth \(Int(width))").ledgerFont(.caption).foregroundStyle(LedgerColor.inkMuted)
                            .frame(width: 64, alignment: .leading)
                        spikeLine(width: width)
                    }
                }
            }
            .padding(LedgerSpacing.s)
            .background(LedgerColor.ground)
        }

        private func variation(of font: CTFont) -> [Int: Double] {
            (CTFontCopyVariation(font) as? [Int: Double]) ?? [:]
        }

        private func inkedWidth(of view: some View) throws -> Int {
            let pixels = try #require(RenderedImage.render(view).flatMap(PixelBuffer.init))
            let columns = try #require(pixels.inkedColumns(differingFrom: Pixel(hex: 0x0B0B0D)))
            return columns.count
        }

        private func inkCoverage(of text: some View) throws -> Int {
            let view = text.foregroundStyle(LedgerColor.ink).padding(LedgerSpacing.s).background(LedgerColor.ground)
            let pixels = try #require(RenderedImage.render(view).flatMap(PixelBuffer.init))
            return pixels.pixels.count { $0.red > 0x80 }
        }
    }
}
