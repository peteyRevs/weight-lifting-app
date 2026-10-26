import SwiftUI

/// A search field: an outlined pill, at least 44 pt high and with `s` above and below its line of text at every
/// size, that holds `text` and hands each change on as typed. Its placeholder is its spoken label too. A tap
/// anywhere on the pill puts the cursor in the field, which by itself is only as high as its line of text.
/// String-only: the caller holds the text (F11's exercise library, F12's Library).
///
/// A placeholder too wide for the field at large text sizes and on narrow phones is drawn as `short` when one is
/// given ("Search 224 exercises" becomes "Search"; F12 S1 review M1), and is still spoken whole.
public struct SearchField: View {
    private let placeholder: String
    private let short: String?
    private let text: String
    private let onChange: (String) -> Void
    @FocusState private var isEditing: Bool
    /// The width the field draws its text in, and the width the whole placeholder needs, as last laid out.
    @State private var room = CGFloat.infinity
    @State private var needed = CGFloat.zero

    /// The room the whole placeholder must leave (review R2-2). UIKit draws it, and cuts it short, inside
    /// `placeholderRect(forBounds:)`, measured by `SearchFieldFitTests` as wide as the field SwiftUI lays out
    /// (`room`) on phones 320 to 440 pt wide at every size: an inset of 0. The point covers UIKit's rounding of the
    /// text's width up to a whole point. The closest fit measured is 6 pt (402 pt, `.accessibility3`).
    static let placeholderMargin: CGFloat = 1

    public init(_ placeholder: String, short: String? = nil, text: String, onChange: @escaping (String) -> Void) {
        self.placeholder = placeholder
        self.short = short
        self.text = text
        self.onChange = onChange
    }

    public var body: some View {
        // The placeholder drawn: the whole one while it fits, else the short one.
        TextField(needed + Self.placeholderMargin <= room ? placeholder : short ?? placeholder, text: binding)
            .ledgerFieldFont(.body)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { room = $0 }
            .background(alignment: .leading) {
                Text(placeholder)
                    .ledgerFieldFont(.body)
                    .fixedSize()
                    .hidden()
                    .accessibilityHidden(true)
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { needed = $0 }
            }
            .foregroundStyle(LedgerColor.ink)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($isEditing)
            .padding(.horizontal, LedgerSpacing.l)
            .padding(.vertical, LedgerSpacing.s)
            .ledgerHitTarget(alignment: .leading)
            .onTapGesture { isEditing = true }
            .background {
                Capsule.ledgerPill.strokeBorder(LedgerColor.hairlineStrong, lineWidth: LedgerHairline.width)
            }
            .accessibilityLabel(placeholder)
    }

    /// The text as given, and a text that differs from it handed on as typed. The field writes its text back
    /// unchanged when it takes the focus and when it loses it; that is no change and hands on nothing.
    private var binding: Binding<String> {
        Binding { text } set: {
            if $0 != text {
                onChange($0)
            }
        }
    }
}
