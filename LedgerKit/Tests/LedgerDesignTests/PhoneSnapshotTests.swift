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

        /// A `width`×`height` white image with `changed` red pixels, at 1×: the first ones (row-major), or spread
        /// evenly over the whole page.
        static func image(width: Int, height: Int, changed: Int, scattered: Bool = false) throws -> UIImage {
            let stride = scattered ? width * height / max(changed, 1) : 1
            let cgImage = try #require(Bitmap.make(width: width, height: height) { column, row in
                let index = row * width + column
                return index % stride == 0 && index / stride < changed ? 0xFF00_00FF : ground
            })
            return UIImage(cgImage: cgImage, scale: SnapshotConfig.scale, orientation: .up)
        }

        @Test(
            "The budget is exact on a short and a long page, pixels together or spread: it passes, one more fails",
            arguments: [66, 1009, 9200], [false, true]
        )
        func budget_isExact_atAnyLength(height: Int, scattered: Bool) throws {
            let width = Int(SnapshotConfig.phoneWidth)
            let budget = SnapshotConfig.pixelBudget
            let reference = try Self.image(width: width, height: height, changed: 0)
            let atBudget = try Self.image(width: width, height: height, changed: budget, scattered: scattered)
            let overBudget = try Self.image(width: width, height: height, changed: budget + 1, scattered: scattered)
            let diffing = Diffing<UIImage>.withinPixelBudget
            #expect(diffing.diffV2(reference, atBudget) == nil, "\(budget) of \(width)×\(height) differing failed")
            let failure = try #require(diffing.diffV2(reference, overBudget), "\(budget + 1) differing passed")
            #expect(failure.0.contains("At most \(budget) of \(width * height) pixels may differ"), "\(failure.0)")
        }

        @Test("A reference over the pixels the budget holds exactly fails, even matched, and says to split the page")
        func reference_overMaximumPixels_fails() throws {
            let height = SnapshotConfig.maximumPixels / Int(SnapshotConfig.phoneWidth) + 1
            let image = try Self.image(width: Int(SnapshotConfig.phoneWidth), height: height, changed: 0)
            let failure = try #require(
                Diffing<UIImage>.withinPixelBudget.diffV2(image, image),
                "a 402×\(height) passed"
            )
            #expect(failure.0.contains("split the page"), "\(failure.0)")
        }

        /// A view 50 pt high, or 100 pt with Increase Contrast, which SwiftUI reads from the window's traits.
        struct ContrastSized: View {
            @Environment(\.colorSchemeContrast) private var contrast

            var body: some View {
                Color.white.frame(width: SnapshotConfig.phoneWidth, height: contrast == .increased ? 100 : 50)
            }
        }

        @Test("The page is measured with the cell's traits, as it is drawn: Increase Contrast makes it 100 pt high")
        func page_isMeasuredWithTheCellsTraits() async {
            let appearance = SnapshotAppearance(.light, .large)
            let contrast: (inout any UIMutableTraits) -> Void = { $0.accessibilityContrast = .high }
            let page = PhonePage(ContrastSized(), appearance, modifyingTraits: contrast)
            let image = await withCheckedContinuation { done in
                Snapshotting<PhonePage, UIImage>.phone(appearance, modifyingTraits: contrast).snapshot(page)
                    .run { done.resume(returning: $0) }
            }
            #expect(image.size.height == 100)
        }
    }
#endif
