import SwiftUI
#if os(iOS)
    import UIKit
#endif

/// Colour tokens (docs/product-spec.md §8.1–§8.3). Dark is the v2 palette and the primary
/// theme; light is the v1 "paper / ink" palette (decision #1). The `watch…` tokens are the watch
/// palette, which has a single appearance.
///
/// Text and rules are one ink colour at fixed alphas. Every text token reaches WCAG AA (4.5:1)
/// on `ground` and `surface`, bare or under `accentSoft`, except `inkFaint` and `inkDim`, which
/// are decorative. With iOS Increase Contrast the ink ladder steps up: text to 7:1, `inkFaint` to
/// 4.5:1 (Pete, 2026-09-27; ratios in the F06 implementation notes).
public nonisolated enum LedgerColor {
    // MARK: Grounds

    /// Screen background: paper `#EFEDE6` / ground `#0B0B0D`.
    public static let ground = Color(light: .paper, dark: .ground)
    /// Raised surface: card `#FFFFFF` / sheet `#131316`.
    public static let surface = Color(light: .card, dark: .sheet)

    // MARK: Ink

    /// Primary text: ink `#16150F` / text `#F4F2ED`.
    public static let ink = Color(light: .ink, dark: .text)
    /// Secondary text, 72 % (Increase Contrast 86 %).
    public static let inkSecondary = ink(0.72, increased: 0.86)
    /// Metadata and captions: 62 % on paper, 51 % on dark (the spec's 45 % is below AA, and these
    /// keep AA on the `accentSoft` tint of a selected item too).
    public static let inkMuted = ink(0.51, light: 0.62, increased: 0.74)
    /// Column headers and decorative labels, 32 %.
    public static let inkFaint = ink(0.32, increased: 0.60)
    /// Completed rows (`DIM` in the v2 prototype), 28 %.
    public static let inkDim = ink(0.28, increased: 0.50)
    /// Default one-point rule (`LINE`), 8 %.
    public static let hairline = ink(0.08, increased: 0.20)
    /// Outlined controls and avatar rings, 14 %.
    public static let hairlineStrong = ink(0.14, increased: 0.30)

    // MARK: Accent: once per screen, on the thing you are about to touch (§8.4)

    /// `#FF5B22`.
    public static let accent = Color(light: .accent, dark: .accent)
    /// Orange text: `#B2390E` on paper (the spec's `accentDeep` `#C63F0F` × 0.9, for AA on paper and
    /// on `accentSoft`), `#FF5B22` on the dark ground.
    public static let accentText = Color(light: .accentDeep, dark: .accent)
    /// Tinted fill behind a selected item: 12 % on paper (`accentTint`), 16 % on dark (§8.3).
    public static let accentSoft = Color(light: .accent.opacity(0.12), dark: .accent.opacity(0.16))
    /// The one-pixel orange rule (`accentLine`), 40 %.
    public static let accentLine = Color(light: .accent.opacity(0.4), dark: .accent.opacity(0.4))
    /// Text and icons on an accent fill.
    public static let onAccent = Color(light: .white, dark: .white)

    // MARK: Watch (§8.3): black screen, white ink

    public static let watchGround = Color(LedgerRGBA(0x000000))
    public static let watchInk = Color(LedgerRGBA.white)
    /// Body copy and secondary values, 55 %.
    public static let watchInkSecondary = Color(LedgerRGBA.white.opacity(0.55))
    /// Captions under numbers: 46 % (the spec's 40 % is below AA).
    public static let watchInkMuted = Color(LedgerRGBA.white.opacity(0.46))
    /// Outlined buttons and inactive set dots, 22 %.
    public static let watchOutline = Color(LedgerRGBA.white.opacity(0.22))
    /// List-row borders, 14 %.
    public static let watchHairline = Color(LedgerRGBA.white.opacity(0.14))
    /// Rest-ring track, 13 %.
    public static let watchTrack = Color(LedgerRGBA.white.opacity(0.13))

    private static func ink(_ alpha: Double, light: Double? = nil, increased: Double) -> Color {
        Color(
            light: .ink.opacity(light ?? alpha), dark: .text.opacity(alpha),
            increased: (.ink.opacity(increased), .text.opacity(increased))
        )
    }
}

/// An sRGB colour written the way the spec writes it: a hex triplet and an alpha.
nonisolated struct LedgerRGBA: Equatable {
    var red, green, blue: Double
    var alpha = 1.0

    init(_ hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    func opacity(_ alpha: Double) -> LedgerRGBA {
        var copy = self
        copy.alpha = alpha
        return copy
    }

    static let paper = LedgerRGBA(0xEFEDE6)
    static let card = LedgerRGBA(0xFFFFFF)
    static let ink = LedgerRGBA(0x16150F)
    static let ground = LedgerRGBA(0x0B0B0D)
    static let sheet = LedgerRGBA(0x131316)
    static let text = LedgerRGBA(0xF4F2ED)
    static let accent = LedgerRGBA(0xFF5B22)
    static let accentDeep = LedgerRGBA(0xB2390E)
    static let white = LedgerRGBA(0xFFFFFF)
}

nonisolated extension Color {
    init(_ rgba: LedgerRGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }

    /// A colour that follows the colour scheme and, on iOS, Increase Contrast. watchOS has one
    /// (dark) appearance and no dynamic `UIColor`; the macOS slice exists only for `swift test`.
    init(light: LedgerRGBA, dark: LedgerRGBA, increased: (light: LedgerRGBA, dark: LedgerRGBA)? = nil) {
        #if os(iOS)
            self.init(uiColor: UIColor { traits in
                let normal = (light: light, dark: dark)
                let pair = traits.accessibilityContrast == .high ? increased ?? normal : normal
                let rgba = traits.userInterfaceStyle == .dark ? pair.dark : pair.light
                return UIColor(red: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
            })
        #else
            self.init(dark)
        #endif
    }
}
