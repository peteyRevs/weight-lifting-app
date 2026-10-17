#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    import LedgerDesign
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// One way a lifter's phone can be set: the text size, the phone's width, Bold Text and the reading
    /// direction (F10 S5 criterion 10). Increase Contrast changes colours and no frame; a reference shows it.
    nonisolated struct LayoutSetting: Sendable, CustomTestStringConvertible {
        var size: DynamicTypeSize = .large
        var width: CGFloat = SnapshotConfig.phoneWidth
        var isBold = false
        var isRightToLeft = false

        /// An iPhone 17 and a 375 pt phone.
        static let widths: [CGFloat] = [narrowWidth, SnapshotConfig.phoneWidth]

        /// The narrower of the two phones.
        static let narrowWidth: CGFloat = 375

        /// Every setting of `size`: both widths, plain and bold, both directions, on every runner. For a test
        /// of a boundary between two arrangements, which a setting left out could move.
        static func everySetting(_ size: DynamicTypeSize) -> [LayoutSetting] {
            widths.flatMap { width in
                [false, true].flatMap { isBold in
                    [false, true].map { LayoutSetting(size: size, width: width, isBold: isBold, isRightToLeft: $0) }
                }
            }
        }

        /// `everySetting(size)`. On the hosted PR runner (`TestSweep`) two of the eight: the iPhone 17 plain,
        /// left to right, and the hardest of them, the 375 pt phone with Bold Text, right to left; mirroring
        /// breaks no line differently.
        static func sweep(_ size: DynamicTypeSize) -> [LayoutSetting] {
            TestSweep.subset(everySetting(size)) { setting in
                (setting.width == SnapshotConfig.phoneWidth && !setting.isBold && !setting.isRightToLeft)
                    || (setting.width == narrowWidth && setting.isBold && setting.isRightToLeft)
            }
        }

        var testDescription: String {
            "\(size) \(Int(width)) pt\(isBold ? " bold" : "")\(isRightToLeft ? " right-to-left" : "")"
        }

        /// `view` as this setting draws it, `width` wide. The reader hosts it at the iPhone 17's width, so a
        /// narrower phone is a narrower frame at its leading edge.
        @MainActor
        func applied(to view: some View, fixedWidth: Bool = true) -> some View {
            view
                .frame(width: fixedWidth ? width : nil)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .environment(\.legibilityWeight, isBold ? .bold : .regular)
                .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
        }

        @MainActor
        func elements(of view: some View, fixedWidth: Bool = true) -> [AccessibilityElementSnapshot] {
            applied(to: view, fixedWidth: fixedWidth).accessibilityElements(SnapshotAppearance(.light, size))
        }
    }

    /// A part of the page whose words must be drawn whole: the label VoiceOver reads for it, by which it is
    /// found on the page, and the same view by itself, to be measured with all the width it wants.
    struct LayoutPart {
        let label: String
        let alone: AnyView

        init(_ label: String, @ViewBuilder alone: () -> some View) {
            self.label = label
            self.alone = AnyView(alone())
        }
    }

    /// Words cut inside their own frame, by measurement and with no reference image (the idea of F11 S9's
    /// tester, `ProgramViewsCutAdversarialTests`): a part is measured by itself, with all the width it wants,
    /// and on the page. A part the page gives less width than it takes by itself must have grown taller for
    /// it, by wrapping; one that is narrower and no taller has lost words.
    enum WorkoutLayoutProbe {
        /// The parts of `parts` that `page` cuts in `setting`, one line each; a part the page does not hold
        /// is reported too, so a check can never pass on a part it did not find.
        static func cut(in page: some View, parts: [LayoutPart], _ setting: LayoutSetting) -> [String] {
            let drawn = setting.elements(of: page)
            return parts.compactMap { part in
                guard let onPage = drawn.first(where: { $0.label == part.label })?.frame.size else {
                    return "\"\(part.label)\" is not on the page"
                }
                let alone = setting.elements(of: part.alone.fixedSize(), fixedWidth: false)
                guard alone.count == 1, let whole = alone.first?.frame.size else {
                    return "\"\(part.label)\" by itself is \(alone.count) stops, not one"
                }
                let isNarrower = onPage.width < whole.width - 0.5
                let isNoTaller = onPage.height <= whole.height + 0.5
                return isNarrower && isNoTaller ? "\"\(part.label)\" takes \(whole), and is given \(onPage)" : nil
            }
        }

        /// The stops of `page` that leave the phone or lie over one another in `setting`, one line each.
        static func misplaced(in page: some View, _ setting: LayoutSetting) -> [String] {
            let drawn = setting.elements(of: page)
            // Right to left the narrower phone's frame stands at the other edge of the reader's host.
            let lead = setting.isRightToLeft ? SnapshotConfig.phoneWidth - setting.width : 0
            var found = drawn.compactMap { element -> String? in
                let frame = element.frame
                let isInside = frame.minX >= lead - 0.5 && frame.maxX <= lead + setting.width + 0.5
                return isInside && frame.width > 0 && frame.height > 0 ? nil : "\"\(element.label)\" is at \(frame)"
            }
            for (index, first) in drawn.enumerated() {
                for second in drawn.dropFirst(index + 1) {
                    let overlap = first.frame.intersection(second.frame)
                    if !overlap.isNull, overlap.width >= 1, overlap.height >= 1 {
                        found.append("\"\(first.label)\" lies over \"\(second.label)\"")
                    }
                }
            }
            return found
        }

        /// The parts of a page's card and of its list whose words this module lays out: the place, the name,
        /// the two facts, "Repeat", "+ Add set" and each remaining exercise. The set rows and the steppers are
        /// `LedgerDesign`'s, which shrinks a numeral that is too long for its column by design.
        static func parts(of model: WorkoutPageModel) -> [LayoutPart] {
            var parts: [LayoutPart] = []
            if let card = model.card {
                parts.append(LayoutPart(card.eyebrow) { Text(card.eyebrow).ledgerFont(.caption) })
                parts.append(LayoutPart(card.title) { Text(card.title).ledgerFont(.heading) })
                parts.append(LayoutPart("\(card.targetLabel), \(card.target)") {
                    FactLine(label: card.targetLabel, value: card.target)
                })
                parts.append(LayoutPart("\(card.lastLabel), \(card.last)") {
                    FactLine(label: card.lastLabel, value: card.last)
                })
                if let title = card.repeatLast {
                    parts.append(LayoutPart(title) { PillButton(title) {} })
                }
                parts.append(LayoutPart(card.addSet) { PillButton(card.addSet, style: .ghost, flush: .leading) {} })
            }
            for row in model.remaining?.rows ?? [] {
                parts.append(LayoutPart("\(row.name), \(row.scheme)") {
                    HairlineRow(row.name, action: {}, accessory: { Text(row.scheme).ledgerFont(.caption) })
                })
            }
            return parts
        }
    }
#endif
