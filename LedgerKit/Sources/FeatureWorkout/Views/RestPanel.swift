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
/// At the accessibility sizes the lines stand under the ring and the buttons one over the other, where a
/// row would cut them.
struct RestPanel: View {
    let model: RestPanelModel
    let send: (WorkoutAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// How the ring's arc goes from one second's place to the next: over that second, or at once with
    /// Reduce Motion.
    static func ringAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .linear(duration: 1)
    }

    var body: some View {
        let buttons = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: LedgerSpacing.s))
            : AnyLayout(HStackLayout(spacing: LedgerSpacing.m))
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            // The arc moves over the second; the digits and the words change at once, without a fade.
            RestReading(model: model)
                .contentTransition(.identity)
                .animation(Self.ringAnimation(reduceMotion: reduceMotion), value: model.fraction)
                .accessibilityIdentifier("workout.rest.status")
            buttons {
                PillButton(model.extend, fillsWidth: true) { send(.edit(.extendRest)) }
                    .accessibilityLabel(Text(verbatim: model.extendLabel))
                    .accessibilityIdentifier("workout.rest.extend")
                PrimaryButton(model.skip) { send(.edit(.skipRest)) }
                    .accessibilityIdentifier("workout.rest.skip")
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
}

/// The ring with the time left, and beside it "Resting" or "Rest over" over the set that comes next: one
/// stop for VoiceOver, whose value is the time left in words. Side by side, and one over the other at the
/// accessibility sizes. A line too long for its place wraps; it is never cut.
struct RestReading: View {
    let model: RestPanelModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LedgerSpacing.m))
            : AnyLayout(HStackLayout(spacing: LedgerSpacing.l))
        layout {
            RestRing(progress: model.fraction, label: model.clock)
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                Text(model.status)
                    .ledgerFont(.caption)
                    .foregroundStyle(LedgerColor.inkMuted)
                if let next = model.next {
                    Text(next.line)
                        .ledgerFont(.body)
                        .foregroundStyle(LedgerColor.ink)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spokenLabel))
        .accessibilityValue(Text(verbatim: model.spokenTime))
        .accessibilityAddTraits(model.isOver ? [] : .updatesFrequently)
    }

    /// "Resting, Set 3, 180 pounds, 5 reps".
    private var spokenLabel: String {
        [model.status, model.next?.spoken].compactMap(\.self).joined(separator: ", ")
    }
}
