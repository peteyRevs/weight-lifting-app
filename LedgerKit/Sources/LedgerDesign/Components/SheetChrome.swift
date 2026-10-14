import SwiftUI

/// A bottom sheet's frame (v2 "Swap exercise"): a title and a ghost cancel pill on one line (the
/// pill under the title at accessibility text sizes), the content under them, on the raised surface
/// with 28 pt top corners and a one-point rule along the top edge. Present it with `.sheet`: it fills
/// the sheet and keeps its content at the top, and it sets the sheet's background and corner radius,
/// so the system sheet takes the same surface and shape. The title always gets every line it needs.
/// Content that can outgrow the sheet's detent (long lists, large text sizes) goes in a `ScrollView`.
///
/// VoiceOver reads the title as a heading, then the cancel button, then the content, and its escape
/// gesture (a two-finger scrub) calls `onCancel`, as the cancel button does. `title` and `cancel` are
/// shown as given; features pass copy from their catalog. `cancelIdentifier` names the cancel button for
/// a UI test, where its words are not what the test should find it by.
public struct SheetChrome<Content: View>: View {
    private let title: String
    private let cancel: String
    private let cancelIdentifier: String
    private let onCancel: () -> Void
    private let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        _ title: String,
        cancel: String,
        cancelIdentifier: String = "",
        onCancel: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.cancel = cancel
        self.cancelIdentifier = cancelIdentifier
        self.onCancel = onCancel
        self.content = content()
    }

    public var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: LedgerRadius.sheet,
            topTrailingRadius: LedgerRadius.sheet,
            style: .circular
        )
        // At accessibility text sizes the cancel pill moves under the title, so the title keeps the
        // full width and never breaks inside a word.
        let header = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: LedgerSpacing.m))
        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
            header {
                Text(title)
                    .ledgerFont(.subheading)
                    .foregroundStyle(LedgerColor.ink)
                    .fixedSize(horizontal: false, vertical: true) // a sheet's height must never cut it short
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                PillButton(cancel, style: .ghost, action: onCancel)
                    .accessibilityIdentifier(cancelIdentifier)
            }
            content
        }
        .padding(.horizontal, LedgerSpacing.xl)
        .padding(.vertical, LedgerSpacing.l)
        // Both height bounds: the frame takes the sheet's height, so content that outgrows it falls off
        // the bottom instead of being centred with the title above the sheet's top (C3-1).
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .background(LedgerColor.surface, in: shape)
        .overlay {
            // CSS `border-top` on a rounded box: the rule runs along the top edge into both corners.
            shape.strokeBorder(LedgerColor.hairline, lineWidth: LedgerHairline.width)
                .mask(alignment: .top) { Rectangle().frame(height: LedgerRadius.sheet) }
        }
        .accessibilityAction(.escape, onCancel)
        .presentationBackground(LedgerColor.surface)
        .presentationCornerRadius(LedgerRadius.sheet)
    }
}

/// The swap sheet with its rows, for the preview, the snapshot tests and the gallery.
struct SheetChromeGallery: View {
    var body: some View {
        SheetChrome("Swap exercise", cancel: "Cancel") {} content: {
            Text("Same movement pattern, equipment you have.")
                .ledgerFont(.bodyLight)
                .foregroundStyle(LedgerColor.inkMuted)
            HairlineList {
                HairlineRow("Dumbbell Bench Press", detail: "Similar pattern · 2 × 70 lb") {} accessory: {
                    Text("Use").ledgerFont(.caption).foregroundStyle(LedgerColor.accentText)
                }
                HairlineRow("Smith Machine Press", detail: "Machine · bench occupied?") {} accessory: {
                    Text("Use").ledgerFont(.caption).foregroundStyle(LedgerColor.accentText)
                }
            }
        }
    }
}
