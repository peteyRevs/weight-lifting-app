import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

extension RenderingSuites {
    /// Round 3: `.ledgerFont`'s line placement beyond a lone line at the reference text size — every
    /// text size, several lines, baseline alignment between roles, a role set on a container, and
    /// content that is not text.
    ///
    /// F06 fix round 3 (Pete, 2026-09-29, decision 1): text uses SwiftUI's native line height only, so
    /// the CSS half-leading positions round 3 pinned are retired. The contract pinned here instead:
    /// `.ledgerFont` moves nothing inside the view (a background stays on the frame, nested roles do
    /// not add up); a lone line sits where SwiftUI's own line height puts it at every text size;
    /// lines are line height × size apart; and first-baseline alignment across roles holds.
    @Suite("LedgerFont line placement (adversarial, round 3)", .tags(.design))
    struct LedgerFontLinePlacementAdversarialTests {
        static let margin: CGFloat = 60
        static let scale: CGFloat = 2
        static let slack: CGFloat = 1 / scale

        // MARK: - Every text size

        static let textSizes: [DynamicTypeSize] = [.xSmall, .xxxLarge, .accessibility3, .accessibility5]

        @Test(
            "At every text size, a lone line sits where SwiftUI's own line height puts it, capitals inside the frame.",
            arguments: LedgerFont.Role.allCases
        )
        func singleLine_everyTextSize_matchesNativeLineHeight(role: LedgerFont.Role) throws {
            for type in Self.textSizes {
                let size = LedgerFont.scaledSize(role, dynamicTypeSize: type)
                let measured = try Self.measure(Text("H").ledgerFont(role), dynamicTypeSize: type)
                let ink = try #require(measured.ink.first, "\(role) at \(type): no ink")
                let native = try Self.measure(Self.native(role, size: size), dynamicTypeSize: type)
                let expected = try #require(native.ink.first, "\(role) at \(type): no native ink").upperBound
                #expect(
                    abs(ink.upperBound - expected) <= Self.slack,
                    "\(role) at \(type) (\(size) pt): baseline \(ink.upperBound) pt, native \(expected) pt"
                )
                #expect(
                    ink.lowerBound >= -Self.slack,
                    "\(role) at \(type): cap line \(-ink.lowerBound) pt above the frame"
                )
                #expect(
                    abs(measured.frame - role.spec.lineHeight * size) <= 1,
                    "\(role) at \(type): frame \(measured.frame) pt, line box \(role.spec.lineHeight * size) pt"
                )
            }
        }

        // MARK: - Several lines

        @Test(
            "In a two-line block the baselines are line height × size apart, in a frame twice that.",
            arguments: LedgerFont.Role.allCases
        )
        func twoLines_baselinePitch_isLineHeightTimesSize(role: LedgerFont.Role) throws {
            let size = LedgerFont.scaledSize(role, dynamicTypeSize: SnapshotConfig.referenceDynamicTypeSize)
            let pitch = role.spec.lineHeight * size
            let measured = try Self.measure(Text("H\nH").ledgerFont(role))
            try #require(measured.ink.count == 2, "\(role): \(measured.ink.count) ink runs for two lines")
            let measuredPitch = measured.ink[1].upperBound - measured.ink[0].upperBound
            #expect(
                abs(measuredPitch - pitch) <= Self.tolerance(size),
                "\(role): baselines \(measuredPitch) pt apart, line height × size \(pitch) pt"
            )
            #expect(
                abs(measured.frame - 2 * pitch) <= 1,
                "\(role): two-line frame \(measured.frame) pt, two line boxes \(2 * pitch) pt"
            )
        }

        // MARK: - Baseline alignment between roles

        nonisolated static let alignedPairs: [(LedgerFont.Role, LedgerFont.Role)] = [
            (.numeralXL, .eyebrow), (.watchNumeral, .watchLabel), (.display, .bodyLight), (.numeralL, .caption)
        ]

        @Test(
            "HStack(alignment: .firstTextBaseline) puts two roles' baselines on one line (a stat and its unit).",
            arguments: alignedPairs
        )
        func firstTextBaseline_twoRoles_shareOneBaseline(large: LedgerFont.Role, small: LedgerFont.Role) throws {
            let row = HStack(alignment: .firstTextBaseline, spacing: 24) {
                Text("H").ledgerFont(large).foregroundStyle(Color.red)
                Text("H").ledgerFont(small).foregroundStyle(Color.green)
            }
            .padding(Self.margin)
            .background(Color.black)
            let buffer = try #require(Probe.buffer(
                row,
                scale: Self.scale,
                dynamicTypeSize: SnapshotConfig.referenceDynamicTypeSize
            ))
            let red = try #require(Self.runs(buffer, where: Self.isRed).last)
            let green = try #require(Self.runs(buffer, where: Self.isGreen).last)
            #expect(
                abs(red.upperBound - green.upperBound) <= 1,
                "\(large) baseline at row \(red.upperBound), \(small) at row \(green.upperBound) (px at \(Self.scale)×)"
            )
        }

        // MARK: - A role set on a container

        nonisolated static let nestings: [(LedgerFont.Role, LedgerFont.Role)] = [
            (.display, .numeralL), (.watchNumeral, .caption), (.eyebrow, .numeralXL), (.bodyLight, .title)
        ]

        @Test(
            "A role set on a container does not move a child that sets its own role: nested roles never add up.",
            arguments: nestings
        )
        func nestedRoles_innerRole_placesItsOwnLine(outer: LedgerFont.Role, inner: LedgerFont.Role) throws {
            let alone = try Self.measure(Text("H").ledgerFont(inner))
            let nested = try Self.measure(VStack(spacing: 0) { Text("H").ledgerFont(inner) }.ledgerFont(outer))
            let aloneInk = try #require(alone.ink.first)
            let nestedInk = try #require(nested.ink.first)
            #expect(nested.frame == alone.frame, "frame \(nested.frame) pt nested, \(alone.frame) pt alone")
            #expect(
                abs(nestedInk.upperBound - aloneInk.upperBound) <= Self.slack,
                """
                \(inner) inside \(outer): baseline \(nestedInk.upperBound) pt below the frame top, \
                alone \(aloneInk.upperBound) pt; cap line \(nestedInk.lowerBound) pt
                """
            )
        }

        // MARK: - Content that is not text

        @Test(
            "A background under the text stays on the view's frame: line placement moves glyphs, not boxes.",
            arguments: LedgerFont.Role.allCases
        )
        func background_underText_staysOnFrame(role: LedgerFont.Role) throws {
            let label = Text("H").padding(LedgerSpacing.s).background(Color.red).ledgerFont(role)
            let type = SnapshotConfig.referenceDynamicTypeSize
            let frame = try #require(Probe.image(label, scale: Self.scale, dynamicTypeSize: type))
            let padded = label.foregroundStyle(Color.white).padding(Self.margin).background(Color.black)
            let buffer = try #require(Probe.buffer(padded, scale: Self.scale, dynamicTypeSize: type))
            let fill = try #require(Self.runs(buffer, where: Self.isRed).first)
            let top = (CGFloat(fill.lowerBound) - Self.margin * Self.scale) / Self.scale
            let bottom = (CGFloat(fill.upperBound + 1) - Self.margin * Self.scale) / Self.scale
            let height = CGFloat(frame.height) / Self.scale
            #expect(
                abs(top) <= Self.slack && abs(bottom - height) <= Self.slack,
                "\(role): background spans \(top)…\(bottom) pt, the view's frame 0…\(height) pt"
            )
        }
    }
}

// MARK: - Measuring

extension RenderingSuites.LedgerFontLinePlacementAdversarialTests {
    /// "H" set with SwiftUI's own modifiers only: the role's font at `size` and its line height.
    static func native(_ role: LedgerFont.Role, size: CGFloat) -> some View {
        Text("H").font(LedgerFont.font(role, size: size)).lineHeight(.multiple(factor: role.spec.lineHeight))
    }

    static func tolerance(_ size: CGFloat) -> CGFloat {
        0.03 * size + slack
    }

    /// Rows of `buffer` holding at least one pixel that satisfies `isInk`, as runs.
    static func runs(_ buffer: PixelBuffer, where isInk: (Pixel) -> Bool) -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        var start: Int?
        for row in 0 ... buffer.height {
            let inked = row < buffer.height && (0 ..< buffer.width)
                .contains { isInk(buffer.pixel(column: $0, row: row)) }
            if inked, start == nil {
                start = row
            } else if !inked, let first = start {
                runs.append(first ... row - 1)
                start = nil
            }
        }
        return runs
    }

    static func isRed(_ pixel: Pixel) -> Bool {
        pixel.red > 160 && pixel.green < 90 && pixel.blue < 90
    }

    static func isGreen(_ pixel: Pixel) -> Bool {
        pixel.green > 160 && pixel.red < 90 && pixel.blue < 90
    }

    /// `view`'s own frame height and its white ink as runs of rows, both in points from the frame top.
    static func measure(
        _ view: some View,
        dynamicTypeSize: DynamicTypeSize = SnapshotConfig.referenceDynamicTypeSize
    ) throws -> (frame: CGFloat, ink: [ClosedRange<CGFloat>]) {
        let frame = try #require(Probe.image(view, scale: scale, dynamicTypeSize: dynamicTypeSize))
        let padded = view.foregroundStyle(Color.white).padding(margin).background(Color.black)
        let buffer = try #require(Probe.buffer(padded, scale: scale, dynamicTypeSize: dynamicTypeSize))
        let top = margin * scale
        let ink = Probe.inkRuns(buffer).map { run in
            (CGFloat(run.lowerBound) - top) / scale ... (CGFloat(run.upperBound + 1) - top) / scale
        }
        return (CGFloat(frame.height) / scale, ink)
    }
}
