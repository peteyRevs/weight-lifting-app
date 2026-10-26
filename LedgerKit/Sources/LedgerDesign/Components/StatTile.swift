import SwiftUI

/// One number with a caption (v2 Today "3/4 sessions this week", "41.2k lb moved · +8%"; Exercise
/// history "195×5 best set"): the value in the heavy narrow numerals, an optional light `unit` after
/// it, the caption under it and an optional orange `delta` after the caption. `isValueAccented` draws the
/// value in orange (`accentText`), as v2 draws Exercise history's "1RM est" (F12 S2, Pete's question 3).
/// Tiles sit side by side, each taking an equal share of the row.
///
/// VoiceOver reads the tile as one element: `accessibilitySummary` if given ("3 of 4 sessions this
/// week"), else the strings as shown ("3/4, sessions this week"). Strings are shown as given;
/// features pass copy from their catalog.
public struct StatTile: View {
    /// v2 Today: the unit is 300 19 px beside the 700 34 px value (Exercise history's 15 beside 30 is
    /// close), so it scales with the value's text size and Bold Text.
    static let unitEms: CGFloat = 19.0 / 34

    private let value: String
    private let unit: String?
    private let caption: String
    private let delta: String?
    private let summary: String?
    private let isValueAccented: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight

    public init(
        value: String,
        unit: String? = nil,
        caption: String,
        delta: String? = nil,
        accessibilitySummary: String? = nil,
        isValueAccented: Bool = false
    ) {
        self.value = value
        self.unit = unit
        self.caption = caption
        self.delta = delta
        summary = accessibilitySummary
        self.isValueAccented = isValueAccented
    }

    public var body: some View {
        let valueSize = LedgerFont.scaledSize(.numeralXL, dynamicTypeSize: dynamicTypeSize)
        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
            Text(Self.valueLine(value, unit: unit, valueSize: valueSize, legibilityWeight: legibilityWeight))
                .ledgerFont(.numeralXL)
                .foregroundStyle(isValueAccented ? LedgerColor.accentText : LedgerColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5) // a long value at the largest text sizes shrinks rather than breaks
            Text(captionLine)
                .ledgerFont(.label)
                .foregroundStyle(LedgerColor.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: summary ?? spoken))
    }

    /// The value, then the unit as a run in `bodyLight` at 19/34 of the value's size, `inkMuted` (the
    /// prototype's .32 is below AA) and its role's own tracking, not the numerals'. One line, so the unit
    /// sits on the value's baseline and the value's line box alone sets the height: every tile's caption
    /// is the same distance below its number, unit or not.
    static func valueLine(
        _ value: String,
        unit: String?,
        valueSize: CGFloat,
        legibilityWeight: LegibilityWeight?
    ) -> AttributedString {
        var line = AttributedString(value)
        if let unit {
            let unitSize = valueSize * Self.unitEms
            var small = AttributedString(unit)
            small.font = LedgerFont.font(.bodyLight, size: unitSize, legibilityWeight: legibilityWeight)
            small.tracking = LedgerFont.Role.bodyLight.spec.tracking * unitSize
            small.foregroundColor = LedgerColor.inkMuted
            line += small
        }
        return line
    }

    /// The caption, then " · " and the delta in orange (`accentText`, AA on paper too).
    private var captionLine: AttributedString {
        var line = AttributedString(caption)
        if let delta {
            var accent = AttributedString(delta)
            accent.foregroundColor = LedgerColor.accentText
            line += AttributedString(" · ") + accent
        }
        return line
    }

    private var spoken: String {
        ["\(value)\(unit ?? "")", caption, delta].compactMap(\.self).joined(separator: ", ")
    }
}

/// Stat tiles side by side, each an equal share of the row (v2: two on Today, three on Exercise
/// history). At accessibility text sizes they stack, so no caption has to break inside a word (HIG,
/// Typography: reduce the number of columns as the text grows).
public struct StatTileRow<Content: View>: View {
    private let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LedgerSpacing.l))
            : AnyLayout(HStackLayout(alignment: .top, spacing: LedgerSpacing.xl))
        layout {
            content
        }
    }
}

/// Today's two tiles and Exercise history's three, for the preview, the snapshot tests and the
/// gallery.
struct StatTileGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.xl) {
            StatTileRow {
                StatTile(value: "3", unit: "/4", caption: "sessions this week")
                StatTile(value: "41.2", unit: "k", caption: "lb moved", delta: "+8%")
            }
            StatTileRow {
                StatTile(value: "218", caption: "1RM est", isValueAccented: true)
                StatTile(value: "195", unit: "×5", caption: "best set")
                StatTile(value: "34", caption: "sessions")
            }
        }
    }
}
