#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDesign
    import LedgerDomain
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// The rules of the strip's layout, from criterion 10 and from the layout's own comment, and a strip as it
    /// was measured.
    nonisolated enum StripRules {
        /// One strip as it was measured: its cells' frames in order, each cell's size alone, and where the
        /// view under the strip begins.
        struct Measured {
            let cells: [CGRect]
            let alone: [CGSize]
            let end: CGRect
            /// The width the layout was given: the strip's, and the `xs` it is set out on each side.
            let given: CGFloat

            var widest: CGFloat {
                alone.map(\.width).max() ?? 0
            }

            /// The cells by row, top to bottom.
            var rows: [[CGRect]] {
                var found: [[CGRect]] = []
                for cell in cells {
                    if let last = found.last?.last, abs(last.minY - cell.minY) < 1 {
                        found[found.count - 1].append(cell)
                    } else {
                        found.append([cell])
                    }
                }
                return found
            }
        }

        /// What is wrong with a measured strip, by the rules of criterion 10 and of the layout's comment. A
        /// line each.
        static func faults(in strip: Measured, isRightToLeft: Bool = false) -> [String] {
            var lines: [String] = []
            let widths = strip.cells.map(\.width)
            let (narrowest, widest) = (widths.min() ?? 0, widths.max() ?? 0)
            if strip.cells.count != strip.alone.count {
                return ["\(strip.cells.count) cells were read, \(strip.alone.count) alone"]
            }
            // A point of grace: a third of 331 pt lands on whole pixels as 110.0 and 110.67 pt.
            if widest - narrowest > 1 {
                lines.append("the cells are not of one width: \(narrowest) to \(widest)")
            }
            let rows = strip.rows
            let fitsItsWord = strip.widest <= strip.given
            if fitsItsWord, narrowest < strip.widest - 0.5 {
                lines.append("a cell of \(narrowest) pt is narrower than the widest word's \(strip.widest)")
            }
            let oneRowNeeds = CGFloat(strip.cells.count) * (strip.widest + LedgerSpacing.xs)
            if oneRowNeeds < strip.given - 1, rows.count != 1 {
                lines.append("\(rows.count) rows where one row fits (\(oneRowNeeds) of \(strip.given) pt)")
            }
            if oneRowNeeds > strip.given + 1, rows.count == 1, strip.cells.count > 1 {
                lines.append("one row where each cell has less than xs beside its word")
            }
            if rows.count > 1, fitsItsWord, rows[0].count > 1, narrowest < strip.widest + LedgerSpacing.xl - 0.5 {
                lines.append("a wrapped cell of \(narrowest) pt has less than xl beside \(strip.widest)")
            }
            if rows.dropLast().contains(where: { $0.count != rows[0].count }) {
                lines.append("the full rows hold \(rows.map(\.count))")
            }
            return lines + rowFaults(in: strip, isRightToLeft: isRightToLeft) + roomFaults(in: strip)
        }

        /// Each row in order, as long as the width when it is full, starting where the first starts.
        static func rowFaults(in strip: Measured, isRightToLeft: Bool) -> [String] {
            var lines: [String] = []
            let rows = strip.rows
            for row in rows {
                let ordered = row.map(\.minX)
                if ordered != ordered.sorted(by: isRightToLeft ? (>) : (<)) {
                    lines.append("a row is out of order")
                }
                let (leading, trailing) = (row.map(\.minX).min() ?? 0, row.map(\.maxX).max() ?? 0)
                let isFull = row.count == rows[0].count
                if isFull, abs(trailing - leading - strip.given) > 1 {
                    lines.append("a full row is \(trailing - leading) pt long in \(strip.given)")
                }
                let edge = isRightToLeft ? trailing : leading
                let first = isRightToLeft ? (rows[0].map(\.maxX).max() ?? 0) : (rows[0].map(\.minX).min() ?? 0)
                if abs(edge - first) > 0.5 {
                    lines.append("a row starts at \(edge), the first at \(first)")
                }
                if (row.map(\.height).max() ?? 0) - (row.map(\.height).min() ?? 0) > 0.5 {
                    lines.append("a row's cells are not of one height")
                }
            }
            return lines
        }

        /// No cell over another, and the size the layout reports is the room its cells take.
        static func roomFaults(in strip: Measured) -> [String] {
            var lines: [String] = []
            for (place, cell) in strip.cells.enumerated() {
                for other in strip.cells[(place + 1)...] {
                    let shared = cell.intersection(other)
                    if !shared.isNull, shared.width > 0.5, shared.height > 0.5 {
                        lines.append("cells \(place) and later overlap by \(shared.size)")
                    }
                }
            }
            // The size the layout reports is the room its cells take: the next view starts under the last row.
            let bottom = strip.cells.map(\.maxY).max() ?? strip.end.minY
            if abs(strip.end.minY - bottom) > 0.5 {
                lines.append("the view under the strip starts at \(strip.end.minY), the cells end at \(bottom)")
            }
            return lines
        }
    }

    /// F11 S9, gate G2, round 2, criterion 10: the strip's `EqualCells` layout, attacked through the strip (the
    /// layout is private to its file). The rules are written here from the criterion and from the layout's
    /// own comment, and measured on the hosted strip: cells of any words, one to seven of them, in any width.
    @Suite("Adversarial F11 S9 · the strip's equal cells", .serialized, .tags(.feature))
    struct ProgramViewsStripAdversarialTests {
        /// Cells of these words on the first weekdays, each a button.
        nonisolated static func cells(_ words: [String]) -> [ProgramBuilderModel.Cell] {
            zip(Weekday.allCases, words).enumerated().map { place, pair in
                ProgramBuilderModel.Cell(
                    weekday: pair.0, letter: "M", label: pair.1, isRest: place % 2 == 1,
                    spokenLabel: "Cell \(place)", spokenValue: pair.1, spokenHint: "Hint",
                    action: .selectWeek(place)
                )
            }
        }

        static func measure(_ cells: [ProgramBuilderModel.Cell], _ setting: ViewsSetting) -> StripRules.Measured {
            let strip = VStack(spacing: 0) {
                ScheduleStrip(cells: cells) { _ in }
                Text(verbatim: "end")
            }
            let stops = ProgramViewsProbe.placed(strip, setting)
            let column = VStack(spacing: 0) {
                ForEach(cells, id: \.weekday) { ScheduleStrip(cells: [$0]) { _ in }.fixedSize() }
            }
            let alone = ProgramViewsProbe.placed(column, setting, atItsOwnWidth: true)
            return StripRules.Measured(
                cells: stops.dropLast().map(\.frame),
                alone: alone.map(\.frame.size),
                end: stops.last?.frame ?? .zero,
                given: setting.width + 2 * LedgerSpacing.xs
            )
        }

        /// A seeded strip: one to seven cells of words of one to ten letters, wide and narrow ones, in a width
        /// from narrower than a word to wider than a phone, at any text size, either direction.
        @Test(
            "Seeded cells in seeded widths: one width, no word cut, rows by the rule, the size it reports",
            arguments: 0 ..< 80
        )
        func seeded_cellsFollowTheRules(_ seed: Int) {
            var generator = SeededGenerator(seed: UInt64(seed) &* 7919 &+ 17)
            let count = Int.random(in: 1 ... 7, using: &generator)
            let letters: [Character] = ["W", "I", "M", "1", ".", "—"]
            var words: [String] = []
            for _ in 0 ..< count {
                var word = ""
                for _ in 0 ..< Int.random(in: 1 ... 10, using: &generator) {
                    word.append(letters.randomElement(using: &generator) ?? "W")
                }
                words.append(word)
            }
            let widths: [CGFloat] = [8, 40, 90, 150, 220, 268, 323, 350, 394]
            let width: CGFloat = widths.randomElement(using: &generator) ?? 323
            let size = DynamicTypeSize.allCases.randomElement(using: &generator) ?? .large
            let isRightToLeft = Bool.random(using: &generator)
            let setting = ViewsSetting(size: size, width: width, isRightToLeft: isRightToLeft)
            let faults = StripRules.faults(in: Self.measure(Self.cells(words), setting), isRightToLeft: isRightToLeft)
            #expect(
                faults.isEmpty,
                "\(words) in \(setting.testDescription): \(faults.prefix(3).joined(separator: "; "))"
            )
        }

        nonisolated static let programs = ["seed", "ten days", "a long tag"]

        static func cells(of program: String) throws -> [ProgramBuilderModel.Cell] {
            switch program {
            case "seed": try ProgramPreview.builder.builderModel().week.cells
            case "ten days": try BuilderState.tenDays.model().week.cells
            default: cells(["UA", "REST", "PUSH DAY", "REST", "D10", "LB", "REST"])
            }
        }

        @Test(
            "On a 375 and a 402 pt phone, at every size: no word cut, equal cells, every target 44 pt",
            arguments: programs, DynamicTypeSize.allCases
        )
        func phones_everySize_wholeEqualAnd44(_ program: String, _ size: DynamicTypeSize) throws {
            let cells = try Self.cells(of: program)
            for phone in ViewsSetting.widths {
                for setting in ViewsSetting.sweep(size) where setting.width == phone {
                    var strip = setting
                    strip.width = phone - 2 * LedgerSpacing.screen
                    let measured = Self.measure(cells, strip)
                    let faults = StripRules.faults(in: measured, isRightToLeft: setting.isRightToLeft)
                    #expect(faults.isEmpty, "\(setting.testDescription): \(faults.prefix(3).joined(separator: "; "))")
                    let least = measured.cells.map { min($0.width, $0.height) }.min() ?? 0
                    #expect(least >= 44, "\(setting.testDescription): a target of \(least) pt")
                }
            }
        }

        /// A note, pinned as measured, not a rule of the slice (criterion 10 names 375 and 402 pt). The cell
        /// carries no 44 pt least width of its own any more: the one row gives a seventh, and under 352 pt a
        /// seventh is under 44 pt. With the seed program that is at the three smallest text sizes (42.7 pt on
        /// 344 pt, 39.3 pt on 320 pt); from `.large` up the strip has wrapped there and its cells are wider.
        @Test("Under 375 pt the one row's targets fall under 44 pt on 344 and 320 pt, at the three smallest sizes only")
        func narrowPhones_whereTargetsFallShort() throws {
            let cells = try Self.cells(of: "seed")
            for (phone, expected) in [(CGFloat(320), 3), (344, 3), (352, 0), (360, 0)] {
                var short: [DynamicTypeSize] = []
                for size in DynamicTypeSize.allCases {
                    let setting = ViewsSetting(size: size, width: phone - 2 * LedgerSpacing.screen)
                    let measured = Self.measure(cells, setting)
                    #expect(
                        StripRules.faults(in: measured).isEmpty,
                        "\(Int(phone)) pt, \(size): the rules hold all the same"
                    )
                    if (measured.cells.map(\.width).min() ?? 0) < 44 {
                        short.append(size)
                    }
                }
                #expect(short == Array(DynamicTypeSize.allCases.prefix(expected)), "\(Int(phone)) pt: \(short)")
            }
        }

        /// **FINDING F11-S9-4** (minor, latent: no screen asks for it today). With no width proposed the
        /// layout reports one row of cells at the widest word's width, and then places its cells by the rule
        /// for that width, which wants `xs` more for each cell and so wraps: four cells whose widest is 59 pt
        /// are read 118 pt wide on more than one row (measured: 118, 118, 29 and 118 pt, three tops), in the
        /// room of one row. Any parent that asks a strip for its own size meets it (`fixedSize`,
        /// `ViewThatFits`, a sideways scroll view). The size reported for no width should be a row the
        /// placement accepts: the widest word's width and `tightRoom`, for each cell. (With `tightRoom` at
        /// zero, a mutation of round 2, this passes.)
        @Test("With no width proposed the cells stand on one row at the widest word's width, as the layout reports")
        func proposals_nil_placesWhatItReports() {
            let cells = Self.cells(["UA", "REST", "LONGER", "D10"])
            let row = HStack(spacing: 0) {
                ScheduleStrip(cells: cells) { _ in }.fixedSize()
                Text(verbatim: "end")
            }
            let stops = ProgramViewsProbe.placed(row, ViewsSetting())
            let frames = stops.dropLast().map(\.frame)
            let alone = Self.measure(cells, ViewsSetting()).widest
            let rows = Set(frames.map { ($0.minY * 2).rounded() }).count
            #expect(frames.count == 4 && rows == 1, "\(rows) rows")
            // The strip stands `xs` out on each side, and so do the cells' frames.
            let widths = frames.map(\.width)
            #expect(widths.allSatisfy { $0 >= alone - 0.5 && $0 <= alone + LedgerSpacing.xl }, "\(widths) for \(alone)")
        }

        @Test("One cell takes the whole width, and no cell takes no room")
        func proposals_oneAndNone() {
            let one = Self.measure(Self.cells(["REST"]), ViewsSetting(width: 300))
            #expect(one.cells.count == 1 && abs((one.cells.first?.width ?? 0) - one.given) < 0.5)
            #expect(StripRules.faults(in: one).isEmpty)
            let host = UIHostingController(rootView: ScheduleStrip(cells: []) { _ in })
            #expect(host.sizeThatFits(in: CGSize(width: 300, height: 1000)).height == 0)
        }

        @Test("In a width narrower than a word every cell is the whole width and stands on its own row")
        func proposals_tiny() {
            for width in [CGFloat(4), 8, 20] {
                let measured = Self.measure(Self.cells(["UA", "REST", "LONGER"]), ViewsSetting(width: width))
                #expect(measured.rows.map(\.count) == [1, 1, 1], "\(width): \(measured.rows.map(\.count))")
                #expect(measured.cells.allSatisfy { abs($0.width - measured.given) < 0.5 }, "\(width)")
                #expect(StripRules.faults(in: measured).isEmpty, "\(width): \(StripRules.faults(in: measured))")
            }
        }
    }
#endif
