import SwiftUI

/// One row of a ``HairlineList``: a title, an optional detail line under it and an optional
/// trailing accessory, under a one-point rule (v2 "RECENT": 500 15 px title, 300 12.5 px meta,
/// 16 px vertical padding). VoiceOver reads the row as one element. With an `action` it is one
/// button, so its accessory must not be interactive (text or an icon, as v2's "Use"). Without an
/// action, one button accessory is allowed: the row reads as that button with the title first
/// ("Dumbbell Bench Press, Use") and activates it. At accessibility text sizes the accessory moves
/// under the title, so neither has to squeeze.
public struct HairlineRow<Accessory: View>: View {
    private let title: String
    private let detail: String?
    private let action: (() -> Void)?
    private let accessory: Accessory
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        _ title: String,
        detail: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.detail = detail
        self.action = action
        self.accessory = accessory()
    }

    public var body: some View {
        VStack(spacing: 0) {
            HairlineRule()
            if let action {
                Button(action: action) { content }
                    .buttonStyle(LedgerPressStyle())
            } else {
                content.accessibilityElement(children: .combine)
            }
        }
    }

    private var content: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LedgerSpacing.s))
            : AnyLayout(HStackLayout(spacing: LedgerSpacing.m))
        return layout {
            VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
                Text(title).ledgerFont(.body).foregroundStyle(LedgerColor.ink)
                if let detail {
                    Text(detail).ledgerFont(.label).foregroundStyle(LedgerColor.inkMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
        .padding(.vertical, LedgerSpacing.l)
        .contentShape(Rectangle())
    }
}

public extension HairlineRow where Accessory == EmptyView {
    init(_ title: String, detail: String? = nil, action: (() -> Void)? = nil) {
        self.init(title, detail: detail, action: action) { EmptyView() }
    }
}
