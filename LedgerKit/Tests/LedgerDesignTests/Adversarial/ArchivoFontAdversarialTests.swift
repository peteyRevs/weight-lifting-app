import CoreText
import Foundation
import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

/// Archivo registration and the variable axes, on whichever simulator runs the plan (the PR plan
/// on iOS 26.5, PR-Watch on watchOS 26.5), so every test here is also the watchOS spike.
@Suite("Archivo loading (adversarial)", .tags(.design))
struct ArchivoFontAdversarialTests {
    static let digits = "0123456789"

    static func registeredArchivo(size: CGFloat = 12) throws -> CTFont {
        #expect(FontRegistration.registerIfNeeded())
        let name = try #require(ArchivoFile.postScriptName, "Archivo not found next to the test bundle")
        return CTFontCreateWithName(name as CFString, size, nil)
    }

    static func digitsImage(weight: CGFloat, width: CGFloat, scale: CGFloat = 1) throws -> CGImage {
        let text = Text(digits).font(LedgerFont.archivo(size: 30, weight: weight, width: width))
        return try #require(Probe.image(text, scale: scale))
    }

    @Test("registerIfNeeded is idempotent: five calls in a row all report success.")
    func registration_calledRepeatedly_alwaysSucceeds() {
        let results = (0 ..< 5).map { _ in FontRegistration.registerIfNeeded() }
        #expect(results == Array(repeating: true, count: 5))
    }

    @Test("registerIfNeeded is safe under concurrent use: 64 racing callers all succeed.", .timeLimit(.minutes(1)))
    func registration_concurrentCallers_allSucceed() async {
        let results = await withTaskGroup(of: Bool.self) { group in
            for _ in 0 ..< 64 {
                group.addTask { FontRegistration.registerIfNeeded() }
            }
            var collected: [Bool] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }
        #expect(results.count == 64)
        #expect(!results.contains(false))
    }

    @Test("A registration someone else made first (the apps' UIAppFonts) still counts as success.")
    func registration_afterExternalRegistration_succeeds() throws {
        let url = try #require(ArchivoFile.url)
        var error: Unmanaged<CFError>?
        // Either registers first (the app case) or reports "already registered"; both are fine here.
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        _ = error?.takeRetainedValue()
        #expect(FontRegistration.registerIfNeeded())
        let font = try Self.registeredArchivo()
        #expect(CTFontCopyFamilyName(font) as String == "Archivo")
    }

    @Test("The PostScript name resolves to Archivo itself, not a substitute face.")
    func registration_postScriptName_resolvesToArchivo() throws {
        let font = try Self.registeredArchivo()
        #expect(CTFontCopyPostScriptName(font) as String == ArchivoFile.postScriptName)
        #expect(CTFontCopyFamilyName(font) as String == "Archivo")
    }

    @Test("The font Core Text resolves is byte-for-byte the file in LedgerDesign's resource bundle.")
    func registration_resolvedFont_isTheBundledFile() throws {
        let font = try Self.registeredArchivo()
        let url = try #require(CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL)
        #expect(url.lastPathComponent == ArchivoFile.fileName)
        #expect(try Data(contentsOf: url) == ArchivoFile.data)
    }

    @Test("Archivo exposes wght 100…900 and wdth 62…125 on this platform.")
    func archivo_variationAxes_includeWeightAndWidth() throws {
        let font = try Self.registeredArchivo()
        let axes = try #require(CTFontCopyVariationAxes(font)) as NSArray
        var ranges: [Int: ClosedRange<Double>] = [:]
        for case let axis as NSDictionary in axes {
            guard let tag = axis[kCTFontVariationAxisIdentifierKey] as? Int,
                  let low = axis[kCTFontVariationAxisMinimumValueKey] as? Double,
                  let high = axis[kCTFontVariationAxisMaximumValueKey] as? Double
            else { continue }
            ranges[tag] = low ... high
        }
        #expect(ranges[ArchivoFile.weightTag] == 100 ... 900, "axes: \(ranges)")
        #expect(ranges[ArchivoFile.widthTag] == 62 ... 125, "axes: \(ranges)")
    }

    @Test("wdth renders on this platform: 62 < 88 < 100 < 112 < 125 set the same digits strictly wider.")
    func archivo_widthAxis_growsMonotonically() throws {
        let widths = try [CGFloat(62), 88, 100, 112, 125].map { try Self.digitsImage(weight: 700, width: $0).width }
        #expect(zip(widths, widths.dropFirst()).allSatisfy { $0 < $1 }, "widths \(widths)")
    }

    @Test("wdth outside the font's 62…125 clamps to the axis ends instead of misrendering.")
    func archivo_widthAxisOutOfRange_clamps() throws {
        let narrowest = try #require(PixelBuffer(Self.digitsImage(weight: 700, width: 62, scale: 2)))
        let widest = try #require(PixelBuffer(Self.digitsImage(weight: 700, width: 125, scale: 2)))
        #expect(try PixelBuffer(Self.digitsImage(weight: 700, width: 10, scale: 2)) == narrowest)
        #expect(try PixelBuffer(Self.digitsImage(weight: 700, width: 400, scale: 2)) == widest)
    }

    @Test("wght renders: 100 < 300 < 500 < 700 < 900 lay down strictly more ink.")
    func archivo_weightAxis_addsInk() throws {
        let ink = try [100, 300, 500, 700, 900].map { weight in
            let text = Text(Self.digits).font(LedgerFont.archivo(size: 30, weight: CGFloat(weight), width: 100))
            return try Probe.inkCount(#require(Probe.inked(text, scale: 2)))
        }
        #expect(zip(ink, ink.dropFirst()).allSatisfy { $0 < $1 }, "ink \(ink)")
    }

    @Test("wght outside the font's 100…900 clamps to the axis ends.")
    func archivo_weightAxisOutOfRange_clamps() throws {
        let lightest = try #require(PixelBuffer(Self.digitsImage(weight: 100, width: 100, scale: 2)))
        let heaviest = try #require(PixelBuffer(Self.digitsImage(weight: 900, width: 100, scale: 2)))
        #expect(try PixelBuffer(Self.digitsImage(weight: 1, width: 100, scale: 2)) == lightest)
        #expect(try PixelBuffer(Self.digitsImage(weight: 2000, width: 100, scale: 2)) == heaviest)
    }

    @Test(
        "LedgerFont.archivo draws the font file's own glyphs at the requested axes, pixel for pixel.",
        arguments: [(CGFloat(700), CGFloat(88)), (300, 112), (500, 100), (600, 98)]
    )
    func archivo_anyAxes_matchesFileReference(weight: CGFloat, width: CGFloat) throws {
        _ = FontRegistration.registerIfNeeded()
        let reference = try #require(ArchivoFile.swiftUIFont(size: 30, weight: weight, width: width))
        let sample = "Ledger 185 × 5"
        let actual = try #require(Probe.buffer(Text(sample).font(LedgerFont.archivo(
            size: 30,
            weight: weight,
            width: width
        ))))
        let expected = try #require(Probe.buffer(Text(sample).font(reference)))
        #expect(actual == expected, "wght \(weight) wdth \(width) differs from Archivo read from the file")
    }
}
