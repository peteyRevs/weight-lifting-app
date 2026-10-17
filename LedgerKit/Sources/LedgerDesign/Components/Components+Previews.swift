#if DEBUG
    import SwiftUI

    // Every component's preview. They live apart from the components so line coverage leaves them out
    // (docs/testing-strategy.md §4: `*+Previews.swift`); each gallery is the one the snapshot tests render.

    /// Every preview in LedgerDesign, one case each (F07 criterion 8): each `#Preview` below shows its case's content,
    /// its tests (`PreviewTests`) render every case and fail on a `#Preview` that is not a case here.
    enum DesignPreview: String, CaseIterable {
        case eyebrow = "Eyebrow"
        case hairlineList = "HairlineList"
        case iconPillButton = "IconPillButton"
        case iconPillButtonSymbol = "IconPillButton symbol"
        case ledgerIcon = "LedgerIcon"
        case pillButton = "PillButton"
        case pillButtonStates = "PillButton states"
        case primaryButton = "PrimaryButton"
        case primaryButtonTimer = "PrimaryButton timer"
        case restRing = "RestRing"
        case setRow = "SetRow"
        case setRowSteppers = "SetRowSteppers"
        case weekStrip = "WeekStrip"
        case statTile = "StatTile"
        case progressSegments = "ProgressSegments"
        case sheetChrome = "SheetChrome"
        case emptyState = "EmptyState"
        case stepperField = "StepperField"
        case ledgerToggleStyle = "LedgerToggleStyle"
        case wrapLayout = "WrapLayout"
        case watchPrimaryButton = "WatchPrimaryButton"
        case watchRestRing = "WatchRestRing"
        case watchStatBlock = "WatchStatBlock"
        case designGallery = "DesignGallery"
        case debugMenu = "DebugMenu"
        case diagnosticsPage = "DiagnosticsPage"

        @ViewBuilder var content: some View {
            switch self {
            case .eyebrow: EyebrowGallery().ledgerGalleryPage()
            case .hairlineList: HairlineListGallery().ledgerGalleryPage()
            case .iconPillButton: IconPillButtonGallery().ledgerGalleryPage()
            case .iconPillButtonSymbol: IconPillButtonSymbolGallery().ledgerGalleryPage()
            case .ledgerIcon: Self.iconsPage
            case .pillButton: PillButtonGallery().ledgerGalleryPage()
            case .pillButtonStates: PillButtonStatesGallery().ledgerGalleryPage()
            case .primaryButton: PrimaryButtonGallery().ledgerGalleryPage()
            case .primaryButtonTimer: PrimaryButtonTimerGallery().ledgerGalleryPage()
            case .restRing: RestRingGallery().ledgerGalleryPage()
            case .setRow: SetRowGallery().ledgerGalleryPage()
            case .setRowSteppers: Self.setRowSteppersPage
            case .weekStrip: WeekStripGallery().ledgerGalleryPage()
            case .statTile: StatTileGallery().ledgerGalleryPage()
            case .progressSegments: ProgressSegmentsGallery().ledgerGalleryPage()
            case .sheetChrome: SheetChromeGallery().ledgerGalleryPage()
            case .emptyState: EmptyStateGallery().ledgerGalleryPage()
            case .stepperField: StepperFieldGallery().ledgerGalleryPage()
            case .ledgerToggleStyle: LedgerToggleGallery().ledgerGalleryPage()
            case .wrapLayout: WrapLayoutGallery().ledgerGalleryPage()
            case .watchPrimaryButton: WatchPrimaryButtonGallery().ledgerWatchPage()
            case .watchRestRing: WatchRestRingGallery().ledgerWatchPage()
            case .watchStatBlock: WatchStatBlockGallery().ledgerWatchPage()
            case .designGallery: DesignGallery()
            case .debugMenu:
                DebugMenu(actions: [DebugMenu.Action("Start sample workout", identifier: "debug.menu.sample") {}]) {
                    Self.diagnostics
                }
            case .diagnosticsPage: NavigationStack { DiagnosticsPage(sections: Self.diagnostics) }
            }
        }

        /// What a first launch on the simulator reads.
        private static let diagnostics = [
            DiagnosticsSection("App", lines: [
                DiagnosticsLine("Database", "/Library/Application Support/Database/ledger.sqlite", key: "path"),
                DiagnosticsLine("Device", "6F1C2E0A-4B7D-4E8A-9C3F-2D5B8A1E7C40", key: "deviceID"),
                DiagnosticsLine("Health", "Not determined", key: "health"),
                DiagnosticsLine("Launch to first frame", "312 ms", key: "launch"),
                DiagnosticsLine("Dependencies", "live", key: "context")
            ]),
            DiagnosticsSection("Rows", lines: [
                DiagnosticsLine("device", "1", key: "rows.device"),
                DiagnosticsLine("exercise", "224", key: "rows.exercise"),
                DiagnosticsLine("workout", "0", key: "rows.workout")
            ])
        ]

        private static var iconsPage: some View {
            HStack(spacing: LedgerSpacing.l) {
                ForEach(LedgerIcon.allCases, id: \.self) { LedgerIconView($0, sizedAs: .heading) }
            }
            .foregroundStyle(LedgerColor.ink)
            .padding(LedgerSpacing.screen)
            .background(LedgerColor.ground)
        }

        private static var setRowSteppersPage: some View {
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
    }

    #Preview("Eyebrow") {
        DesignPreview.eyebrow.content
    }

    #Preview("HairlineList") {
        DesignPreview.hairlineList.content
    }

    #Preview("IconPillButton") {
        DesignPreview.iconPillButton.content
    }

    #Preview("IconPillButton symbol") {
        DesignPreview.iconPillButtonSymbol.content
    }

    #Preview("LedgerIcon") {
        DesignPreview.ledgerIcon.content
    }

    #Preview("PillButton") {
        DesignPreview.pillButton.content
    }

    #Preview("PillButton states") {
        DesignPreview.pillButtonStates.content
    }

    #Preview("PrimaryButton") {
        DesignPreview.primaryButton.content
    }

    #Preview("PrimaryButton timer") {
        DesignPreview.primaryButtonTimer.content
    }

    #Preview("RestRing") {
        DesignPreview.restRing.content
    }

    #Preview("SetRow") {
        DesignPreview.setRow.content
    }

    #Preview("SetRowSteppers") {
        DesignPreview.setRowSteppers.content
    }

    #Preview("WeekStrip") {
        DesignPreview.weekStrip.content
    }

    #Preview("StatTile") {
        DesignPreview.statTile.content
    }

    #Preview("ProgressSegments") {
        DesignPreview.progressSegments.content
    }

    #Preview("SheetChrome") {
        DesignPreview.sheetChrome.content
    }

    #Preview("EmptyState") {
        DesignPreview.emptyState.content
    }

    #Preview("StepperField") {
        DesignPreview.stepperField.content
    }

    #Preview("LedgerToggleStyle") {
        DesignPreview.ledgerToggleStyle.content
    }

    #Preview("WrapLayout") {
        DesignPreview.wrapLayout.content
    }

    #Preview("WatchPrimaryButton") {
        DesignPreview.watchPrimaryButton.content
    }

    #Preview("WatchRestRing") {
        DesignPreview.watchRestRing.content
    }

    #Preview("WatchStatBlock") {
        DesignPreview.watchStatBlock.content
    }

    #Preview("DesignGallery") {
        DesignPreview.designGallery.content
    }

    #Preview("DebugMenu") {
        DesignPreview.debugMenu.content
    }

    #Preview("DiagnosticsPage") {
        DesignPreview.diagnosticsPage.content
    }
#endif
