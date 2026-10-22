#if os(iOS) && DEBUG
    @testable import FeatureLibrary
    import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// F12 S2, criterion 12 and Pete's question 3 (A): where an exercise's history is orange, by the colour of the
    /// pixels each part draws, in both themes: the estimate, the chart's change and the current week's bar, and
    /// nothing else (not the header, the other stats, the other bars, a PR tag or the log).
    @Suite("Exercise history orange audit", .serialized, .tags(.feature))
    struct ExerciseHistoryOrangeAuditTests {
        nonisolated static let themes: [ColorScheme] = [.dark, .light]

        /// As `ProgramDrawing.orangePixels`: the pixels whose hue is the accent's, either of its two.
        static func orangePixels(in view: some View, _ theme: ColorScheme) throws -> Int {
            let content = view.fixedSize(horizontal: false, vertical: true).background(LedgerColor.ground)
            let image = RenderedImage.render(content, width: SnapshotConfig.phoneWidth, colorScheme: theme)
            return try #require(image.flatMap(PixelBuffer.init)).pixels.count { pixel in
                Int(pixel.red) > Int(pixel.green) + 40 && Int(pixel.green) > Int(pixel.blue) + 15 && pixel.red > 110
            }
        }

        @Test("The estimate, the change and the last bar are orange; the rest of the page is not", arguments: themes)
        func orange_isTheEstimateTheChangeAndTheLastBar(_ theme: ColorScheme) throws {
            let model = try HistoryPreview.logged.model()
            let estimate = try #require(model.stats.first)
            let tile = { (stat: ExerciseHistoryModel.Stat) in
                StatTile(value: stat.value, unit: stat.unit, caption: stat.caption, isValueAccented: stat.isAccented)
            }
            #expect(try Self.orangePixels(in: tile(estimate), theme) > 0, "the estimate")
            let others = try model.stats.dropFirst().map { try Self.orangePixels(in: tile($0), theme) }
            #expect(others == [0, 0], "the other stats")
            #expect(try Self.orangePixels(in: SessionLog(log: model.log) { _ in }, theme) == 0, "the log, PR tags too")
            #expect(model.log.entries.contains { $0.isRecord })
            let chart = try Self.orangePixels(in: E1RMChart(chart: model.chart), theme)
            let unaccented = ExerciseHistoryModel.Chart(
                title: model.chart.title, delta: nil, bars: Array(model.chart.bars.dropLast()), empty: nil,
                spokenTitle: "", weekAxis: "", valueAxis: ""
            )
            #expect(chart > 0)
            #expect(try Self.orangePixels(in: E1RMChart(chart: unaccented), theme) == 0, "the other bars and the title")
            let noDelta = ExerciseHistoryModel.Chart(
                title: model.chart.title, delta: nil, bars: model.chart.bars, empty: nil,
                spokenTitle: "", weekAxis: "", valueAxis: ""
            )
            let bar = try Self.orangePixels(in: E1RMChart(chart: noDelta), theme)
            #expect(bar > 0 && bar < chart, "the last bar, and the change beside the title")
        }

        @Test("With no estimate the page wears no orange", arguments: themes)
        func noData_wearsNone(_ theme: ColorScheme) throws {
            #expect(try Self.orangePixels(in: HistoryParts(preview: .noData), theme) == 0)
        }
    }
#endif
