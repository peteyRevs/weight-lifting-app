import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

nonisolated enum RoleSets {
    /// Every role that sets numbers (spec §8.5: numbers use `tabular-nums`).
    static let numerals: [LedgerFont.Role] = [
        .numeralXL, .numeralL, .numeralM, .numeralS, .watchNumeral, .watchCountdown, .watchStat
    ]
    /// Roles the spec sets in capitals (v2 labels, watch labels and captions).
    static let uppercase: [LedgerFont.Role] = [.eyebrow, .watchLabel, .watchCaption]
    /// Rows of the expectation table whose size and weight the spec pins to one value.
    static let pinned: [RoleExpectation] = RoleExpectation.all.filter { $0.pinnedSize != nil && $0.pinnedWeight != nil }
}

nonisolated extension RoleExpectation {
    var pinnedSize: CGFloat? {
        size.upperBound - size.lowerBound < 0.03 ? (size.lowerBound + size.upperBound) / 2 : nil
    }

    var pinnedWeight: CGFloat? {
        weight.upperBound - weight.lowerBound < 0.01 ? (weight.lowerBound + weight.upperBound) / 2 : nil
    }
}

extension RenderingSuites {
    @Suite("LedgerFont rendering (adversarial)", .tags(.design))
    struct LedgerFontRenderingAdversarialTests {
        static let sample = "Hg0123456789"

        static func size(_ view: some View, scale: CGFloat = 4, type: DynamicTypeSize = .large) -> CGSize? {
            Probe.image(view, scale: scale, dynamicTypeSize: type).map { CGSize(width: $0.width, height: $0.height) }
        }

        static func capHeight(_ view: some View, type: DynamicTypeSize) -> Int? {
            Probe.inked(view, scale: 2, dynamicTypeSize: type).flatMap(Probe.inkHeight)
        }

        @Test("The tabular probe is sensitive: Archivo's default figures are proportional.")
        func archivo_defaultFigures_areProportional() throws {
            let font = LedgerFont.archivo(size: 30, weight: 700, width: 88)
            let ones = try #require(Self.size(Text("1111111111").font(font)))
            let zeros = try #require(Self.size(Text("0000000000").font(font)))
            #expect(ones.width != zeros.width, "without tnum, 1 and 0 must differ in advance")
        }

        @Test(
            "Numeral roles set tabular figures through .ledgerFont: ten 1s are as wide as ten 0s.",
            arguments: RoleSets.numerals
        )
        func numeralRole_ledgerFont_isTabular(role: LedgerFont.Role) throws {
            let ones = try #require(Self.size(Text("1111111111").ledgerFont(role)))
            let zeros = try #require(Self.size(Text("0000000000").ledgerFont(role)))
            #expect(ones.width == zeros.width, "\(role): 1s \(ones.width) px, 0s \(zeros.width) px")
        }

        @Test(
            "The bare LedgerFont.font(role, dynamicTypeSize:) is tabular for numeral roles too (brief public surface).",
            arguments: RoleSets.numerals
        )
        func numeralRole_bareFont_isTabular(role: LedgerFont.Role) throws {
            let ones = try #require(Self.size(Text("1111111111").font(LedgerFont.font(role, dynamicTypeSize: .large))))
            let zeros = try #require(Self.size(Text("0000000000").font(LedgerFont.font(role, dynamicTypeSize: .large))))
            #expect(ones.width == zeros.width, "\(role): 1s \(ones.width) px, 0s \(zeros.width) px")
        }

        @Test("Uppercase roles render lower-case input in capitals.", arguments: RoleSets.uppercase)
        func uppercaseRole_lowercaseInput_rendersCapitals(role: LedgerFont.Role) throws {
            let lower = try #require(Probe.buffer(Text("up next 3").ledgerFont(role), scale: 2))
            let upper = try #require(Probe.buffer(Text("UP NEXT 3").ledgerFont(role), scale: 2))
            #expect(lower == upper)
        }

        @Test(
            "A role's bare font is Archivo at the spec's size, wght, wdth and figures (rendered layout).",
            arguments: RoleSets.pinned
        )
        func pinnedRole_bareFont_matchesArchivoReference(expected: RoleExpectation) throws {
            let size = try #require(expected.pinnedSize)
            let weight = try #require(expected.pinnedWeight)
            _ = FontRegistration.registerIfNeeded()
            let reference = try #require(
                ArchivoFile.swiftUIFont(size: size, weight: weight, width: expected.width, tabular: expected.tabular),
                "Archivo not found next to the test bundle"
            )
            // F06 fix round: the bare font now takes the text size; the design size is exact at the
            // platform's reference size (.large on iOS, .xLarge on watchOS).
            let font = LedgerFont.font(expected.role, dynamicTypeSize: SnapshotConfig.referenceDynamicTypeSize)
            let actual = try #require(Self.size(Text(Self.sample).font(font), scale: 2))
            let wanted = try #require(Self.size(Text(Self.sample).font(reference), scale: 2))
            #expect(
                abs(actual.width - wanted.width) <= 1,
                "\(expected.role) width \(actual.width), spec \(wanted.width)"
            )
            #expect(
                abs(actual.height - wanted.height) <= 1,
                "\(expected.role) height \(actual.height), spec \(wanted.height)"
            )
        }

        @Test(
            ".ledgerFont scales every role with Dynamic Type: never shrinks as size grows; AX3 > large.",
            arguments: LedgerFont.Role.allCases
        )
        func role_ledgerFont_scalesWithDynamicType(role: LedgerFont.Role) throws {
            let heights = try DynamicTypeSize.allCases.map { type in
                try #require(Self.capHeight(Text("H").ledgerFont(role), type: type), "\(role) at \(type)")
            }
            let pairs = zip(DynamicTypeSize.allCases, heights)
            #expect(zip(heights, heights.dropFirst()).allSatisfy { $0 <= $1 }, "\(role): \(Array(pairs))")
            let large = try #require(Self.capHeight(Text("H").ledgerFont(role), type: .large))
            let accessibility = try #require(Self.capHeight(Text("H").ledgerFont(role), type: .accessibility3))
            #expect(accessibility > large + 1, "\(role): large \(large) px, AX3 \(accessibility) px")
        }

        @Test(
            "LedgerFont.font(role, dynamicTypeSize:) is Dynamic Type–scaled, as the brief's public surface promises.",
            arguments: [LedgerFont.Role.body, .numeralL]
        )
        func bareFont_accessibilitySize_scalesUp(role: LedgerFont.Role) throws {
            // F06 fix round: a Font built from a Core Text instance cannot read the environment, so the
            // text size is passed explicitly (implementation notes, "Dynamic Type").
            let large = try #require(Self.capHeight(
                Text("H").font(LedgerFont.font(role, dynamicTypeSize: .large)), type: .large
            ))
            let accessibility = try #require(Self.capHeight(
                Text("H").font(LedgerFont.font(role, dynamicTypeSize: .accessibility3)), type: .accessibility3
            ))
            #expect(accessibility > large + 1, "\(role): large \(large) px, AX3 \(accessibility) px")
        }

        @Test(
            "Bold Text (legibility weight) makes .ledgerFont text heavier, as the HIG asks of custom fonts.",
            arguments: [LedgerFont.Role.body, .label, .numeralL]
        )
        func role_boldTextSetting_addsWeight(role: LedgerFont.Role) throws {
            let text = Text("Upper A 185")
            let regular = try #require(Probe.inked(
                text.ledgerFont(role).environment(\.legibilityWeight, .regular),
                scale: 2
            ))
            let bold = try #require(Probe.inked(text.ledgerFont(role).environment(\.legibilityWeight, .bold), scale: 2))
            let (regularInk, boldInk) = (Probe.inkCount(regular), Probe.inkCount(bold))
            #expect(
                Double(boldInk) > Double(regularInk) * 1.05,
                "\(role): ink \(regularInk) → \(boldInk) with Bold Text"
            )
        }
    }
}
