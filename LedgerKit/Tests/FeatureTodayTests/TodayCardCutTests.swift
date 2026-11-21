#if os(iOS) && DEBUG
    @testable import FeatureToday
    import LedgerDesign
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// The card of a workout in progress (Resume) and of today's workout already done (View session), checked for
    /// words cut at every text size, as Workout's `WorkoutLayoutProbe.cut` and Program's
    /// `ProgramViewsCutAdversarialTests` check theirs, by measurement and with no reference image. Each part of the
    /// card is measured by itself, with all the width it wants, and on the page. A part that gets less width on the
    /// page than it takes by itself must be taller there, because it wrapped. A part that is narrower and no taller
    /// has lost words.
    ///
    /// `TodayViewsLayoutAdversarialTests` already lays these two states out at every text size (no stop empty,
    /// outside the page, under 44 pt or over another), and the UI test `DynamicType` clip-audits Up next and the rest
    /// day at Accessibility XXXL; neither looked inside a part's frame for a cut.
    @Suite("Today card: Resume and View session keep their words", .serialized, .tags(.feature))
    struct TodayCardCutTests {
        /// Every text size. On the hosted PR runner (`TestSweep`) the representative sizes, `.xxxLarge` and
        /// `.accessibility5` among them.
        nonisolated static let sizes = TestSweep.sizes(DynamicTypeSize.allCases)

        /// The two cards' states.
        nonisolated static let previews: [TodayPreview] = [.resume, .logged]

        /// A phone's width and Bold Text, left to right: mirroring breaks no line differently, and the reader gives
        /// a mirrored frame a few points less than it measures (Workout's `ReceiptLoggedCutAdversarialTests`).
        struct Setting: CustomStringConvertible {
            let size: DynamicTypeSize
            let width: CGFloat
            let isBold: Bool

            /// An iPhone 17 and a 375 pt phone, plain and bold. On the hosted PR runner (`TestSweep`) the iPhone 17
            /// plain and the hardest, the 375 pt phone bold.
            static func sweep(_ size: DynamicTypeSize) -> [Setting] {
                let all = [375, SnapshotConfig.phoneWidth].flatMap { width in
                    [false, true].map { Setting(size: size, width: width, isBold: $0) }
                }
                return TestSweep.subset(all) { $0.width == 375 ? $0.isBold : !$0.isBold }
            }

            var description: String {
                "\(size) \(Int(width)) pt\(isBold ? " bold" : "")"
            }

            /// The stops of `view` in this setting; `width` wide, or as wide as it wants.
            func elements(of view: some View, fixedWidth: Bool = true) -> [AccessibilityElementSnapshot] {
                view
                    .frame(width: fixedWidth ? width : nil)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .environment(\.legibilityWeight, isBold ? .bold : .regular)
                    .accessibilityElements(SnapshotAppearance(.light, size))
            }
        }

        /// A part of the card: the label VoiceOver reads for it, by which it is found on the page, and the same view
        /// by itself.
        struct Part {
            let label: String
            let alone: AnyView

            init(_ label: String, @ViewBuilder alone: () -> some View) {
                self.label = label
                self.alone = AnyView(alone())
            }
        }

        /// The parts of `page` it cuts in `setting`, one line each; a part the page does not hold is reported too,
        /// so that the check never passes on a part it did not find.
        static func cut(in page: some View, parts: [Part], _ setting: Setting) -> [String] {
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

        /// Every part of the card of `preview` that holds words, each drawn as the card draws it.
        static func parts(of preview: TodayPreview) throws -> [Part] {
            let model = try preview.model().card
            if let card = model.upNext {
                guard case let .resume(_, startedAt) = card.action else {
                    throw TodayPreviewData.Unreadable()
                }
                var parts = [Part(card.eyebrow) { Eyebrow(card.eyebrow, tint: .accent) }]
                if let meta = card.meta {
                    parts.append(Part(meta) { Text(meta).ledgerFont(.caption) })
                }
                parts.append(Part(card.title) { Text(card.title).ledgerFont(.heading) })
                parts += card.rows.map { row in
                    Part("\(row.name), \(row.scheme)") {
                        HairlineRow(row.name) { Text(row.scheme).ledgerFont(.numeralS) }
                    }
                }
                let resume = TodayCopy.resume(since: startedAt, pausedAt: preview.now)
                parts.append(Part(TodayCopy.resumeWorkout) {
                    PrimaryButton(label: resume, accessibilityLabel: TodayCopy.resumeWorkout, icon: .arrow) {}
                })
                return parts
            }
            let logged = try #require(model.logged, "\(preview.rawValue) draws neither card")
            var parts = [
                Part(logged.eyebrow) { Eyebrow(logged.eyebrow) },
                Part(logged.elapsed) { Text(logged.elapsed).ledgerFont(.caption) },
                Part(logged.title) { Text(logged.title).ledgerFont(.heading) },
                Part(logged.stats) { Text(logged.stats).ledgerFont(.bodyLight) },
                Part(logged.action.title) { PillButton(logged.action.title, flush: .leading) {} }
            ]
            if let next = logged.next {
                parts.append(Part(next) { Text(next).ledgerFont(.label) })
            }
            return parts
        }

        @Test(
            "Resume and View session: no word of the card is cut, at every text size, on two phones, plain and bold",
            arguments: previews,
            sizes
        )
        func card_keepsItsWords(_ preview: TodayPreview, _ size: DynamicTypeSize) throws {
            let parts = try Self.parts(of: preview)
            #expect(parts.count >= 6, "\(preview.rawValue): the parts were not read")
            for setting in Setting.sweep(size) {
                let cut = Self.cut(in: TodayParts(preview: preview), parts: parts, setting)
                #expect(cut.isEmpty, "\(preview.rawValue), \(setting): \(cut.joined(separator: "; "))")
            }
        }

        /// The control: the check sees a heading held to one line, and passes the same heading let wrap.
        @Test("The check sees a heading cut to one line at Accessibility 5, and not one that wraps")
        func check_seesACut() throws {
            let title = try #require(TodayPreview.logged.model().card.logged).title
            let part = Part(title) { Text(title).ledgerFont(.heading) }
            let setting = Setting(size: .accessibility5, width: 375, isBold: false)
            let cut = Self.cut(in: Text(title).ledgerFont(.heading).lineLimit(1), parts: [part], setting)
            let whole = Self.cut(in: Text(title).ledgerFont(.heading), parts: [part], setting)
            #expect(cut.count == 1 && whole.isEmpty, "held to one line: \(cut); wrapping: \(whole)")
        }
    }
#endif
