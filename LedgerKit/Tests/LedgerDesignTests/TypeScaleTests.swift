@testable import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

extension RenderingSuites {
    /// Type roles against the v2 prototype's CSS (docs/product-spec.md §8.5), and the behaviour
    /// `.ledgerFont(_:)` adds on top of the bare font.
    @Suite("TypeScale", .tags(.design))
    struct TypeScaleTests {
        static let expected: [Row] = [
            Row(.display, 38, 600, 98, -0.035, false, false), // onboarding title
            Row(.title, 32, 600, 98, -0.035, false, false), // screen title "Upper A"
            Row(.heading, 27, 600, 98, -0.032, false, false), // exercise name
            Row(.subheading, 21, 600, 98, -0.03, false, false), // sheet title "Swap exercise"
            Row(.body, 15, 500, 100, 0, false, false), // row title
            Row(.bodyLight, 13.5, 300, 100, 0, false, false), // body copy
            Row(.label, 12.5, 300, 100, 0, false, false), // row meta, stat caption
            Row(.caption, 12, 400, 100, 0, false, false), // date line, "Week 3 of 8"
            Row(.button, 16, 700, 100, -0.005, false, false), // "Start workout", bold for 3:1 on the accent
            Row(.eyebrow, 10, 500, 100, 0.18, false, true), // "UP NEXT"
            Row(.numeralXL, 34, 700, 88, -0.03, true, false), // Today stats
            Row(.numeralL, 30, 700, 88, -0.03, true, false), // stat tiles
            Row(.numeralM, 24, 700, 90, -0.025, true, false), // set weight / reps
            Row(.numeralS, 15, 700, 90, 0, true, false), // PR values
            Row(.watchNumeral, 64 / 1.5, 700, 92, -0.035, true, false), // set-ready weight
            Row(.watchCountdown, 52 / 1.5, 700, 92, -0.035, true, false), // rest countdown
            Row(.watchStat, 30 / 1.5, 700, 92, -0.03, true, false), // summary stats
            Row(.watchTitle, 20 / 1.5, 600, 100, 0, false, false), // exercise name
            Row(.watchButton, 21 / 1.5, 700, 100, -0.01, false, false), // "Done set", bold as above
            Row(.watchLabel, 17 / 1.5, 700, 100, 0.1, false, true), // "RESTING"
            Row(.watchCaption, 17 / 1.5, 600, 100, 0.07, false, true) // "ELAPSED"
        ]

        @Test("Every role has a spec, and each matches the prototype")
        func roles_specs_matchPrototype() {
            #expect(Self.expected.map(\.role) == LedgerFont.Role.allCases)
            for row in Self.expected {
                let spec = row.role.spec
                #expect(abs(spec.size - row.size) < 0.001, "\(row.role) size")
                #expect(spec.weight == row.weight && spec.width == row.width, "\(row.role) axes")
                #expect(spec.tracking == row.tracking, "\(row.role) tracking")
                #expect(spec.isTabular == row.isTabular && spec.isUppercase == row.isUppercase, "\(row.role) flags")
            }
        }

        @Test("No watch role is smaller than 11 pt (spec §4.1: the smallest label is 17 px ÷ 1.5)")
        func watchRoles_size_atLeastElevenPoints() {
            for role in LedgerFont.Role.allCases where role.rawValue.hasPrefix("watch") {
                #expect(role.spec.size >= 11, "\(role) is \(role.spec.size) pt")
            }
        }

        @Test(
            "Dynamic Type scales the role size on this platform",
            arguments: [LedgerFont.Role.body, .numeralM, .watchTitle]
        )
        func ledgerFont_dynamicTypeSizes_scaleAroundReference(_ role: LedgerFont.Role) throws {
            let text = Text("Bench press 185 × 5").ledgerFont(role)
            let reference = try #require(RenderedImage.render(text))
            let accessibility = try #require(RenderedImage.render(text, dynamicTypeSize: .accessibility3))
            let small = try #require(RenderedImage.render(text, dynamicTypeSize: .xSmall))
            // watchOS grows accessibility sizes far less than iOS (title3 +18 % against +115 %).
            #expect(
                Double(accessibility.width) > Double(reference.width) * 1.1,
                "\(reference.width) → \(accessibility.width)"
            )
            #expect(small.width < reference.width, "\(reference.width) → \(small.width)")
        }

        @Test("At the reference text size a role renders at exactly its design size")
        func ledgerFont_referenceSize_matchesDesignSize() throws {
            let scaled = try #require(RenderedImage.render(Text("185 × 5").ledgerFont(.numeralM)))
            let fixed = try #require(RenderedImage.render(Text("185 × 5").font(LedgerFont.font(
                .numeralM,
                dynamicTypeSize: SnapshotConfig.referenceDynamicTypeSize
            )).tracking(-0.6)))
            #expect(scaled.width == fixed.width)
            #expect(scaled.height == 24) // line height 1 × 24 pt at 1×
        }

        @Test("scaledSize is the design size at the platform's reference text size and grows with it")
        func scaledSize_referenceTextSize_isDesignSize() {
            for role in LedgerFont.Role.allCases {
                let reference = LedgerFont.scaledSize(role, dynamicTypeSize: SnapshotConfig.referenceDynamicTypeSize)
                let sizes = DynamicTypeSize.allCases.map { LedgerFont.scaledSize(role, dynamicTypeSize: $0) }
                #expect(abs(reference - max(role.spec.size, role.spec.minimumSize)) < 0.01, "\(role): \(reference)")
                #expect(zip(sizes, sizes.dropFirst()).allSatisfy { $0 <= $1 }, "\(role): \(sizes)")
            }
        }

        @Test("Watch roles never scale below 11 pt, even at the smallest text size")
        func watchLabel_smallestTextSize_staysAtElevenPoints() throws {
            let label = try #require(RenderedImage.render(
                Text("RESTING").ledgerFont(.watchLabel),
                dynamicTypeSize: .xSmall
            ))
            #expect(label.height == 11) // line height 1 × the 11 pt floor at 1×
            #expect(LedgerFont.Role.allCases.filter { $0.spec.minimumSize == 11 }.count == 7)
            let explicit = try #require(RenderedImage.render(
                Text("RESTING").font(LedgerFont.font(.watchLabel, size: 8)).lineHeight(.multiple(factor: 1))
            ))
            #expect(explicit.height == label.height, "an explicit 8 pt is floored to 11 pt too")
        }

        @Test("Uppercase roles render lower-case copy in capitals")
        func eyebrow_lowercaseCopy_rendersAsCapitals() throws {
            let lower = try #require(RenderedImage.render(Text("Up next").ledgerFont(.eyebrow))
                .flatMap(PixelBuffer.init))
            let upper = try #require(RenderedImage.render(Text("UP NEXT").ledgerFont(.eyebrow))
                .flatMap(PixelBuffer.init))
            #expect(lower == upper)
        }

        @Test("Letter spacing is applied in em of the scaled size")
        func eyebrow_tracking_widensText() throws {
            let tracked = try #require(RenderedImage.render(Text("UP NEXT").ledgerFont(.eyebrow)))
            let plain = try #require(RenderedImage.render(Text("UP NEXT").font(LedgerFont.font(
                .eyebrow,
                dynamicTypeSize: SnapshotConfig.referenceDynamicTypeSize
            ))))
            // .18 em × 10 pt × 7 glyphs ≈ 12.6 pt wider at 1×.
            #expect(tracked.width - plain.width >= 11, "\(plain.width) → \(tracked.width)")
        }
    }
}

extension RenderingSuites.TypeScaleTests {
    /// Copied from the prototypes' `font:` declarations; watch sizes are CSS px ÷ 1.5 (spec §4.1).
    struct Row {
        let role: LedgerFont.Role
        let size, weight, width, tracking: CGFloat
        let isTabular, isUppercase: Bool

        init(
            _ role: LedgerFont.Role,
            _ size: CGFloat,
            _ weight: CGFloat,
            _ width: CGFloat,
            _ tracking: CGFloat,
            _ isTabular: Bool,
            _ isUppercase: Bool
        ) {
            (self.role, self.size, self.weight, self.width, self.tracking) = (role, size, weight, width, tracking)
            (self.isTabular, self.isUppercase) = (isTabular, isUppercase)
        }
    }
}
