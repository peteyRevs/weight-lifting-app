#if DEBUG // DesignGallery exists in Debug builds only; the test plans build Debug
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SnapshotTesting
    import SwiftUI
    import Testing

    extension RenderingSuites {
        /// F06 criterion 9: `DesignGallery` shows every component and every token, each with its name.
        /// The lists below are the module's public surface, written out: a new component or token
        /// that is not added to the gallery, and to these lists, fails the review of its PR.
        @Suite("DesignGallery", .tags(.design))
        struct DesignGalleryTests {
            /// Every public view (and the icon type) in `LedgerDesign/Components`.
            static let components = [
                "PrimaryButton", "PillButton", "IconPillButton", "LedgerIcon", "LedgerIconView", "Eyebrow",
                "HairlineList", "HairlineRow", "HairlineRule", "SetRow", "SetRowHeader", "SetRowSteppers",
                "RestRing", "WeekStrip", "StatTile", "StatTileRow", "ProgressSegments", "SheetChrome", "EmptyState",
                "WatchPrimaryButton", "WatchRestRing", "WatchStatBlock",
                "StepperField", "LedgerToggleStyle", "WrapLayout", "ReceiptLayout",
                // F12 S1 (ruling R5): moved from FeatureProgram.
                "FilterChipRow", "SearchField",
                // F14 S1 (A5): Settings' units.
                "SegmentedChoice"
            ]
            /// Every token type in `LedgerDesign/Tokens`.
            static let tokenTypes = [
                "LedgerColor", "LedgerFont", "LedgerSpacing", "LedgerRadius", "LedgerHairline", "LedgerMotion"
            ]
            /// Every token, as its page names it.
            static let tokens: [String] = [
                "ground", "surface", "ink", "inkSecondary", "inkMuted", "inkFaint", "inkDim", "hairline",
                "hairlineStrong", "accent", "accentText", "accentSoft", "accentLine", "onAccent", "watchGround",
                "watchInk", "watchInkSecondary", "watchInkMuted", "watchOutline", "watchHairline", "watchTrack",
                "xs · 4", "s · 8", "m · 12", "l · 16", "xl · 24", "xxl · 32", "screen · 26",
                "row · 16", "card · 26", "sheet · 28", "pill · 999", "width · 1", "snappy", "buzz",
                "buzzCycle · 0.38 s", "buzzRepeats · 3", "boldTextWeightStep · 100",
                "arrow", "check", "chevron", "swap", "minus", "plus"
            ] + LedgerFont.Role.allCases.map(\.rawValue)

            @Test("Every component and token type has its own named section, once")
            func sections_names_coverEveryComponentAndTokenType() {
                let named = GallerySection.all.flatMap { $0.name.components(separatedBy: " · ") }
                #expect(Set(named) == Set(Self.components + Self.tokenTypes))
                #expect(named.count == Set(named).count, "a name appears twice: \(named)")
            }

            #if os(iOS)
                /// The gallery's content, the public view's `ScrollView`'s only child, read whole. The
                /// accessibility helper reads no elements through a hosted SwiftUI `ScrollView` (measured:
                /// none, even at a fixed 874 pt height), so the test reads what the scroll view holds.
                @Test("VoiceOver finds every section as a heading and every token by its name")
                func gallery_accessibilityTree_namesEverySectionAndToken() {
                    let elements = DesignGalleryContent().accessibilityElements()
                    let headings = elements.filter { $0.traits.contains(.header) }.map(\.label)
                    let labels = Set(elements.map(\.label))
                    let sections = GallerySection.all.map(\.name)
                    // Components draw headings of their own (eyebrows, sheet and empty-state titles).
                    #expect(headings.filter(Set(sections).contains) == sections)
                    for token in Self.tokens {
                        #expect(labels.contains(token), "no element reads \"\(token)\"")
                    }
                }

                /// Dark only, the primary theme (review R3-S4): the gallery adds no pixels the component and
                /// token references lack, and every design change re-records it.
                @Test("DesignGallery matches its reference (dark, large)")
                func designGallery_dark_matchesReference() {
                    assertPhoneSnapshot(
                        of: DesignGalleryContent().frame(width: SnapshotConfig.phoneWidth),
                        SnapshotAppearance(.dark, .large)
                    )
                }
            #endif
        }
    }
#endif
