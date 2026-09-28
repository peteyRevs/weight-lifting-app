import CoreText
import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

/// Round 2: where `.ledgerFont` puts a single line inside its own frame. The prototypes set every
/// role with CSS `line-height` (spec §8.5: `64px/0.86`, `30px/1`, `15px/1.2`…), and CSS splits the
/// leading evenly above and below the font's content area, so the baseline of a lone line sits
/// `L/2 + (ascent − descent)/2` em below the top of its `L` em line box. Archivo's ascent and
/// descent are read from the font file.
@Suite("LedgerFont line box (adversarial, round 2)", .tags(.design))
struct LedgerFontLineBoxAdversarialTests {
    static let margin: CGFloat = 60
    static let scale: CGFloat = 2

    /// Archivo's ascent and descent in em (hhea, which OS/2 repeats with USE_TYPO_METRICS).
    static func verticalMetrics() throws -> (ascent: CGFloat, descent: CGFloat) {
        let font = try #require(ArchivoFile.font(size: 1000, weight: 400, width: 100), "Archivo file not found")
        return (CTFontGetAscent(font) / 1000, CTFontGetDescent(font) / 1000)
    }

    /// Where a lone capital "H" lands, in points measured from the top of its own frame.
    struct Placement {
        let frame: CGFloat
        let capTop: CGFloat
        let baseline: CGFloat
    }

    /// A lone capital "H" in `role` at the platform's reference text size.
    static func placement(_ role: LedgerFont.Role) throws -> Placement {
        let type = SnapshotConfig.referenceDynamicTypeSize
        let text = Text("H").ledgerFont(role)
        let frame = try #require(Probe.image(text, scale: scale, dynamicTypeSize: type))
        let padded = text.foregroundStyle(Color.white).padding(margin).background(Color.black)
        let buffer = try #require(Probe.buffer(padded, scale: scale, dynamicTypeSize: type))
        let runs = Probe.inkRuns(buffer)
        let first = try #require(runs.first)
        let last = try #require(runs.last)
        let top = margin * scale
        return Placement(
            frame: CGFloat(frame.height) / scale,
            capTop: (CGFloat(first.lowerBound) - top) / scale,
            baseline: (CGFloat(last.upperBound + 1) - top) / scale
        )
    }

    @Test(
        "A lone line's baseline sits where CSS puts it: half the leading above, half below.",
        arguments: LedgerFont.Role.allCases
    )
    func singleLine_baseline_matchesCSSHalfLeading(role: LedgerFont.Role) throws {
        let (ascent, descent) = try Self.verticalMetrics()
        let spec = role.spec
        let measured = try Self.placement(role)
        let expected = spec.size * (spec.lineHeight / 2 + (ascent - descent) / 2)
        let tolerance = 0.03 * spec.size + 1 / Self.scale
        #expect(
            abs(measured.baseline - expected) <= tolerance,
            """
            \(role) \(spec.size) pt / \(spec.lineHeight): baseline \(measured.baseline) pt below the frame top \
            (\(String(format: "%.3f", measured.baseline / spec.size)) em), CSS \(String(format: "%.1f", expected)) pt \
            (\(String(format: "%.3f", expected / spec.size)) em); frame \(measured.frame) pt
            """
        )
    }

    @Test(
        "Capitals and figures stay inside their own frame (CSS keeps them inside for every line height ≥ 0.67).",
        arguments: LedgerFont.Role.allCases
    )
    func singleLine_capitalInk_staysInsideFrame(role: LedgerFont.Role) throws {
        let measured = try Self.placement(role)
        let slack = 1 / Self.scale
        #expect(measured.capTop >= -slack, "\(role): cap line \(-measured.capTop) pt above the frame")
        #expect(
            measured.baseline <= measured.frame + slack,
            "\(role): baseline \(measured.baseline - measured.frame) pt below its \(measured.frame) pt frame"
        )
    }
}
