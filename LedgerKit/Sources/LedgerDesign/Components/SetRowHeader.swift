import SwiftUI

/// The set grid's column headings (v2 "#", "lb", "reps"), aligned with the rows under them.
public struct SetRowHeader: View {
    private let number: String
    private let weight: String
    private let reps: String

    public init(number: String, weight: String, reps: String) {
        self.number = number
        self.weight = weight
        self.reps = reps
    }

    public var body: some View {
        HStack(spacing: LedgerSpacing.s) {
            SetColumns(label: heading(number), weight: heading(weight), reps: heading(reps))
            SetRowCheck(state: .pending).hidden()
        }
        .padding(.bottom, LedgerSpacing.s)
    }

    private func heading(_ text: String) -> some View {
        Text(text).ledgerFont(.caption).foregroundStyle(LedgerColor.inkMuted)
    }
}

/// The set grid (v2 `22px 1fr 1fr 42px`, gap 10) up to the check column: a label column sized in
/// ems of the caption role, then weight and reps sharing the rest. The header and the rows both
/// use it, followed by a check, so their columns line up at every text size.
struct SetColumns<Label: View, Weight: View, Reps: View>: View {
    /// The prototype's 22 px label column over its 12 px label.
    static var labelColumnEms: CGFloat {
        22.0 / 12
    }

    let label: Label
    let weight: Weight
    let reps: Reps
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let labelWidth = LedgerFont.scaledSize(.caption, dynamicTypeSize: dynamicTypeSize) * Self.labelColumnEms
        HStack(spacing: LedgerSpacing.s) {
            label.frame(width: labelWidth, alignment: .leading)
            weight.frame(maxWidth: .infinity, alignment: .leading)
            reps.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
