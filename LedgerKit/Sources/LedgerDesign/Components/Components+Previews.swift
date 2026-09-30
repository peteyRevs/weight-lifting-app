import SwiftUI

// Every component's preview. They live apart from the components so line coverage leaves them out
// (docs/testing-strategy.md §4: `*+Previews.swift`); each gallery is the one the snapshot tests render.

#Preview("Eyebrow") {
    EyebrowGallery().ledgerGalleryPage()
}

#Preview("HairlineList") {
    HairlineListGallery().ledgerGalleryPage()
}

#Preview("IconPillButton") {
    IconPillButtonGallery().ledgerGalleryPage()
}

#Preview("LedgerIcon") {
    HStack(spacing: LedgerSpacing.l) {
        ForEach(LedgerIcon.allCases, id: \.self) { LedgerIconView($0, sizedAs: .heading) }
    }
    .foregroundStyle(LedgerColor.ink)
    .padding(LedgerSpacing.screen)
    .background(LedgerColor.ground)
}

#Preview("PillButton") {
    PillButtonGallery().ledgerGalleryPage()
}

#Preview("PrimaryButton") {
    PrimaryButtonGallery().ledgerGalleryPage()
}

#Preview("RestRing") {
    RestRingGallery().ledgerGalleryPage()
}

#Preview("SetRow") {
    SetRowGallery().ledgerGalleryPage()
}

#Preview("SetRowSteppers") {
    SetRowSteppers(
        weightStep: "5 lb",
        repStep: "1 rep",
        weight: "185 pounds",
        reps: "5 reps",
        onWeight: { _ in },
        onReps: { _ in }
    )
    .ledgerGalleryPage()
}

#Preview("WeekStrip") {
    WeekStripGallery().ledgerGalleryPage()
}

#Preview("StatTile") {
    StatTileGallery().ledgerGalleryPage()
}

#Preview("ProgressSegments") {
    ProgressSegmentsGallery().ledgerGalleryPage()
}

#Preview("SheetChrome") {
    SheetChromeGallery().ledgerGalleryPage()
}

#Preview("EmptyState") {
    EmptyStateGallery().ledgerGalleryPage()
}

#Preview("WatchPrimaryButton") {
    WatchPrimaryButtonGallery().ledgerWatchPage()
}

#Preview("WatchRestRing") {
    WatchRestRingGallery().ledgerWatchPage()
}

#Preview("WatchStatBlock") {
    WatchStatBlockGallery().ledgerWatchPage()
}

#if DEBUG
    #Preview("DesignGallery") {
        DesignGallery()
    }
#endif
