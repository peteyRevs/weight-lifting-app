import SwiftUI

/// The orange pill: the one accent-filled action on a screen (spec §8.4), full width and at least
/// 54 pt tall (v2 "Start workout": 16 px label, 19 px padding, optional arrow). Disabled, it turns
/// grey (v1 "Select exercises to add": ink .10 fill).
///
/// `title` is shown as given; features pass copy from their string catalog. A label that changes by
/// itself (v2 "Resume workout · 12:48", a `Text` that holds a timer) is passed as a `Text`. Such a
/// button can be given a fixed line for VoiceOver to read in the label's place; without one VoiceOver
/// reads the label as it stands when the button gets focus.
public struct PrimaryButton: View {
    /// Spec §8.6: "primary CTA height ≈ 54 px".
    static let minimumHeight: CGFloat = 54

    private let label: Text
    private let spoken: String?
    private let icon: LedgerIcon?
    private let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    public init(_ title: String, icon: LedgerIcon? = nil, action: @escaping () -> Void) {
        label = Text(title)
        spoken = nil
        self.icon = icon
        self.action = action
    }

    /// A button whose label is a `Text` the caller built, such as one that counts with
    /// `Text(timerInterval:)`. `accessibilityLabel` is what VoiceOver reads in its place; nil leaves the
    /// label to be read as drawn, and the element as SwiftUI marks it (one that holds a timer updates
    /// frequently). A line that is empty or only white space is no line: it is treated as nil, so the
    /// button is never one VoiceOver reads as nothing.
    public init(
        label: Text,
        accessibilityLabel: String? = nil,
        icon: LedgerIcon? = nil,
        action: @escaping () -> Void
    ) {
        self.label = label
        let line = accessibilityLabel ?? ""
        spoken = line.allSatisfy(\.isWhitespace) ? nil : line
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        if let spoken {
            // A `Text` that holds a timer marks its element as updating frequently. What VoiceOver reads
            // here is the fixed line, which does not update.
            button
                .accessibilityLabel(Text(verbatim: spoken))
                .accessibilityRemoveTraits(.updatesFrequently)
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: LedgerSpacing.s) {
                label
                    .ledgerFont(.button)
                    .multilineTextAlignment(.center)
                if let icon {
                    LedgerIconView(icon, sizedAs: .button)
                }
            }
            .foregroundStyle(isEnabled ? LedgerColor.onAccent : LedgerColor.inkMuted)
            .padding(.horizontal, LedgerSpacing.xl)
            .padding(.vertical, LedgerSpacing.m)
            .frame(maxWidth: .infinity, minHeight: Self.minimumHeight)
            .background(isEnabled ? LedgerColor.accent : LedgerColor.hairline, in: .ledgerPill)
            .contentShape(.ledgerPill)
        }
        .buttonStyle(LedgerPressStyle())
    }
}

/// Every state, for the preview, the snapshot tests and the gallery.
struct PrimaryButtonGallery: View {
    var body: some View {
        VStack(spacing: LedgerSpacing.xl) {
            PrimaryButton("Start workout", icon: .arrow) {}
            PrimaryButton("Resume workout · 12:48") {}
            PrimaryButton("Save workout") {}.disabled(true)
        }
    }
}

/// A label that counts, frozen so that it draws the same every time, for the preview and the snapshot
/// tests: enabled with its arrow, and disabled.
struct PrimaryButtonTimerGallery: View {
    /// Any fixed moment: the label shows the time from it to `pause`.
    static let start = Date(timeIntervalSinceReferenceDate: 0)
    /// 12 minutes 48 seconds later.
    static let pause = start.addingTimeInterval(768)

    var body: some View {
        VStack(spacing: LedgerSpacing.xl) {
            PrimaryButton(label: Self.elapsed, accessibilityLabel: "Resume workout", icon: .arrow) {}
            PrimaryButton(label: Self.elapsed, accessibilityLabel: "Resume workout") {}.disabled(true)
        }
    }

    /// "12:48", counting up from `start` and stopped at `pause`.
    static var elapsed: Text {
        Text(timerInterval: start ... .distantFuture, pauseTime: pause, countsDown: false)
    }
}
