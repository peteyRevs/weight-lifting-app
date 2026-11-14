#if os(iOS)
    import LedgerSnapshotTesting
    import SnapshotTesting
    import SwiftUI
    import Testing

    /// `assertPhoneSnapshot`'s strategy (`Snapshotting.phone`): a long page is drawn whole, and held to the same
    /// pixel budget as a short one (`tasks/chores/2026-10-12-m1-batch-b.md` §4).
    @Suite("Phone snapshot strategy", .tags(.design, .snapshot))
    struct PhoneSnapshotTests {
        static let ground: UInt32 = 0xFFFF_FFFF

        /// Forty lines of body text with 16 pt of ground above and below. A line's height is not a whole point,
        /// so measured at 3× and drawn at 1× the stack grew and lost up to 13 pt at each end.
        static var fortyLines: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(1 ... 40, id: \.self) { Text("Line \($0)").font(.body) }
            }
            .padding(.vertical, 16)
            .frame(width: SnapshotConfig.phoneWidth)
            .background(Color.white)
        }

        func drawn(_ view: some View, _ appearance: SnapshotAppearance) async throws -> PixelBuffer {
            let page = PhonePage(view, appearance)
            let image = await withCheckedContinuation { done in
                Snapshotting<PhonePage, UIImage>.phone(appearance).snapshot(page).run { done.resume(returning: $0) }
            }
            return try #require(image.cgImage.flatMap(PixelBuffer.init))
        }

        @Test(
            "Forty lines of text are drawn whole: the ground above the first and below the last is the padding's",
            arguments: [DynamicTypeSize.large, .accessibility3, .accessibility5]
        )
        func fortyLines_areDrawnWhole(size: DynamicTypeSize) async throws {
            let buffer = try await drawn(Self.fortyLines, SnapshotAppearance(.light, size))
            let white = buffer.pixel(column: 0, row: 0)
            let inked = (0 ..< buffer.height).filter { row in
                (0 ..< buffer.width).contains { buffer.pixel(column: $0, row: row).differs(from: white, by: 24) }
            }
            let (first, last) = try (#require(inked.first), #require(inked.last))
            #expect(first >= 16, "\(size): the first line's ink starts at row \(first), inside the padding")
            #expect(
                buffer.height - 1 - last >= 16,
                "\(size): the last line's ink ends \(buffer.height - 1 - last) from the bottom"
            )
        }

        /// A `width`×`height` white image whose first `changed` pixels (row-major) are red, at 1×.
        static func image(width: Int, height: Int, changed: Int) throws -> UIImage {
            let cgImage = try #require(Bitmap.make(width: width, height: height) { column, row in
                row * width + column < changed ? 0xFF00_00FF : ground
            })
            return UIImage(cgImage: cgImage, scale: SnapshotConfig.scale, orientation: .up)
        }

        @Test(
            "The budget is exact at a short and at a long page: the budget's pixels pass, one more fails",
            arguments: [66, 1009, 9200]
        )
        func budget_isExact_atAnyLength(height: Int) throws {
            let width = Int(SnapshotConfig.phoneWidth)
            let budget = SnapshotConfig.pixelBudget
            let reference = try Self.image(width: width, height: height, changed: 0)
            let atBudget = try Self.image(width: width, height: height, changed: budget)
            let overBudget = try Self.image(width: width, height: height, changed: budget + 1)
            let diffing = Diffing<UIImage>.withinPixelBudget
            #expect(diffing.diffV2(reference, atBudget) == nil, "\(budget) of \(width)×\(height) differing failed")
            let failure = try #require(diffing.diffV2(reference, overBudget), "\(budget + 1) differing passed")
            #expect(failure.0.contains("At most \(budget) of \(width * height) pixels may differ"), "\(failure.0)")
        }
    }
#endif
