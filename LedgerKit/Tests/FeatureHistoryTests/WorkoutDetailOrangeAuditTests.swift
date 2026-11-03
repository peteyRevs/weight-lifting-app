#if os(iOS) && DEBUG
    @testable import FeatureHistory
    import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// F13 S2, N6: where a past workout's detail is orange, by the colour of the pixels each part draws, in both
    /// themes: the receipt's own orange as F10 shipped it (the TIME label and the records line), and nothing else. The
    /// header, the other tiles, the rows and "Delete workout" are not; Delete's red is its alert's alone.
    @Suite("Workout detail orange audit", .serialized, .tags(.feature))
    struct WorkoutDetailOrangeAuditTests {
        nonisolated static let themes: [ColorScheme] = [.dark, .light]

        /// As `ProgramDrawing.orangePixels`: the pixels whose hue is the accent's, either of its two.
        static func orangePixels(in view: some View, _ theme: ColorScheme) throws -> Int {
            let content = view.fixedSize(horizontal: false, vertical: true).background(LedgerColor.ground)
            let image = RenderedImage.render(content, width: SnapshotConfig.phoneWidth, colorScheme: theme)
            return try #require(image.flatMap(PixelBuffer.init)).pixels.count { pixel in
                Int(pixel.red) > Int(pixel.green) + 40 && Int(pixel.green) > Int(pixel.blue) + 15 && pixel.red > 110
            }
        }

        /// `model` with no TIME accent and no records line: the page as it would be without the receipt's orange.
        static func unaccented(_ model: WorkoutDetailModel) -> WorkoutDetailModel {
            let receipt = model.receipt
            return WorkoutDetailModel(
                date: model.date,
                title: model.title,
                receipt: ReceiptLayout.Model(
                    tiles: receipt.tiles
                        .map { ReceiptLayout.Tile(label: $0.label, value: $0.value, spoken: $0.spoken) },
                    records: nil,
                    logged: receipt.logged,
                    note: receipt.note,
                    rows: receipt.rows
                ),
                rowRoutes: model.rowRoutes,
                delete: model.delete
            )
        }

        static func page(_ model: WorkoutDetailModel) -> some View {
            WorkoutDetailPage(model: model, send: { _ in }, onDelete: {})
        }

        @Test("The TIME label and the records line are orange; the rest of the page is not", arguments: themes)
        func orange_isTheReceiptsOwn(_ theme: ColorScheme) throws {
            let model = try DetailPreview.withRecords.model()
            #expect(try Self.orangePixels(in: Self.page(model), theme) > 0)
            #expect(try Self.orangePixels(in: Self.page(Self.unaccented(model)), theme) == 0, "nothing else")
            let noRecords = try DetailPreview.noRecords.model()
            let withRecords = try Self.orangePixels(in: Self.page(model), theme)
            #expect(try Self.orangePixels(in: Self.page(noRecords), theme) < withRecords, "the records line")
        }

        @Test("Delete workout, and the page of a workout that can't be read, wear no orange", arguments: themes)
        func delete_wearsNone(_ theme: ColorScheme) throws {
            let deletion = WorkoutDetailPresentation.deletion
            #expect(try Self.orangePixels(in: DeleteWorkoutButton(model: deletion) {}, theme) == 0)
            #expect(try Self.orangePixels(in: DetailParts(preview: .unreadable), theme) == 0)
        }
    }
#endif
