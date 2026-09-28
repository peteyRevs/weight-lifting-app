import SwiftUI
#if os(iOS)
    import UIKit
#endif

/// Colour tokens (docs/product-spec.md §8.1–§8.3). Dark is the v2 palette and the primary
/// theme; light is the v1 "paper / ink" palette (decision #1). The `watch…` tokens are the watch
/// palette, which has a single appearance.
///
/// Text and rules are one ink colour at fixed alphas. Only `ink` and `inkSecondary` reach
/// 4.5:1 on both grounds, so only they may carry meaning in small text; `inkMuted` (4.2:1 dark,
/// 2.9:1 light) is for supplementary text, and `inkFaint`, `inkDim` and the hairlines are
/// decorative (F06 implementation notes, "Contrast").
public nonisolated enum LedgerColor {
    // MARK: Grounds

    /// Screen background: paper `#EFEDE6` / ground `#0B0B0D`.
    public static let ground = Color(light: .paper, dark: .ground)
    /// Raised surface: card `#FFFFFF` / sheet `#131316`.
    public static let surface = Color(light: .card, dark: .sheet)

    // MARK: Ink

    /// Primary text: ink `#16150F` / text `#F4F2ED`.
    public static let ink = Color(light: .ink, dark: .text)
    /// Secondary text, 72 %.
    public static let inkSecondary = ink(0.72)
    /// Metadata and captions, 45 %.
    public static let inkMuted = ink(0.45)
    /// Column headers and decorative labels, 32 %.
    public static let inkFaint = ink(0.32)
    /// Completed rows (`DIM` in the v2 prototype), 28 %.
    public static let inkDim = ink(0.28)
    /// Default one-point rule (`LINE`), 8 %.
    public static let hairline = ink(0.08)
    /// Outlined controls and avatar rings, 14 %.
    public static let hairlineStrong = ink(0.14)

    // MARK: Accent: once per screen, on the thing you are about to touch (§8.4)

    /// `#FF5B22`.
    public static let accent = Color(light: .accent, dark: .accent)
    /// Orange text: `#C63F0F` on paper for contrast (`accentDeep`), `#FF5B22` on the dark ground.
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
    /// Captions under numbers, 40 %.
    public static let watchInkMuted = Color(LedgerRGBA.white.opacity(0.4))
    /// Outlined buttons and inactive set dots, 22 %.
    public static let watchOutline = Color(LedgerRGBA.white.opacity(0.22))
    /// List-row borders, 14 %.
    public static let watchHairline = Color(LedgerRGBA.white.opacity(0.14))
    /// Rest-ring track, 13 %.
    public static let watchTrack = Color(LedgerRGBA.white.opacity(0.13))

    private static func ink(_ alpha: Double) -> Color {
        Color(light: .ink.opacity(alpha), dark: .text.opacity(alpha))
    }
}

/// An sRGB colour written the way the spec writes it: a hex triplet and an alpha.
nonisolated struct LedgerRGBA: Equatable {
    let hex: UInt32
    let alpha: Double

    init(_ hex: UInt32, alpha: Double = 1) {
        self.hex = hex
        self.alpha = alpha
    }

    var red: Double {
        Double((hex >> 16) & 0xFF) / 255
    }

    var green: Double {
        Double((hex >> 8) & 0xFF) / 255
    }

    var blue: Double {
        Double(hex & 0xFF) / 255
    }

    func opacity(_ alpha: Double) -> LedgerRGBA {
        LedgerRGBA(hex, alpha: alpha)
    }

    static let paper = LedgerRGBA(0xEFEDE6)
    static let card = LedgerRGBA(0xFFFFFF)
    static let ink = LedgerRGBA(0x16150F)
    static let ground = LedgerRGBA(0x0B0B0D)
    static let sheet = LedgerRGBA(0x131316)
    static let text = LedgerRGBA(0xF4F2ED)
    static let accent = LedgerRGBA(0xFF5B22)
    static let accentDeep = LedgerRGBA(0xC63F0F)
    static let white = LedgerRGBA(0xFFFFFF)
}

nonisolated extension Color {
    init(_ rgba: LedgerRGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }

    /// A colour that follows the environment's colour scheme. watchOS has one (dark) appearance
    /// and no dynamic `UIColor`; the macOS slice exists only for host-side `swift test`.
    init(light: LedgerRGBA, dark: LedgerRGBA) {
        #if os(iOS)
            self.init(uiColor: UIColor { traits in
                let rgba = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(red: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
            })
        #else
            self.init(dark)
        #endif
    }
}
