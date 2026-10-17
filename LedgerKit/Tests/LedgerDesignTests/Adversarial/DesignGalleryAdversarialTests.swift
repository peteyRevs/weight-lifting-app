#if DEBUG && os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    extension RenderingSuites {
        /// F06 criterion 9, adversarial round 1: every public token in `LedgerDesign/Tokens`, listed from
        /// the source (`grep "public static" Tokens/*.swift`, 2026-09-30), is drawn in the gallery with its
        /// name. Functions are not tokens; `buzzKeyframes` and `ledgerBuzz` are the gallery's "buzz".
        @Suite("DesignGallery names (adversarial, slice 3 round 1)", .tags(.design))
        struct DesignGalleryAdversarialTests {
            /// Every `public static let` of the token types, each referenced so a rename fails to compile.
            static let tokens: [(qualified: String, value: Any)] = [
                ("LedgerColor.ground", LedgerColor.ground),
                ("LedgerColor.surface", LedgerColor.surface),
                ("LedgerColor.ink", LedgerColor.ink),
                ("LedgerColor.inkSecondary", LedgerColor.inkSecondary),
                ("LedgerColor.inkMuted", LedgerColor.inkMuted),
                ("LedgerColor.inkFaint", LedgerColor.inkFaint),
                ("LedgerColor.inkDim", LedgerColor.inkDim),
                ("LedgerColor.hairline", LedgerColor.hairline),
                ("LedgerColor.hairlineStrong", LedgerColor.hairlineStrong),
                ("LedgerColor.accent", LedgerColor.accent),
                ("LedgerColor.accentText", LedgerColor.accentText),
                ("LedgerColor.accentSoft", LedgerColor.accentSoft),
                ("LedgerColor.accentLine", LedgerColor.accentLine),
                ("LedgerColor.onAccent", LedgerColor.onAccent),
                ("LedgerColor.watchGround", LedgerColor.watchGround),
                ("LedgerColor.watchInk", LedgerColor.watchInk),
                ("LedgerColor.watchInkSecondary", LedgerColor.watchInkSecondary),
                ("LedgerColor.watchInkMuted", LedgerColor.watchInkMuted),
                ("LedgerColor.watchOutline", LedgerColor.watchOutline),
                ("LedgerColor.watchHairline", LedgerColor.watchHairline),
                ("LedgerColor.watchTrack", LedgerColor.watchTrack),
                ("LedgerSpacing.xs", LedgerSpacing.xs),
                ("LedgerSpacing.s", LedgerSpacing.s),
                ("LedgerSpacing.m", LedgerSpacing.m),
                ("LedgerSpacing.l", LedgerSpacing.l),
                ("LedgerSpacing.xl", LedgerSpacing.xl),
                ("LedgerSpacing.xxl", LedgerSpacing.xxl),
                ("LedgerSpacing.screen", LedgerSpacing.screen),
                ("LedgerRadius.pill", LedgerRadius.pill),
                ("LedgerRadius.card", LedgerRadius.card),
                ("LedgerRadius.sheet", LedgerRadius.sheet),
                ("LedgerRadius.row", LedgerRadius.row),
                ("LedgerHairline.width", LedgerHairline.width),
                ("LedgerMotion.snappy", LedgerMotion.snappy),
                ("LedgerMotion.buzzCycle", LedgerMotion.buzzCycle),
                ("LedgerMotion.buzzRepeats", LedgerMotion.buzzRepeats),
                ("LedgerFont.boldTextWeightStep", LedgerFont.boldTextWeightStep)
            ]

            /// An element names `name` when it reads the name alone or the name then " · " and its value,
            /// as the token pages write "xs · 4".
            static func names(_ label: String, _ name: String) -> Bool {
                label == name || label.hasPrefix("\(name) · ")
            }

            @Test("Every public token constant is drawn in the gallery with its name")
            func gallery_everyPublicTokenConstant_isNamed() {
                let labels = DesignGalleryContent().accessibilityElements().map(\.label)
                for token in Self.tokens {
                    let name = String(token.qualified.split(separator: ".").last ?? "")
                    #expect(
                        labels.contains { Self.names($0, name) },
                        "\(token.qualified) (\(token.value)) is not named in the gallery"
                    )
                }
                for role in LedgerFont.Role.allCases {
                    #expect(labels.contains(role.rawValue), "LedgerFont.Role.\(role) is not named")
                }
                for icon in LedgerIcon.allCases {
                    #expect(labels.contains("\(icon)"), "LedgerIcon.\(icon) is not named")
                }
            }

            /// `grep -E "public (nonisolated )?struct \w+(<…>)?: View" Components/*.swift`, 2026-09-30, and
            /// again on 2026-10-08 (F11 S8: `StepperField`). The slice's two other controls are no views and
            /// are listed with it: `LedgerToggleStyle` is a style and `WrapLayout` a layout.
            static let publicViews = [
                "EmptyState", "Eyebrow", "HairlineList", "HairlineRow", "HairlineRule", "IconPillButton",
                "LedgerIconView",
                "PillButton", "PrimaryButton", "ProgressSegments", "RestRing", "SetRow", "SetRowHeader",
                "SetRowSteppers",
                "SheetChrome", "StatTile", "StatTileRow", "WatchPrimaryButton", "WatchRestRing", "WatchStatBlock",
                "WeekStrip",
                "StepperField", "LedgerToggleStyle", "WrapLayout"
            ]

            @Test("Every public view in Components/ is named by a gallery heading")
            func gallery_everyPublicView_isNamedByAHeading() {
                let headings = DesignGalleryContent().accessibilityElements()
                    .filter { $0.traits.contains(.header) }
                    .flatMap { $0.label.components(separatedBy: " · ") }
                for view in Self.publicViews {
                    #expect(headings.contains(view), "\(view) has no heading")
                }
            }
        }
    }
#endif
