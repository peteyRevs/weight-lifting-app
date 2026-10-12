import LedgerDesign
import SwiftUI

/// The rest panel (v2 "Active workout", the floating card): the ring with the time left, "Resting" or
/// "Rest over" over the set that comes next, and "+30s" beside "Skip rest". `WorkoutScreen` floats it over
/// the page's end while the workout shows a rest; it stays at "0:00" and "Rest over" until "+30s", "Skip
/// rest" or the next logged set takes it away (decision #7).
///
/// It draws the model and reads no clock: the store hands the presentation the injected date at each
/// second of the rest, and the model is the rest at that moment. Between two seconds the ring's arc moves
/// to its new place over the second; with Reduce Motion it steps there, with the digits.
///
/// The panel's one orange button is "Skip rest"; the ring's arc is the design system's. VoiceOver reads the
/// ring and the two lines as one stop: "Resting" and the next set, with the time left as its value, in
/// words, marked as updating often so that it is not spoken at every second; then the two buttons.
///
/// **At the accessibility sizes the panel is compact** (F10 S6, criterion 17), so that the page still
/// shows between the header and the panel on a small phone: no ring, the time left as text beside
/// "Resting" or "Rest over", the next set under them, and the two buttons side by side where their words
/// fit whole, else one over the other. At the largest size of all the next set is not drawn either
/// (VoiceOver still reads it): on a 375 pt phone with a home button it is what leaves the page 120 pt.
/// Nothing is cut, and both buttons stay 44 pt targets.
struct RestPanel: View {
    let model: RestPanelModel
    let send: (WorkoutAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// How the ring's arc goes from one second's place to the next: over that second; at once with Reduce
    /// Motion, and at once when the rest is over, so that the arc is gone when "0:00" and "Rest over" are
    /// read and does not drain for a second after them.
    static func ringAnimation(reduceMotion: Bool, isOver: Bool) -> Animation? {
        reduceMotion || isOver ? nil : .linear(duration: 1)
    }

    var body: some View {
        let isCompact = dynamicTypeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            // The arc moves over the second; the digits and the words change at once, without a fade.
            RestReading(model: model)
                .contentTransition(.identity)
                .animation(Self.ringAnimation(reduceMotion: reduceMotion, isOver: model.isOver), value: model.fraction)
                .accessibilityIdentifier("workout.rest.status")
            Group {
                if isCompact {
                    // Side by side where both words fit on one line each, "Skip rest" at its own width and
                    // "+30s" in what is left (two halves would wrap the longer word); else one over the other.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: LedgerSpacing.s) {
                            extend
                            skip.fixedSize(horizontal: true, vertical: false)
                        }
                        VStack(spacing: LedgerSpacing.s) {
                            extend
                            skip
                        }
                    }
                } else {
                    HStack(spacing: LedgerSpacing.m) {
                        extend
                        skip
                    }
                }
            }
            .disabled(!model.isEnabled)
        }
        .padding(LedgerSpacing.l)
        .background(LedgerColor.surface, in: .rect(cornerRadius: LedgerRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: LedgerRadius.card)
                .strokeBorder(LedgerColor.hairlineStrong, lineWidth: LedgerHairline.width)
        }
        .accessibilityElement(children: .contain)
    }

    /// "+30s", read by what it does.
    private var extend: some View {
        PillButton(model.extend, fillsWidth: true) { send(.edit(.extendRest)) }
            .accessibilityLabel(Text(verbatim: model.extendLabel))
            .accessibilityIdentifier("workout.rest.extend")
    }

    private var skip: some View {
        PrimaryButton(model.skip) { send(.edit(.skipRest)) }
            .accessibilityIdentifier("workout.rest.skip")
    }
}

/// The ring with the time left, and beside it "Resting" or "Rest over" over the set that comes next: one
/// stop for VoiceOver, whose value is the time left in words. At the accessibility sizes there is no ring:
/// the time left is text, on one line with "Resting" or "Rest over", and the next set is under them, but
/// at the largest size, where it is left to VoiceOver. A line too long for its place wraps; it is never
/// cut.
struct RestReading: View {
    let model: RestPanelModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: LedgerSpacing.s) {
                        Text(model.clock)
                            .ledgerFont(.numeralS)
                            .foregroundStyle(LedgerColor.ink)
                            .fixedSize()
                        status
                    }
                    if dynamicTypeSize < .accessibility5 {
                        nextSet
                    }
                }
            } else {
                HStack(spacing: LedgerSpacing.l) {
                    RestRing(progress: model.fraction, label: model.clock)
                    VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                        status
                        nextSet
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spokenLabel))
        .accessibilityValue(Text(verbatim: model.spokenTime))
        .accessibilityAddTraits(model.isOver ? [] : .updatesFrequently)
    }

    private var status: some View {
        Text(model.status)
            .ledgerFont(.caption)
            .foregroundStyle(LedgerColor.inkMuted)
    }

    @ViewBuilder private var nextSet: some View {
        if let next = model.next {
            Text(next.line)
                .ledgerFont(.body)
                .foregroundStyle(LedgerColor.ink)
        }
    }

    /// "Resting, Set 3, 180 pounds, 5 reps".
    private var spokenLabel: String {
        [model.status, model.next?.spoken].compactMap(\.self).joined(separator: ", ")
    }
}
