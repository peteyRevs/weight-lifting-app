import SwiftUI

/// Type tokens: Archivo roles from the v2 type system (docs/product-spec.md §8.5). Numbers are
/// 700 at a narrow width with tabular figures; everything else is 300–700 at normal width.
///
/// Views style text with `.ledgerFont(_:)`, which reads Dynamic Type and Bold Text from the
/// environment and adds the role's tracking, case and line height. A `Font` built from a Core Text
/// instance cannot follow the environment by itself (F06 notes, "Dynamic Type"), so the `Font`
/// entry points below take the text size explicitly; none of them returns an unscaled font.
public nonisolated enum LedgerFont {
    public enum Role: String, CaseIterable, Sendable {
        // Phone
        case display, title, heading, subheading
        case body, bodyLight, label, caption, button, eyebrow
        case numeralXL, numeralL, numeralM, numeralS
        // Watch: the prototype is drawn at 1.5× a 46 mm display (§4.1)
        case watchNumeral, watchCountdown, watchStat
        case watchTitle, watchButton, watchLabel, watchCaption
    }

    /// Bold Text moves every role one weight step up, as it does system text.
    public static let boldTextWeightStep: CGFloat = 100

    /// The role's font at a Dynamic Type size (and Bold Text setting).
    public static func font(
        _ role: Role,
        dynamicTypeSize: DynamicTypeSize,
        legibilityWeight: LegibilityWeight? = nil
    ) -> Font {
        font(role, size: scaledSize(role, dynamicTypeSize: dynamicTypeSize), legibilityWeight: legibilityWeight)
    }

    /// The role's font at an explicit, already scaled point size, never below the role's floor.
    public static func font(_ role: Role, size: CGFloat, legibilityWeight: LegibilityWeight? = nil) -> Font {
        let spec = role.spec
        let weight = spec.weight + (legibilityWeight == .bold ? boldTextWeightStep : 0)
        let pointSize = max(size, spec.minimumSize)
        return Font(ArchivoFont.make(size: pointSize, weight: weight, width: spec.width, tabularDigits: spec.isTabular))
    }

    /// The role's point size at a Dynamic Type size, on SwiftUI's own curve for custom fonts
    /// relative to the role's text style (exact at `.large` on iOS and at `.xLarge` on watchOS),
    /// never below the role's floor. Resolved sizes are whole points, so the factor is read at
    /// 1000 pt and applied to the design size.
    public static func scaledSize(_ role: Role, dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        FontRegistration.registerIfNeeded() // an unknown name sends Core Text on a slow fallback search
        let spec = role.spec
        var environment = EnvironmentValues()
        environment.dynamicTypeSize = dynamicTypeSize
        let probe = Font.custom(ArchivoFont.postScriptName, size: 1000, relativeTo: spec.textStyle)
        let factor = probe.resolve(in: environment.fontResolutionContext).pointSize / 1000
        return max(spec.size * factor, spec.minimumSize)
    }

    /// Archivo at any point on its axes. `weight` is `wght` (the design uses 300…700), `width` is
    /// `wdth` (88…112); both are clamped to the font's own ranges, 100…900 and 62…125.
    public static func archivo(size: CGFloat, weight: CGFloat, width: CGFloat) -> Font {
        Font(ArchivoFont.make(size: size, weight: weight, width: width))
    }
}

/// One type role, in the units the prototype uses: CSS px (= pt), `wght`, `wdth`, line height as a
/// multiple of the size, and letter spacing in em.
public nonisolated struct LedgerTypeSpec: Equatable, Sendable {
    public let size: CGFloat
    public let weight: CGFloat
    public let width: CGFloat
    public let lineHeight: CGFloat
    public let tracking: CGFloat
    public let isTabular: Bool
    public let isUppercase: Bool
    /// The Dynamic Type curve the size follows.
    public let textStyle: Font.TextStyle
    /// The size never scales below this (watch roles: 11 pt, F06 criterion 4).
    public let minimumSize: CGFloat
}

public nonisolated extension LedgerFont.Role {
    var spec: LedgerTypeSpec {
        switch self {
        case .display: .text(38, 600, width: 98, line: 1.06, tracking: -0.035, .largeTitle)
        case .title: .text(32, 600, width: 98, tracking: -0.035, .largeTitle)
        case .heading: .text(27, 600, width: 98, line: 1.08, tracking: -0.032, .title)
        case .subheading: .text(21, 600, width: 98, line: 1.1, tracking: -0.03, .title3)
        case .body: .text(15, 500, line: 1.2, .subheadline)
        case .bodyLight: .text(13.5, 300, line: 1.6, .footnote)
        case .label: .text(12.5, 300, line: 1.2, .footnote)
        case .caption: .text(12, 400, .caption)
        case .button: .text(16, 700, tracking: -0.005, .callout) // bold: white on accent is 3.1:1
        case .eyebrow: .text(10, 500, tracking: 0.18, uppercase: true, .caption2)
        case .numeralXL: .numeral(34, width: 88, tracking: -0.03, .largeTitle)
        case .numeralL: .numeral(30, width: 88, tracking: -0.03, .title)
        case .numeralM: .numeral(24, width: 90, tracking: -0.025, .title2)
        case .numeralS: .numeral(15, width: 90, tracking: 0, .subheadline)
        case .watchNumeral: .watch(.numeral(64, width: 92, line: 0.86, tracking: -0.035, .largeTitle))
        case .watchCountdown: .watch(.numeral(52, width: 92, tracking: -0.035, .largeTitle))
        case .watchStat: .watch(.numeral(30, width: 92, tracking: -0.03, .title3))
        case .watchTitle: .watch(.text(20, 600, line: 1.12, .headline))
        case .watchButton: .watch(.text(21, 700, tracking: -0.01, .body))
        case .watchLabel: .watch(.text(17, 700, tracking: 0.1, uppercase: true, .footnote))
        case .watchCaption: .watch(.text(17, 600, tracking: 0.07, uppercase: true, .footnote))
        }
    }
}

private nonisolated extension LedgerTypeSpec {
    static func text(
        _ size: CGFloat,
        _ weight: CGFloat,
        width: CGFloat = 100,
        line: CGFloat = 1,
        tracking: CGFloat = 0,
        uppercase: Bool = false,
        _ textStyle: Font.TextStyle
    ) -> LedgerTypeSpec {
        LedgerTypeSpec(
            size: size, weight: weight, width: width, lineHeight: line, tracking: tracking,
            isTabular: false, isUppercase: uppercase, textStyle: textStyle, minimumSize: 0
        )
    }

    static func numeral(
        _ size: CGFloat,
        width: CGFloat,
        line: CGFloat = 1,
        tracking: CGFloat,
        _ textStyle: Font.TextStyle
    ) -> LedgerTypeSpec {
        LedgerTypeSpec(
            size: size, weight: 700, width: width, lineHeight: line, tracking: tracking,
            isTabular: true, isUppercase: false, textStyle: textStyle, minimumSize: 0
        )
    }

    /// A watch role from the watch prototype, which is drawn at 1.5× a 46 mm display (spec §4.1).
    /// Sizes are exact at `.xLarge`, the 44–49 mm default text size and the size watchOS scales
    /// custom metrics from; the 40–42 mm default (`.large`) scales them to about 94 %, so the
    /// 11 pt floor keeps the smallest labels legible there.
    static func watch(_ prototype: LedgerTypeSpec) -> LedgerTypeSpec {
        LedgerTypeSpec(
            size: prototype.size / 1.5, weight: prototype.weight, width: prototype.width,
            lineHeight: prototype.lineHeight, tracking: prototype.tracking, isTabular: prototype.isTabular,
            isUppercase: prototype.isUppercase, textStyle: prototype.textStyle, minimumSize: 11
        )
    }
}

public extension View {
    /// Sets text in a type role: Archivo at the role's axes, its size scaled with Dynamic Type and
    /// its weight stepped up by Bold Text, plus the role's tracking, case and line height.
    func ledgerFont(_ role: LedgerFont.Role) -> some View {
        modifier(LedgerTextStyle(role: role))
    }
}

struct LedgerTextStyle: ViewModifier {
    let role: LedgerFont.Role
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight

    func body(content: Content) -> some View {
        let spec = role.spec
        let size = LedgerFont.scaledSize(role, dynamicTypeSize: dynamicTypeSize)
        content
            .font(LedgerFont.font(role, size: size, legibilityWeight: legibilityWeight))
            .tracking(spec.tracking * size)
            .textCase(spec.isUppercase ? .uppercase : nil)
            .lineHeight(.multiple(factor: spec.lineHeight))
    }
}
