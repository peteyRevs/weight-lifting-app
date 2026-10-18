import SwiftUI

/// The receipt of a finished workout (v1 "Session receipt"), under its screen's header: three tiles (the
/// time, the sets, the weight moved), the records line when there is one, then "LOGGED" over one row for
/// each exercise: its name, what was prescribed at the trailing edge, and a chip for each run of logged
/// sets. F10's cover draws it after a save; F13's workout detail reuses it.
///
/// String-only: the model holds final strings, formatted and localised by the caller, and this view
/// decides nothing about a workout. A tile whose `isAccented` is set has its label in orange (the
/// prototype's "TIME"), and so has the records line; nothing on it is a control.
///
/// At accessibility text sizes the tiles stand one per row, the note beside "LOGGED" goes under it, and a
/// row's target stands under its name, so no word has to break. A tile's value stays on one line and
/// shrinks rather than wrap ("1,234,567"). Chips wrap (`WrapLayout`).
///
/// VoiceOver reads each tile as one stop (its `spoken`, "TIME, 24 minutes, 22 seconds"), the records line,
/// "LOGGED" as a heading, then each row as one stop (its `spoken`). The note beside "LOGGED" describes the
/// picture and is hidden from VoiceOver.
public struct ReceiptLayout: View {
    /// Everything the receipt shows, in order.
    public nonisolated struct Model: Equatable, Sendable {
        public let tiles: [Tile]
        /// "1 new PR this session"; nil draws no line.
        public let records: String?
        /// "LOGGED", the rows' heading.
        public let logged: String
        /// "Prescribed on the right": drawn, never spoken.
        public let note: String
        public let rows: [Row]

        public init(tiles: [Tile], records: String?, logged: String, note: String, rows: [Row]) {
            self.tiles = tiles
            self.records = records
            self.logged = logged
            self.note = note
            self.rows = rows
        }
    }

    /// One number with its label above it: "TIME" over "24:22".
    public nonisolated struct Tile: Equatable, Sendable {
        public let label: String
        public let value: String
        /// The whole tile as VoiceOver reads it.
        public let spoken: String
        /// The label is orange.
        public let isAccented: Bool

        public init(label: String, value: String, spoken: String, isAccented: Bool = false) {
            self.label = label
            self.value = value
            self.spoken = spoken
            self.isAccented = isAccented
        }
    }

    /// One exercise: its name, its target ("5 × 5 @ 185 lb") and its chips ("5 × 185×5", "185×4", "—").
    public nonisolated struct Row: Equatable, Sendable {
        public let name: String
        public let target: String
        public let chips: [String]
        /// The whole row as VoiceOver reads it.
        public let spoken: String

        public init(name: String, target: String, chips: [String], spoken: String) {
            self.name = name
            self.target = target
            self.chips = chips
            self.spoken = spoken
        }
    }

    private let model: Model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(model: Model) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            tiles
            if let records = model.records {
                Text(records)
                    .ledgerFont(.caption)
                    .foregroundStyle(LedgerColor.accentText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                loggedHeader
                rows
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isStacked: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var tiles: some View {
        let layout = isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LedgerSpacing.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: LedgerSpacing.s))
        return layout {
            ForEach(Array(model.tiles.enumerated()), id: \.offset) { _, tile in
                ReceiptTile(tile: tile)
            }
        }
        // Side by side, every tile is as tall as the tallest.
        .fixedSize(horizontal: false, vertical: true)
    }

    private var loggedHeader: some View {
        let layout = isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LedgerSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: LedgerSpacing.m))
        return layout {
            Eyebrow(model.logged)
                .frame(maxWidth: isStacked ? nil : .infinity, alignment: .leading)
            Text(model.note)
                .ledgerFont(.caption)
                .foregroundStyle(LedgerColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.rows.enumerated()), id: \.offset) { place, row in
                if place > 0 {
                    HairlineRule()
                }
                ReceiptRowView(row: row, isStacked: isStacked)
            }
        }
        .padding(.horizontal, LedgerSpacing.l)
        .background(LedgerColor.surface, in: RoundedRectangle(cornerRadius: LedgerRadius.card))
    }
}

/// One tile: the label over the value, on the raised surface.
private struct ReceiptTile: View {
    let tile: ReceiptLayout.Tile

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
            Text(tile.label)
                .ledgerFont(.eyebrow)
                .foregroundStyle(tile.isAccented ? LedgerColor.accentText : LedgerColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Text(tile.value)
                .ledgerFont(.numeralM)
                .foregroundStyle(LedgerColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5) // a long value shrinks rather than breaks or is cut
        }
        .padding(.vertical, LedgerSpacing.l)
        .padding(.horizontal, LedgerSpacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LedgerColor.surface, in: RoundedRectangle(cornerRadius: LedgerRadius.row))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: tile.spoken))
    }
}

/// One exercise of the receipt: the name and the target on a line (the target under the name when
/// `isStacked`), then the chips.
private struct ReceiptRowView: View {
    let row: ReceiptLayout.Row
    let isStacked: Bool

    var body: some View {
        let line = isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LedgerSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: LedgerSpacing.m))
        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
            line {
                Text(row.name)
                    .ledgerFont(.body)
                    .foregroundStyle(LedgerColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: isStacked ? nil : .infinity, alignment: .leading)
                Text(row.target)
                    .ledgerFont(.caption)
                    .foregroundStyle(LedgerColor.inkMuted)
                    .fixedSize(horizontal: !isStacked, vertical: true)
            }
            WrapLayout {
                ForEach(Array(row.chips.enumerated()), id: \.offset) { _, chip in
                    Text(chip)
                        .ledgerFont(.caption)
                        .foregroundStyle(LedgerColor.ink)
                        .padding(.horizontal, LedgerSpacing.s)
                        .padding(.vertical, LedgerSpacing.xs)
                        .background(LedgerColor.ground, in: .ledgerPill)
                }
            }
        }
        .padding(.vertical, LedgerSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: row.spoken))
    }
}

/// A receipt with a record and an exercise with nothing logged, for the preview, the snapshot tests and
/// the gallery.
struct ReceiptLayoutGallery: View {
    nonisolated static let model = ReceiptLayout.Model(
        tiles: [
            ReceiptLayout.Tile(label: "TIME", value: "24:22", spoken: "TIME, 24 minutes, 22 seconds", isAccented: true),
            ReceiptLayout.Tile(label: "SETS", value: "23/25", spoken: "23 of 25 sets logged"),
            ReceiptLayout.Tile(label: "LB MOVED", value: "24,180", spoken: "24,180 lb moved")
        ],
        records: "1 new PR this session",
        logged: "LOGGED",
        note: "Prescribed on the right",
        rows: [
            ReceiptLayout.Row(
                name: "Bench Press",
                target: "5 × 5 @ 185 lb",
                chips: ["4 × 185×5", "185×4"],
                spoken: "Bench Press, Prescribed 5 × 5 @ 185 lb, Logged 4 × 185×5, 185×4"
            ),
            ReceiptLayout.Row(
                name: "Barbell Row",
                target: "4 × 8 @ 135 lb",
                chips: ["4 × 135×8"],
                spoken: "Barbell Row, Prescribed 4 × 8 @ 135 lb, Logged 4 × 135×8"
            ),
            ReceiptLayout.Row(
                name: "Incline Dumbbell Press",
                target: "3 × 10 @ 50 lb",
                chips: ["—"],
                spoken: "Incline Dumbbell Press, Prescribed 3 × 10 @ 50 lb, Nothing logged"
            )
        ]
    )

    var body: some View {
        ReceiptLayout(model: Self.model)
    }
}
