import SwiftUI

/// A search field: an outlined pill, at least 44 pt high and with `s` above and below its line of text at every
/// size, that holds `text` and hands each change on as typed. Its placeholder is its spoken label too. A tap
/// anywhere on the pill puts the cursor in the field, which by itself is only as high as its line of text.
/// String-only: the caller holds the text (F11's exercise library, F12's Library).
public struct SearchField: View {
    private let placeholder: String
    private let text: String
    private let onChange: (String) -> Void
    @FocusState private var isEditing: Bool

    public init(_ placeholder: String, text: String, onChange: @escaping (String) -> Void) {
        self.placeholder = placeholder
        self.text = text
        self.onChange = onChange
    }

    public var body: some View {
        TextField(placeholder, text: binding)
            .ledgerFieldFont(.body)
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
