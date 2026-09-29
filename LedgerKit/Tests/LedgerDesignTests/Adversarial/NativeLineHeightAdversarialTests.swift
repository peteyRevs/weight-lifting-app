import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

/// Round 3's measuring helpers (ink runs, frame, colour tests).
private typealias Lines = RenderingSuites.LedgerFontLinePlacementAdversarialTests

extension RenderingSuites {
    /// Round 4 (close-out after the re-plan): the native line-height contract that fix round 3
    /// retargeted the line-placement suites to (Pete, 2026-09-29, decision 1), pushed past the cases
    /// those suites pin. Every role as the container and as a child (pixel for pixel), every role's
    /// first and last baselines against a partner, three hard-broken and three soft-wrapped lines and
    /// a background at the smallest and largest text sizes.
    @Suite("LedgerFont native line height (adversarial, round 4)", .tags(.design))
    struct NativeLineHeightAdversarialTests {
        static let scale: CGFloat = 2
        static let margin: CGFloat = 60
        /// Lower-case letters and figures, two lines: case, tracking, tabular figures and pitch all show.
        static let sample = "Hg 185\nxy 47"
        nonisolated static let extremes: [DynamicTypeSize] = [.xSmall, .accessibility5]
        nonisolated static let alignmentSizes: [DynamicTypeSize] = [
            SnapshotConfig.referenceDynamicTypeSize, .accessibility5
        ]

        /// `view` white on black with a margin wide enough for ink drawn outside its frame.
        static func pixels(
            _ view: some View,
            _ type: DynamicTypeSize = SnapshotConfig.referenceDynamicTypeSize
        ) throws -> PixelBuffer {
            try #require(Probe.buffer(
                view.foregroundStyle(Color.white).padding(margin).background(Color.black),
                scale: scale,
                dynamicTypeSize: type
            ))
        }

        // MARK: - Nested roles

        @Test(
            "A role on a container, or applied again on top, never changes a child's own role, pixel for pixel.",
            arguments: LedgerFont.Role.allCases
        )
        func nestedRoles_everyOuterRole_leavesInnerRoleUntouched(outer: LedgerFont.Role) throws {
            for inner in [LedgerFont.Role.bodyLight, .watchNumeral] {
                let alone = try Self.pixels(Text(Self.sample).ledgerFont(inner))
                let contained = try Self
                    .pixels(VStack(spacing: 0) { Text(Self.sample).ledgerFont(inner) }.ledgerFont(outer))
                let doubled = try Self.pixels(Text(Self.sample).ledgerFont(inner).ledgerFont(outer))
                #expect(contained == alone, "\(inner) inside a \(outer) container is drawn differently from \(inner)")
                #expect(doubled == alone, "\(inner) then \(outer) on one Text is drawn differently from \(inner)")
            }
        }

        @Test(
            "A role set on a container reaches a child without a role exactly as if it were set on the child.",
            arguments: LedgerFont.Role.allCases
        )
        func containerRole_childWithoutRole_matchesDirectRole(role: LedgerFont.Role) throws {
            let direct = try Self.pixels(Text(Self.sample).ledgerFont(role))
            let inherited = try Self.pixels(VStack(spacing: 0) { Text(Self.sample) }.ledgerFont(role))
            #expect(inherited == direct, "\(role) on a container is drawn differently from \(role) on the Text")
        }

        // MARK: - Content that is not text, at the extremes

        @Test(
            "At xSmall and AX5 a background under a symbol and two lines of text stays on the view's frame.",
            arguments: LedgerFont.Role.allCases, extremes
        )
        func background_extremeTextSizes_staysOnFrame(role: LedgerFont.Role, type: DynamicTypeSize) throws {
            let label = HStack(spacing: LedgerSpacing.s) {
                Image(systemName: "circle.fill")
                Text("H\nH")
            }
            .padding(LedgerSpacing.s)
            .background(Color.red)
            .ledgerFont(role)
            let frame = try #require(Probe.image(label, scale: Self.scale, dynamicTypeSize: type))
            let fill = try #require(Lines.runs(Self.pixels(label, type), where: Lines.isRed).first)
            let top = (CGFloat(fill.lowerBound) - Self.margin * Self.scale) / Self.scale
            let bottom = (CGFloat(fill.upperBound + 1) - Self.margin * Self.scale) / Self.scale
            let height = CGFloat(frame.height) / Self.scale
            #expect(
                abs(top) <= Lines.slack && abs(bottom - height) <= Lines.slack,
                "\(role) at \(type): background spans \(top)…\(bottom) pt, the view's frame 0…\(height) pt"
            )
        }

        // MARK: - Several lines, at the extremes

        @Test(
            "At xSmall and AX5, three hard-broken and three soft-wrapped lines are line height × size apart (± 1 pt).",
            arguments: LedgerFont.Role.allCases, extremes
        )
        func threeLines_extremeTextSizes_pitchIsLineHeightTimesSize(
            role: LedgerFont.Role,
            type: DynamicTypeSize
        ) throws {
            let pitch = role.spec.lineHeight * LedgerFont.scaledSize(role, dynamicTypeSize: type)
            let word = try #require(Probe.image(Text("HHH").ledgerFont(role), dynamicTypeSize: type))
            let hard = try Lines.measure(Text("HHH\nHHH\nHHH").ledgerFont(role), dynamicTypeSize: type)
            let soft = try Lines.measure(
                Text("HHH HHH HHH").ledgerFont(role).frame(width: CGFloat(word.width) * 1.3, alignment: .leading),
                dynamicTypeSize: type
            )
            for (name, block) in [("hard", hard), ("soft", soft)] {
                try #require(block.ink.count == 3, "\(role) at \(type), \(name): \(block.ink.count) lines, not 3")
                let baselines = block.ink.map(\.upperBound)
                for (upper, lower) in zip(baselines, baselines.dropFirst()) {
                    #expect(
                        abs(lower - upper - pitch) <= 1,
                        "\(role) at \(type), \(name): baselines \(lower - upper) pt apart, L × size \(pitch) pt"
                    )
                }
                #expect(
                    abs(block.frame - 3 * pitch) <= 1,
                    "\(role) at \(type), \(name): frame \(block.frame) pt, three line boxes \(3 * pitch) pt"
                )
            }
        }

        // MARK: - First and last baselines across roles

        @Test(
            "Every role's first and last baselines (two lines) align with a one-line partner, at reference and AX5.",
            arguments: LedgerFont.Role.allCases, alignmentSizes
        )
        func baselines_everyRole_alignWithPartner(role: LedgerFont.Role, type: DynamicTypeSize) throws {
            let partner: LedgerFont.Role = role.rawValue.hasPrefix("watch") ? .watchLabel : .eyebrow
            for first in [true, false] {
                let row = HStack(alignment: first ? .firstTextBaseline : .lastTextBaseline, spacing: 24) {
                    Text("H\nH").ledgerFont(role).foregroundStyle(Color.red)
                    Text("H").ledgerFont(partner).foregroundStyle(Color.green)
                }
                .padding(Self.margin)
                .background(Color.black)
                let buffer = try #require(Probe.buffer(row, scale: Self.scale, dynamicTypeSize: type))
                let red = Lines.runs(buffer, where: Lines.isRed)
                let line = try #require(first ? red.first : red.last, "\(role) at \(type): no red ink")
                let green = try #require(Lines.runs(buffer, where: Lines.isGreen).last, "\(partner): no green ink")
                #expect(
                    abs(line.upperBound - green.upperBound) <= 1,
                    """
                    \(first ? "first" : "last") baseline, \(role) at \(type): row \(line.upperBound), \
                    \(partner) row \(green.upperBound) (px at \(Self.scale)×)
                    """
                )
            }
        }
    }
}
