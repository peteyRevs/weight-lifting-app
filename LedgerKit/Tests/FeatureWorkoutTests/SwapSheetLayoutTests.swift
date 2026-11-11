#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    import LedgerDesign
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// F10 S8b, criteria 13, 30 and 33: the swap sheet and the card's title row in every setting. Nothing of
    /// the sheet is cut, leaves the phone or lies over something else from the default size to the largest,
    /// on a 375 pt phone and an iPhone 17, with Bold Text and right to left (by measurement,
    /// `WorkoutLayoutProbe`); every target is 44 pt; the card's name never stands under the swap button; and
    /// orange on the sheet is "Use" alone.
    @Suite("Swap sheet layout", .serialized, .tags(.feature))
    struct SwapSheetLayoutTests {
        nonisolated static let sizes = WorkoutPageLayoutTests.sizes

        static func models() throws -> [SwapSheetModel] {
            try SwapSheetPreview.allCases.map { try #require($0.model) }
        }

        static func parts(of model: SwapSheetModel) -> [LayoutPart] {
            var parts = [
                LayoutPart(model.title) { Text(model.title).ledgerFont(.subheading) },
                LayoutPart(model.cancel) { PillButton(model.cancel, style: .ghost) {} },
                LayoutPart(model.line) { Text(model.line).ledgerFont(.bodyLight) }
            ]
            if let message = model.message {
                parts.append(LayoutPart(message) { Text(message).ledgerFont(.body) })
            }
            if let toggle = model.toggle {
                parts.append(LayoutPart(toggle.label) {
                    Toggle(isOn: .constant(toggle.isOn)) { Text(toggle.label).ledgerFont(.body) }.toggleStyle(.ledger)
                })
            }
            for row in model.rows {
                parts.append(LayoutPart("\(row.name), \(row.detail), \(row.use)") {
                    HairlineRow(row.name, detail: row.detail, action: {}, accessory: {
                        Text(row.use).ledgerFont(.caption)
                    })
                })
            }
            return parts
        }

        // MARK: Criterion 33: sizes, Bold Text, right to left

        @Test("No word of the sheet is cut, in any setting", arguments: sizes)
        func sheet_noWordIsCut(_ size: DynamicTypeSize) throws {
            for model in try Self.models() {
                let sheet = SwapSheetParts(model: model)
                for setting in LayoutSetting.sweep(size) {
                    let cut = WorkoutLayoutProbe.cut(in: sheet, parts: Self.parts(of: model), setting)
                    #expect(cut.isEmpty, "\(setting.testDescription): \(cut.prefix(2).joined(separator: "; "))")
                }
            }
        }

        @Test("Every stop is inside the phone, none lies over another, and every target is 44 pt", arguments: sizes)
        func sheet_nothingLeavesOrOverlaps(_ size: DynamicTypeSize) throws {
            for model in try Self.models() {
                let sheet = SwapSheetParts(model: model)
                for setting in LayoutSetting.sweep(size) {
                    let misplaced = WorkoutLayoutProbe.misplaced(in: sheet, setting)
                    #expect(
                        misplaced.isEmpty,
                        "\(setting.testDescription): \(misplaced.prefix(2).joined(separator: "; "))"
                    )
                    let buttons = setting.elements(of: sheet).filter { $0.traits.contains(.button) }
                    #expect(buttons.count == 1 + (model.toggle == nil ? 0 : 1) + model.rows.count)
                    let small = buttons.filter { $0.frame.width < 44 - 0.001 || $0.frame.height < 44 - 0.001 }
                    #expect(small.isEmpty, "\(setting.testDescription): \(small.map(\.label))")
                }
            }
        }

        /// The card's name and the swap button: side by side, or the button under the name, never the name
        /// under the button; the button is a 44 pt target. On the page that can be swapped, and on one whose
        /// name takes three lines.
        @Test("The card's name never stands under Swap exercise, which is a 44 pt target", arguments: sizes)
        func titleRow_nameNeverUnderTheButton(_ size: DynamicTypeSize) throws {
            for model in try [WorkoutPageLayoutTests.page(.started), WorkoutPageLayoutTests.longWords()] {
                let card = try #require(model.card)
                let page = WorkoutPage(model: model) { _ in }
                for setting in LayoutSetting.sweep(size) {
                    let stops = setting.elements(of: page)
                    let title = try #require(stops.first { $0.label == card.title }).frame
                    let button = try #require(stops.first { $0.label == "Swap exercise" }).frame
                    let isBeside = title.maxX <= button.minX + 0.5 || button.maxX <= title.minX + 0.5
                    let isBelow = button.minY >= title.maxY - 0.5
                    #expect(isBeside || isBelow, "\(setting.testDescription): \(title) and \(button)")
                    #expect(button.width >= 44 - 0.001 && button.height >= 44 - 0.001, "\(setting.testDescription)")
                }
            }
        }

        // MARK: Criterion 30: orange is Use

        @Test("Orange on the sheet is the rows' Use and nothing else; with no row there is none", arguments: [
            ColorScheme.light, .dark
        ])
        func orange_isUseAlone(scheme: ColorScheme) throws {
            let width = SnapshotConfig.phoneWidth
            let sheet = try SwapSheetParts(.rows)
            let image = try #require(RenderedImage.render(
                sheet,
                width: width,
                colorScheme: scheme,
                dynamicTypeSize: .large
            ))
            let marked = VStack(spacing: 0) {
                Color.clear.frame(height: 1).accessibilityElement().accessibilityLabel(Text(verbatim: "Top"))
                sheet
            }
            let stops = marked.frame(width: width).accessibilityElements(SnapshotAppearance(scheme, .large))
            let top = try #require(stops.first { $0.label == "Top" }).frame
            // "Use" stands at each row's trailing end: the row's last quarter.
            let uses = stops.filter { $0.label.hasSuffix(", Use") }.map { stop in
                let row = stop.frame.offsetBy(dx: -top.minX, dy: -top.maxY)
                return CGRect(x: row.maxX - row.width / 4, y: row.minY, width: row.width / 4, height: row.height)
            }
            #expect(uses.count == 8)
            let found = WorkoutRestPanelAdversarialTests.orange(in: image)
            let inUse = found.count { point in uses.contains { $0.contains(point) } }
            #expect(inUse > 8, "\(scheme): every Use is orange")
            #expect(found.count == inUse, "\(scheme): \(found.count - inUse) orange pixels stray")
            let empty = try #require(RenderedImage.render(
                SwapSheetParts(.empty), width: width, colorScheme: scheme, dynamicTypeSize: .large
            ))
            #expect(WorkoutRestPanelAdversarialTests.orange(in: empty).isEmpty, "\(scheme): no row, no orange")
        }
    }
#endif
