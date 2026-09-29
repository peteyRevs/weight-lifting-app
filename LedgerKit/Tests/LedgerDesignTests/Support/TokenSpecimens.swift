@testable import LedgerDesign
import SwiftUI

/// Test-only specimen sheets that put every token on screen with its name, so a snapshot shows
/// the whole type ramp or palette at once. DesignGallery (F06 slice 3) is the product version.
enum Specimen {
    static let phoneRoles: [LedgerFont.Role] = [
        .display, .title, .heading, .subheading, .body, .bodyLight, .label, .caption, .button, .eyebrow,
        .numeralXL, .numeralL, .numeralM, .numeralS
    ]
    static let watchRoles: [LedgerFont.Role] = LedgerFont.Role.allCases.filter { !phoneRoles.contains($0) }

    /// Sample copy from the v2 prototype for each role; numeral roles show a set.
    static func sample(_ role: LedgerFont.Role) -> String {
        samples[role] ?? "185 × 5"
    }

    private static let samples: [LedgerFont.Role: String] = [
        .display: "Train four days a week",
        .title: "Upper A — Push focus", .heading: "Upper A — Push focus", .subheading: "Swap exercise",
        .body: "Barbell Bench Press", .bodyLight: "Same movement pattern, equipment you have.",
        .label: "3 sets · 8 reps", .caption: "Wednesday, August 19", .button: "Start workout",
        .eyebrow: "Up next", .watchLabel: "Resting", .watchCaption: "Elapsed",
        .watchTitle: "Bench Press", .watchButton: "Done set"
    ]
}

struct TypeRampSpecimen: View {
    let roles: [LedgerFont.Role]
    let width: CGFloat
    var ground = LedgerColor.ground
    var ink = LedgerColor.ink
    var nameInk = LedgerColor.inkMuted

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.m) {
            ForEach(roles, id: \.self) { role in
                VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
                    Text(role.rawValue).ledgerFont(.caption).foregroundStyle(nameInk)
                    Text(Specimen.sample(role)).ledgerFont(role).foregroundStyle(ink)
                }
            }
        }
        .padding(LedgerSpacing.l)
        .frame(width: width, alignment: .leading)
        .background(ground)
    }
}

struct PaletteSpecimen: View {
    let swatches: [(name: String, color: Color)]
    let width: CGFloat
    var ground = LedgerColor.ground
    var ink = LedgerColor.ink

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
            ForEach(swatches, id: \.name) { swatch in
                HStack(spacing: LedgerSpacing.m) {
                    RoundedRectangle(cornerRadius: LedgerSpacing.xs)
                        .fill(swatch.color)
                        .stroke(LedgerColor.hairlineStrong, lineWidth: LedgerHairline.width)
                        .frame(width: LedgerSpacing.xxl, height: LedgerSpacing.xl)
                    Text(swatch.name).ledgerFont(.caption).foregroundStyle(ink)
                }
            }
        }
        .padding(LedgerSpacing.l)
        .frame(width: width, alignment: .leading)
        .background(ground)
    }

    static let phone: [(name: String, color: Color)] = [
        ("ground", LedgerColor.ground), ("surface", LedgerColor.surface), ("ink", LedgerColor.ink),
        ("inkSecondary", LedgerColor.inkSecondary), ("inkMuted", LedgerColor.inkMuted),
        ("inkFaint", LedgerColor.inkFaint), ("inkDim", LedgerColor.inkDim), ("hairline", LedgerColor.hairline),
        ("hairlineStrong", LedgerColor.hairlineStrong), ("accent", LedgerColor.accent),
        ("accentText", LedgerColor.accentText), ("accentSoft", LedgerColor.accentSoft),
        ("accentLine", LedgerColor.accentLine), ("onAccent", LedgerColor.onAccent)
    ]

    static let watch: [(name: String, color: Color)] = [
        ("watchGround", LedgerColor.watchGround), ("watchInk", LedgerColor.watchInk),
        ("watchInkSecondary", LedgerColor.watchInkSecondary), ("watchInkMuted", LedgerColor.watchInkMuted),
        ("watchOutline", LedgerColor.watchOutline), ("watchHairline", LedgerColor.watchHairline),
        ("watchTrack", LedgerColor.watchTrack), ("accent", LedgerColor.accent)
    ]
}
