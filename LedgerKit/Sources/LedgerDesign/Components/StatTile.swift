import SwiftUI

/// One number with a caption (v2 Today "3/4 sessions this week", "41.2k lb moved · +8%"; Exercise
/// history "195×5 best set"): the value in the heavy narrow numerals, an optional light `unit` after
/// it, the caption under it and an optional orange `delta` after the caption. Tiles sit side by side,
/// each taking an equal share of the row.
///
/// VoiceOver reads the tile as one element: `accessibilitySummary` if given ("3 of 4 sessions this
/// week"), else the strings as shown ("3/4, sessions this week"). Strings are shown as given;
/// features pass copy from their catalog.
public struct StatTile: View {
    private let value: String
    private let unit: String?
    private let caption: String
    private let delta: String?
    private let summary: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight

    public init(
        value: String,
        unit: String? = nil,
        caption: String,
        delta: String? = nil,
        accessibilitySummary: String? = nil
    ) {
        self.value = value
        self.unit = unit
        self.caption = caption
        self.delta = delta
        summary = accessibilitySummary
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
            Text(valueLine)
                .ledgerFont(.numeralXL)
                .foregroundStyle(LedgerColor.ink)
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

    /// The value, then the unit as a run in `bodyLight` and `inkMuted` (the prototype's .32 is below AA).
    /// One line, so the unit sits on the value's baseline and the value's line box alone sets the
    /// height: every tile's caption is the same distance below its number, unit or not.
    private var valueLine: AttributedString {
        var line = AttributedString(value)
        if let unit {
            var small = AttributedString(unit)
            small.font = LedgerFont.font(
                .bodyLight,
                dynamicTypeSize: dynamicTypeSize,
                legibilityWeight: legibilityWeight
            )
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
                StatTile(value: "218", caption: "1RM est")
                StatTile(value: "195", unit: "×5", caption: "best set")
                StatTile(value: "34", caption: "sessions")
            }
        }
    }
}
