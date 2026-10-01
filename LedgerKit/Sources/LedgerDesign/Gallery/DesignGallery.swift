#if DEBUG
    import SwiftUI

    /// Every LedgerDesign token and component, each under its name (F06 criterion 9), for the debug
    /// menu (F07). It follows the device's colour scheme, text size and Bold Text; the watch components
    /// are drawn on black at the 46 mm width.
    ///
    /// Debug builds only. This file and `TokenPages.swift` compile under `#if DEBUG`, which SwiftPM and
    /// Xcode define for the Debug configuration alone, so a Release build (TestFlight, the App Store)
    /// holds no gallery code. The debug menu that opens it has to be `#if DEBUG` as well.
    public struct DesignGallery: View {
        public init() {}

        public var body: some View {
            ScrollView {
                DesignGalleryContent()
            }
            .background(LedgerColor.ground)
        }
    }

    /// The gallery's pages, one after another, each under its name as a heading.
    struct DesignGalleryContent: View {
        var body: some View {
            VStack(alignment: .leading, spacing: LedgerSpacing.xxl) {
                ForEach(GallerySection.all) { section in
                    VStack(alignment: .leading, spacing: LedgerSpacing.l) {
                        Text(section.name)
                            .ledgerFont(.subheading)
                            .foregroundStyle(LedgerColor.ink)
                            .accessibilityAddTraits(.isHeader)
                        section.content
                    }
                }
            }
            .ledgerGalleryPage()
        }
    }

    /// One named page of the gallery.
    struct GallerySection: Identifiable {
        /// The 46 mm screen's width (208 × 248 pt), which the watch components are drawn at.
        static let watchWidth: CGFloat = 208

        let name: String
        let content: AnyView

        var id: String {
            name
        }

        init(_ name: String, @ViewBuilder content: () -> some View) {
            self.name = name
            self.content = AnyView(content())
        }

        /// The tokens, then every public view in `Components/`, each gallery showing every state.
        static var all: [GallerySection] {
            [
                GallerySection("LedgerColor") { ColorTokenPage() },
                GallerySection("LedgerFont") { TypeTokenPage() },
                GallerySection("LedgerSpacing") { SpacingTokenPage() },
                GallerySection("LedgerRadius") { RadiusTokenPage() },
                GallerySection("LedgerHairline") { HairlineTokenPage() },
                GallerySection("LedgerMotion") { MotionTokenPage() },
                GallerySection("LedgerIcon · LedgerIconView") { IconTokenPage() },
                GallerySection("PrimaryButton") { PrimaryButtonGallery() },
                GallerySection("PillButton") { PillButtonGallery() },
                GallerySection("IconPillButton") { IconPillButtonGallery() },
                GallerySection("Eyebrow") { EyebrowGallery() },
                GallerySection("HairlineList · HairlineRow · HairlineRule") { HairlineListGallery() },
                GallerySection("SetRow · SetRowHeader · SetRowSteppers") { SetRowGallery() },
                GallerySection("RestRing") { RestRingGallery() },
                GallerySection("WeekStrip") { WeekStripGallery() },
                GallerySection("StatTile · StatTileRow") { StatTileGallery() },
                GallerySection("ProgressSegments") { ProgressSegmentsGallery() },
                GallerySection("SheetChrome") { SheetChromeGallery() },
                GallerySection("EmptyState") { EmptyStateGallery() },
                GallerySection("WatchPrimaryButton") { WatchPrimaryButtonGallery().galleryWatchScreen() },
                GallerySection("WatchRestRing") { WatchRestRingGallery().galleryWatchScreen() },
                GallerySection("WatchStatBlock") { WatchStatBlockGallery().galleryWatchScreen() }
            ]
        }
    }

    private extension View {
        /// A watch component as the 46 mm screen shows it: on black, at the watch's width.
        func galleryWatchScreen() -> some View {
            ledgerWatchPage().frame(width: GallerySection.watchWidth)
        }
    }
#endif
