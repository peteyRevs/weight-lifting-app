import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Testing

extension RenderingSuites {
    /// Round 2: Bold Text (Pete, 2026-09-27: one weight step, +100) and the bold button labels the
    /// 3:1 white-on-accent decision rests on (HIG Accessibility: "All sizes, Bold: 3:1").
    @Suite("Bold Text (adversarial, round 2)", .tags(.design))
    struct BoldTextAdversarialTests {
        static let sample = "Hg 0123456789"

        static func ink(_ font: Font, text: String = sample) throws -> Int {
            try Probe.inkCount(#require(Probe.inked(Text(text).font(font), scale: 2)))
        }

        @Test(
            "Bold Text is one 100 step and never pushes a role past Archivo's wght 900.",
            arguments: LedgerFont.Role.allCases
        )
        func boldText_everyRole_staysOnTheAxis(role: LedgerFont.Role) {
            #expect(LedgerFont.boldTextWeightStep == 100)
            #expect(role.spec.weight + LedgerFont.boldTextWeightStep <= 900, "\(role) would clamp and not get bolder")
        }

        @Test(
            "Every role, the 700 numerals included, lays down visibly more ink with Bold Text.",
            arguments: LedgerFont.Role.allCases
        )
        func boldText_everyRole_isHeavier(role: LedgerFont.Role) throws {
            let type = SnapshotConfig.referenceDynamicTypeSize
            let regular = try Self.ink(LedgerFont.font(role, dynamicTypeSize: type, legibilityWeight: .regular))
            let bold = try Self.ink(LedgerFont.font(role, dynamicTypeSize: type, legibilityWeight: .bold))
            #expect(Double(bold) > Double(regular) * 1.03, "\(role): ink \(regular) → \(bold)")
            let explicit = try Self.ink(LedgerFont.font(role, size: role.spec.size, legibilityWeight: .bold))
            #expect(
                explicit == bold,
                "\(role): the explicit-size path disagrees with the text-size path under Bold Text"
            )
        }

        @Test(
            "Bold Text draws the role at exactly wght + 100 (Archivo read from the file).",
            arguments: RoleSets.pinned
        )
        func boldText_pinnedRole_isOneStepHeavier(expected: RoleExpectation) throws {
            let size = try #require(expected.pinnedSize)
            let weight = try #require(expected.pinnedWeight)
            _ = FontRegistration.registerIfNeeded()
            let bold = LedgerFont.font(
                expected.role, dynamicTypeSize: SnapshotConfig.referenceDynamicTypeSize, legibilityWeight: .bold
            )
            let actual = try Self.ink(bold)
            let oneStep = try Self.ink(#require(ArchivoFile.swiftUIFont(
                size: size, weight: weight + 100, width: expected.width, tabular: expected.tabular
            )))
            let twoSteps = try Self.ink(#require(ArchivoFile.swiftUIFont(
                size: size, weight: weight + 200, width: expected.width, tabular: expected.tabular
            )))
            #expect(
                abs(Double(actual - oneStep)) <= Double(oneStep) * 0.01,
                "\(expected.role): \(actual) vs +100 \(oneStep)"
            )
            #expect(abs(Double(actual - oneStep)) < abs(Double(actual - twoSteps)), "\(expected.role) is nearer +200")
        }

        @Test(
            "Text on the accent renders at wght 700 without Bold Text, not just in the spec table.",
            arguments: [LedgerFont.Role.button, .watchButton]
        )
        func accentLabelRole_rendered_isBold(role: LedgerFont.Role) throws {
            _ = FontRegistration.registerIfNeeded()
            let size = role.spec.size
            let text = "START WORKOUT"
            let actual = try Self.ink(LedgerFont.font(role, size: size, legibilityWeight: .regular), text: text)
            let bold = try Self.ink(#require(ArchivoFile.swiftUIFont(size: size, weight: 700, width: 100)), text: text)
            let semibold = try Self.ink(
                #require(ArchivoFile.swiftUIFont(size: size, weight: 600, width: 100)),
                text: text
            )
            #expect(actual >= bold - bold / 100, "\(role): ink \(actual), wght 700 \(bold), wght 600 \(semibold)")
        }
    }
}
