import SwiftUI

/// The switch of a form (the Day editor's "Drop set"; Settings): the toggle's label, then a track with a
/// knob. Use it as `.toggleStyle(.ledger)`.
///
/// On, the track is filled with ink and the knob is the ground's colour; off, the track is an outline and
/// the knob a muted ink. No orange: the accent is kept for the one thing a screen is about (Pete's decision 1
/// of F11). The state is told by the knob's side as well as by the fill, and every part is an ink token, so
/// both read on either theme and step up under Increase Contrast.
///
/// The whole row is the tap target, at least 44 pt high. To VoiceOver it is SwiftUI's own switch: the label,
/// the value on or off, the switch's traits and its double-tap, taken from a system toggle with the same
/// label and binding.
public struct LedgerToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        LedgerToggle(configuration: configuration)
    }
}

public extension ToggleStyle where Self == LedgerToggleStyle {
    /// The form switch of the design system: an ink track, no accent.
    static var ledger: LedgerToggleStyle {
        LedgerToggleStyle()
    }
}

/// The style's body, a view of its own so that it can read the environment.
private struct LedgerToggle: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : LedgerMotion.snappy) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: LedgerSpacing.m) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                LedgerToggleTrack(isOn: configuration.isOn)
            }
            .ledgerHitTarget()
        }
        .buttonStyle(LedgerPressStyle())
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }
}

/// The track and its knob. It keeps its size at every text size: it holds no text.
private struct LedgerToggleTrack: View {
    /// The prototype's switch: a 52 × 32 pt track, a 26 pt knob, 3 pt from the track's edge.
    static let size = CGSize(width: 52, height: 32)
    static let knob: CGFloat = 26

    let isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Circle()
            .fill(LedgerToggleLook.knob(isOn: isOn, isEnabled: isEnabled))
            .frame(width: Self.knob, height: Self.knob)
            .padding((Self.size.height - Self.knob) / 2)
            .frame(width: Self.size.width, height: Self.size.height, alignment: isOn ? .trailing : .leading)
            .background { track }
            .accessibilityHidden(true)
    }

    /// Filled when on, an outline when off.
    @ViewBuilder private var track: some View {
        let color = LedgerToggleLook.track(isOn: isOn, isEnabled: isEnabled)
        if isOn {
            Capsule.ledgerPill.fill(color)
        } else {
            Capsule.ledgerPill.strokeBorder(color, lineWidth: LedgerHairline.width)
        }
    }
}

/// The switch's colours, apart from its views so that the contrast tests read the same ones. On, the knob
/// stands on the track's fill; off, on the ground inside the track's outline.
nonisolated enum LedgerToggleLook {
    static func knob(isOn: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else {
            return isOn ? LedgerColor.inkMuted : LedgerColor.inkFaint
        }
        return isOn ? LedgerColor.ground : LedgerColor.inkMuted
    }

    /// The fill when on, the outline when off.
    static func track(isOn: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else {
            return LedgerColor.hairline
        }
        return isOn ? LedgerColor.ink : LedgerColor.hairlineStrong
    }
}

/// Every state, for the preview, the snapshot tests and the gallery: off, on, a label of two lines, and
/// each state disabled.
struct LedgerToggleGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
            toggle("Drop set", isOn: false)
            toggle("Drop set", isOn: true)
            Toggle(isOn: .constant(true)) {
                VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
                    Text("Drop set").ledgerFont(.body).foregroundStyle(LedgerColor.ink)
                    Text("One extra set at −15%, straight after the last working set.")
                        .ledgerFont(.label)
                        .foregroundStyle(LedgerColor.inkMuted)
                }
            }
            toggle("Keep the screen awake", isOn: false).disabled(true)
            toggle("Keep the screen awake", isOn: true).disabled(true)
        }
        .toggleStyle(.ledger)
    }

    private func toggle(_ title: String, isOn: Bool) -> some View {
        Toggle(isOn: .constant(isOn)) {
            Text(title).ledgerFont(.body).foregroundStyle(LedgerColor.ink)
        }
    }
}
