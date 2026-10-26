#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    import LedgerDesign
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// F10 S7b, criteria 35, 38 and 39: the receipt in every setting. Nothing of it is cut, leaves the phone
    /// or lies over something else from the default size to the largest, on a 375 pt phone and an iPhone
    /// 17, with Bold Text and right to left (by measurement, `WorkoutLayoutProbe`); at the accessibility
    /// sizes the tiles stand one per row and "Done" under the name; and orange is the "TIME" label and the
    /// records line alone.
    @Suite("Receipt layout", .serialized, .tags(.feature))
    struct ReceiptLayoutTests {
        nonisolated static let sizes = WorkoutPageLayoutTests.sizes

        /// A receipt whose words and numbers are as long as they get.
        static func longWords() throws -> ReceiptScreenModel {
            var workout = try Fixtures.seedSession()
            workout.name = "Upper A — Push focus, the long version of a day whose name runs on"
            workout.exercises[0].name = "Single-Arm Half-Kneeling Landmine Press with a Pause"
            workout.exercises[0].sets = (0 ..< 1250).map { index in
                LoggedSet(
                    id: .derived(from: workout.exercises[0].id, index: index),
                    weight: .pounds(Decimal(200 + index % 7)),
                    reps: Reps(clamping: 5),
                    kind: .working,
                    doneAt: index < 1234 ? workout.startedAt : nil
                )
            }
            let finished = try WorkoutPresentationReceiptTests.finished(workout, after: 3 * 3600 + 59 * 60 + 59)
            let records = WorkoutPresentationReceiptTests.records(12, of: finished)
            return WorkoutPresentationReceiptTests.receipt(finished, records: records)
        }

        static func models() throws -> [ReceiptScreenModel] {
            try ReceiptPreview.allCases.map { try #require($0.model) } + [longWords()]
        }

        /// The parts whose words this module and `ReceiptLayout` lay out: the header, the records line and
        /// each row. A tile's value shrinks rather than wraps, by design (`LedgerDesign`), so a tile is
        /// checked for its place, not for a cut. "LOGGED" is left out right to left only: there the reader
        /// gives the tracked eyebrow 5 pt less than it measures alone at the accessibility sizes, while the
        /// word is drawn whole (the notes, S7b "Deviations" 5; `ReceiptLoggedCutAdversarialTests`).
        static func parts(of model: ReceiptScreenModel, isRightToLeft: Bool = false) -> [LayoutPart] {
            var parts = [
                LayoutPart(model.header.date) { Text(model.header.date).ledgerFont(.caption) },
                LayoutPart(model.header.title) { Text(model.header.title).ledgerFont(.heading) },
                LayoutPart(model.header.done) { PillButton(model.header.done) {} }
            ]
            if !isRightToLeft {
                parts.append(LayoutPart(model.page.logged) { Eyebrow(model.page.logged) })
            }
            if let records = model.page.records {
                parts.append(LayoutPart(records) { Text(records).ledgerFont(.caption) })
            }
            for row in model.page.rows {
                parts.append(LayoutPart(row.spoken) {
                    VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                        HStack(spacing: LedgerSpacing.m) {
                            Text(row.name).ledgerFont(.body)
                            Text(row.target).ledgerFont(.caption)
                        }
                        WrapLayout {
                            ForEach(Array(row.chips.enumerated()), id: \.offset) { _, chip in
                                Text(chip).ledgerFont(.caption).padding(.horizontal, LedgerSpacing.s)
                            }
                        }
                    }
                    .padding(.vertical, LedgerSpacing.l)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text(verbatim: row.spoken))
                })
            }
            return parts
        }

        // MARK: Criteria 38 and 39: sizes, Bold Text, right to left

        @Test("No word of the receipt is cut, in any setting", arguments: sizes)
        func receipt_noWordIsCut(_ size: DynamicTypeSize) throws {
            for model in try Self.models() {
                let receipt = ReceiptParts(model: model)
                for setting in LayoutSetting.sweep(size) {
                    let cut = WorkoutLayoutProbe.cut(
                        in: receipt, parts: Self.parts(of: model, isRightToLeft: setting.isRightToLeft), setting
                    )
                    #expect(cut.isEmpty, "\(setting.testDescription): \(cut.prefix(2).joined(separator: "; "))")
                }
            }
        }

        @Test(
            "Every stop is inside the phone, none lies over another, and Done and the rows are 44 pt",
            arguments: sizes
        )
        func receipt_nothingLeavesOrOverlaps(_ size: DynamicTypeSize) throws {
            for model in try Self.models() {
                let receipt = ReceiptParts(model: model)
                for setting in LayoutSetting.sweep(size) {
                    let misplaced = WorkoutLayoutProbe.misplaced(in: receipt, setting)
                    #expect(
                        misplaced.isEmpty,
                        "\(setting.testDescription): \(misplaced.prefix(2).joined(separator: "; "))"
                    )
                    let buttons = setting.elements(of: receipt).filter { $0.traits.contains(.button) }
                    // F12 S3, N18 (sanctioned edit): each exercise's row is a button too, and a 44 pt target.
                    #expect(
                        buttons.map(\.label) == ["Done"] + model.page.rows.map(\.spoken),
                        "\(setting.testDescription)"
                    )
                    let small = buttons.filter { $0.frame.width < 44 - 0.001 || $0.frame.height < 44 - 0.001 }
                    #expect(small.isEmpty, "\(setting.testDescription)")
                }
            }
        }

        @Test(
            "At the accessibility sizes the tiles stand one per row and Done under the name; below, side by side",
            arguments: [DynamicTypeSize.large, .xxxLarge, .accessibility1, .accessibility5]
        )
        func receipt_stacksAtAccessibilitySizes(_ size: DynamicTypeSize) throws {
            let model = try #require(ReceiptPreview.withRecords.model)
            // The four sizes stay on every runner: they hold the boundary, which only the text size moves
            // (`ReceiptLayout` and `ReceiptHeader` stack on `isAccessibilitySize`), so the settings may sweep.
            for setting in LayoutSetting.sweep(size) {
                let stops = setting.elements(of: ReceiptParts(model: model))
                let tiles = model.page.tiles.compactMap { tile in stops.first { $0.label == tile.spoken }?.frame }
                let title = try #require(stops.first { $0.label == model.header.title }).frame
                let done = try #require(stops.first { $0.label == "Done" }).frame
                #expect(tiles.count == 3)
                let isStacked = zip(tiles, tiles.dropFirst()).allSatisfy { $1.minY >= $0.maxY }
                let isSideBySide = zip(tiles, tiles.dropFirst()).allSatisfy { abs($1.minY - $0.minY) < 0.5 }
                #expect(size.isAccessibilitySize ? isStacked : isSideBySide, "\(setting.testDescription)")
                #expect(size.isAccessibilitySize == (done.minY >= title.maxY), "\(setting.testDescription)")
            }
        }

        @Test("Right to left the receipt is mirrored: Done at the other edge, every line in the same order")
        func rightToLeft_isMirrored() throws {
            let receipt = try ReceiptParts(.withRecords)
            func stops(_ isRightToLeft: Bool) -> [String: CGRect] {
                let found = LayoutSetting(isRightToLeft: isRightToLeft).elements(of: receipt)
                return Dictionary(found.map { ($0.label, $0.frame) }) { first, _ in first }
            }
            let leading = stops(false)
            let mirrored = stops(true)
            let (title, done) = ("Upper A — Push focus", "Done")
            #expect(try #require(leading[done]).midX > #require(leading[title]).midX)
            #expect(try #require(mirrored[done]).midX < #require(mirrored[title]).midX)
            let time = "TIME, 24 minutes, 22 seconds"
            #expect(try #require(mirrored[time]).midX > #require(leading[time]).midX, "the first tile at the right")
            #expect(leading.keys.sorted() == mirrored.keys.sorted(), "every line keeps its characters' order")
        }

        @Test("The check sees a row that is cut")
        func check_seesACut() throws {
            let model = try Self.longWords()
            let cutOne = ReceiptParts(model: model).lineLimit(1)
            let parts = Self.parts(of: model).filter { $0.label == model.header.title }
            #expect(WorkoutLayoutProbe.cut(in: cutOne, parts: parts, LayoutSetting()).count == 1)
        }
    }

    extension ReceiptLayoutTests {
        // MARK: Criterion 35: no orange control

        @Test(
            "Orange on the receipt is the TIME label and the records line; Done and the other tiles are not",
            arguments: [ColorScheme.light, .dark]
        )
        func orange_isTheTimeLabelAndTheRecords(scheme: ColorScheme) throws {
            let width = SnapshotConfig.phoneWidth
            func orange(_ preview: ReceiptPreview) throws -> (found: [CGPoint], stops: [String: CGRect]) {
                let receipt = try ReceiptParts(preview)
                let image = try #require(RenderedImage.render(
                    receipt, width: width, colorScheme: scheme, dynamicTypeSize: .large
                ))
                #expect(image.width == Int(width), "one pixel a point")
                let marked = VStack(spacing: 0) {
                    Color.clear.frame(height: 1).accessibilityElement().accessibilityLabel(Text(verbatim: "Top"))
                    receipt
                }
                let found = marked.frame(width: width).accessibilityElements(SnapshotAppearance(scheme, .large))
                let top = try #require(found.first { $0.label == "Top" }).frame
                let placed = found.map { ($0.label, $0.frame.offsetBy(dx: -top.minX, dy: -top.maxY)) }
                let stops = Dictionary(placed) { first, _ in first }
                return (WorkoutRestPanelAdversarialTests.orange(in: image), stops)
            }
            let withRecords = try orange(.withRecords)
            let time = try #require(withRecords.stops["TIME, 24 minutes, 22 seconds"])
            let records = try #require(withRecords.stops["1 new PR this session"])
            let inTime = withRecords.found.count { time.contains($0) }
            let inRecords = withRecords.found.count { records.contains($0) }
            #expect(inTime > 20, "\(scheme): the TIME label is orange")
            #expect(inRecords > 50, "\(scheme): the records line is orange")
            #expect(withRecords.found.count == inTime + inRecords, "\(scheme): orange strays")
            let done = try #require(withRecords.stops["Done"])
            #expect(withRecords.found.allSatisfy { !done.contains($0) }, "\(scheme): Done is ink")

            let noRecords = try orange(.noRecords)
            let alone = try #require(noRecords.stops["TIME, 1 hour, 1 minute, 5 seconds"])
            #expect(noRecords.found.allSatisfy { alone.contains($0) }, "\(scheme): with no record, only TIME")
        }
    }
#endif
