import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

extension RenderingSuites {
    /// Round 2: where `.ledgerFont` puts a single line inside its own frame.
    ///
    /// F06 fix round 3 (Pete, 2026-09-29, decision 1): text uses SwiftUI's native line height only.
    /// Round 2 pinned the CSS half-leading position (`L/2 + (ascent − descent)/2` em below the top of
    /// an `L` em line box); that requirement was dropped, so these tests pin the native contract
    /// instead: a lone line lands exactly where `lineHeight(.multiple(factor:))` puts it with the
    /// role's own font, in a frame `L` × size tall, with its capitals inside the frame.
    @Suite("LedgerFont line box (adversarial, round 2)", .tags(.design))
    struct LedgerFontLineBoxAdversarialTests {
        static let margin: CGFloat = 60
        static let scale: CGFloat = 2

        /// The role's size at the platform's reference text size.
        static func size(_ role: LedgerFont.Role) -> CGFloat {
            LedgerFont.scaledSize(role, dynamicTypeSize: SnapshotConfig.referenceDynamicTypeSize)
        }

        /// The same "H" set with SwiftUI's own modifiers only: the role's font and its line height.
        static func native(_ role: LedgerFont.Role) -> some View {
            Text("H").font(LedgerFont.font(role, size: size(role))).lineHeight(.multiple(factor: role.spec.lineHeight))
        }

        /// A lone capital "H" in `text` at the platform's reference text size.
        static func placement(_ text: some View) throws -> Placement {
            let type = SnapshotConfig.referenceDynamicTypeSize
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
            "A lone line sits where SwiftUI's own line height puts it, in a frame of line height × size.",
            arguments: LedgerFont.Role.allCases
        )
        func singleLine_baseline_matchesNativeLineHeight(role: LedgerFont.Role) throws {
            let measured = try Self.placement(Text("H").ledgerFont(role))
            let native = try Self.placement(Self.native(role))
            let lineBox = role.spec.lineHeight * Self.size(role)
            #expect(
                abs(measured.baseline - native.baseline) <= 1 / Self.scale,
                "\(role): baseline \(measured.baseline) pt below the frame top, native \(native.baseline) pt"
            )
            #expect(abs(measured.frame - lineBox) <= 1, "\(role): frame \(measured.frame) pt, line box \(lineBox) pt")
        }

        @Test(
            "Capitals start inside their own frame, and the baseline is inside it for every line height ≥ 1.",
            arguments: LedgerFont.Role.allCases
        )
        func singleLine_capitalInk_staysInsideFrame(role: LedgerFont.Role) throws {
            let measured = try Self.placement(Text("H").ledgerFont(role))
            let slack = 1 / Self.scale
            #expect(measured.capTop >= -slack, "\(role): cap line \(-measured.capTop) pt above the frame")
            // Decision 1: SwiftUI puts a lone baseline 1 em below the frame top, so the one role whose line
            // height is under 1 (watchNumeral, 0.86) draws its figures up to (1 − L) em below its frame.
            // Components leave room for that with spacing tokens.
            if role.spec.lineHeight >= 1 {
                #expect(
                    measured.baseline <= measured.frame + slack,
                    "\(role): baseline \(measured.baseline - measured.frame) pt below its \(measured.frame) pt frame"
                )
            }
        }
    }
}

extension RenderingSuites.LedgerFontLineBoxAdversarialTests {
    /// Where a lone capital "H" lands, in points measured from the top of its own frame.
    struct Placement {
        let frame: CGFloat
        let capTop: CGFloat
        let baseline: CGFloat
    }
}
