import CoreGraphics
@testable import LedgerDesign
import Testing

/// F11 S8 adversarial round 1, criterion 3, the arithmetic: `WrapLayout.arrangement(of:in:)` against the
/// tester's own model of a wrapping row, on seeded children and widths, and at the widths a parent may
/// propose (none, zero, below zero, unbounded). The model is written from the criterion and the type's
/// documentation, never from its code: rows are filled greedily, a row's children are centred on its height,
/// and the size is the widest row by the rows' heights with the line spacing between them.
@Suite("Adversarial F11 S8 · WrapLayout's arithmetic", .tags(.design))
nonisolated struct WrapLayoutAdversarialTests {
    struct Model {
        var frames: [CGRect] = []
        var size = CGSize.zero
        /// The children of each row, by place.
        var rows: [[Int]] = []
    }

    /// The tester's model. Rows first, by widths alone; then each row's frames.
    static func model(_ sizes: [CGSize], width: CGFloat?, spacing: CGFloat, lineSpacing: CGFloat) -> Model {
        let limit = width.map { $0.isFinite ? $0 : CGFloat.infinity } ?? .infinity
        var model = Model()
        var used: CGFloat = 0
        for (place, size) in sizes.enumerated() {
            if let row = model.rows.last, !row.isEmpty, used + spacing + size.width <= limit {
                model.rows[model.rows.count - 1].append(place)
                used += spacing + size.width
            } else {
                model.rows.append([place])
                used = size.width
            }
        }
        model.frames = Array(repeating: .zero, count: sizes.count)
        var top: CGFloat = 0
        for (number, row) in model.rows.enumerated() {
            let height = row.map { sizes[$0].height }.max() ?? 0
            var leading: CGFloat = 0
            for place in row {
                let origin = CGPoint(x: leading, y: top + (height - sizes[place].height) / 2)
                model.frames[place] = CGRect(origin: origin, size: sizes[place])
                leading += sizes[place].width + spacing
            }
            model.size.width = max(model.size.width, leading - spacing)
            model.size.height = top + height
            top += height + (number < model.rows.count - 1 ? lineSpacing : 0) + 0
        }
        return model
    }

    /// Sizes in half points, so that every sum is exact.
    static func sizes(_ count: Int, upTo widest: Int, using random: inout SplitMix64) -> [CGSize] {
        (0 ..< count).map { _ in
            CGSize(
                width: CGFloat(Int.random(in: 0 ... widest * 2, using: &random)) / 2,
                height: CGFloat(Int.random(in: 0 ... 120, using: &random)) / 2
            )
        }
    }

    @Test(
        "On seeded children, spacings and widths the frames and the size are the tester's model's",
        arguments: 0 ..< 300 as Range<Int>
    )
    func arrangement_seeded_isTheTestersModel(seed: Int) {
        var random = SplitMix64(seed: seed * 7919 + 11)
        let count = [0, 1, 2, Int.random(in: 0 ... 40, using: &random)].randomElement(using: &random) ?? 0
        let sizes = Self.sizes(count, upTo: [20, 90, 200].randomElement(using: &random) ?? 90, using: &random)
        let spacing = CGFloat([0, 4, 8, 8, 24, 500].randomElement(using: &random) ?? 8)
        let lineSpacing = CGFloat([0, 6, 8, 40].randomElement(using: &random) ?? 8)
        let widths: [CGFloat?] = [nil, 0, 1, 44, 100, 137.5, 402, 100_000, .infinity, -1, -100]
        let layout = WrapLayout(spacing: spacing, lineSpacing: lineSpacing)
        for width in widths {
            let expected = Self.model(sizes, width: width, spacing: spacing, lineSpacing: lineSpacing)
            let found = layout.arrangement(of: sizes, in: width)
            let isTheModels = found.frames == expected.frames && found.size == expected.size
            #expect(isTheModels, "seed \(seed), width \(String(describing: width)), \(count) children")
            Self.checkUse(found.size, found.frames, seed: seed, width: width)
        }
    }

    /// The size reported is the size used: no child stands outside it, and it is no bigger than the children
    /// need.
    static func checkUse(_ size: CGSize, _ frames: [CGRect], seed: Int, width: CGFloat?) {
        let bounds = CGRect(origin: .zero, size: size)
        let isInside = frames.allSatisfy {
            $0.minX >= 0 && $0.minY >= 0 && $0.maxX <= bounds.maxX && $0.maxY <= bounds.maxY
        }
        #expect(isInside, "seed \(seed), width \(String(describing: width)): a child stands outside \(size)")
        let reach = frames.reduce(CGSize.zero) {
            CGSize(width: max($0.width, $1.maxX), height: max($0.height, $1.maxY))
        }
        #expect(reach == size, "seed \(seed), width \(String(describing: width)): \(reach) used of \(size)")
        #expect(size.width.isFinite && size.height.isFinite && size.width >= 0 && size.height >= 0)
    }

    @Test(
        "A row is full only when the next child does not fit: no row could have taken its follower",
        arguments: 0 ..< 100 as Range<Int>
    )
    func arrangement_seeded_rowsAreGreedyAndInOrder(seed: Int) {
        var random = SplitMix64(seed: seed * 97 + 5)
        let sizes = Self.sizes(Int.random(in: 1 ... 60, using: &random), upTo: 120, using: &random)
        let width = CGFloat(Int.random(in: 0 ... 400, using: &random))
        let frames = WrapLayout(spacing: 8, lineSpacing: 6).arrangement(of: sizes, in: width).frames
        #expect(frames.map(\.size) == sizes, "seed \(seed): a child was resized")
        for (place, frame) in frames.enumerated().dropFirst() {
            let before = frames[place - 1]
            if frame.minX == 0 {
                let wouldHaveFit = before.maxX + 8 + frame.width <= width
                #expect(!wouldHaveFit, "seed \(seed): child \(place) wrapped although it fitted")
                #expect(frame.midY > before.midY, "seed \(seed): child \(place) is not below the row before")
            } else {
                let isBeside = frame.minX == before.maxX + 8 && frame.maxX <= width && frame.midY == before.midY
                #expect(isBeside, "seed \(seed): child \(place) at \(frame) after \(before), width \(width)")
            }
        }
    }

    @Test(
        "Arranged again in the width it reported, the layout stands as it stood: placing repeats measuring",
        arguments: 0 ..< 100 as Range<Int>
    )
    func arrangement_seeded_isStableInItsOwnWidth(seed: Int) {
        var random = SplitMix64(seed: seed * 131 + 3)
        let width = CGFloat(Int.random(in: 1 ... 400, using: &random))
        // As the layout hands them over: no child wider than the row.
        let sizes = Self.sizes(Int.random(in: 0 ... 50, using: &random), upTo: 150, using: &random).map {
            CGSize(width: min($0.width, width), height: $0.height)
        }
        let layout = WrapLayout(spacing: 8, lineSpacing: 6)
        let measured = layout.arrangement(of: sizes, in: width)
        let placed = layout.arrangement(of: sizes, in: measured.size.width)
        let isStable = placed.frames == measured.frames && placed.size == measured.size
        #expect(isStable, "seed \(seed): measured in \(width), placed in \(measured.size.width)")
        #expect(measured.size.width <= width, "seed \(seed)")
    }

    @Test("Children of no size, a width of nothing or less, and spacing wider than the row all lay out")
    func arrangement_degenerateInputs_layOut() {
        let layout = WrapLayout(spacing: 8, lineSpacing: 6)
        let dots = Array(repeating: CGSize.zero, count: 4)
        #expect(layout.arrangement(of: dots, in: 100).frames.count == 4)
        #expect(layout.arrangement(of: dots, in: 0).size == CGSize(width: 0, height: 18), "four rows of nothing")
        let three = [CGSize(width: 30, height: 10), CGSize(width: 30, height: 10), CGSize(width: 30, height: 10)]
        for width in [0, -1, -1000, 29] as [CGFloat] {
            let narrow = layout.arrangement(of: three, in: width)
            #expect(narrow.frames.map(\.minX) == [0, 0, 0], "\(width)")
            #expect(narrow.size == CGSize(width: 30, height: 42), "\(width)")
        }
        let wide = WrapLayout(spacing: 1000, lineSpacing: 0).arrangement(of: three, in: 100)
        #expect(wide.frames.map(\.minY) == [0, 10, 20])
        #expect(wide.size == CGSize(width: 30, height: 30))
        let nan = layout.arrangement(of: three, in: .nan)
        #expect(nan.frames.count == 3 && nan.size.width.isFinite, "a width that is no number is no width")
    }

    @Test("Five thousand children are arranged in under a second")
    func arrangement_manyChildren_isLinear() {
        var random = SplitMix64(seed: 5000)
        let sizes = Self.sizes(5000, upTo: 90, using: &random)
        let layout = WrapLayout(spacing: 8, lineSpacing: 6)
        var frames = 0
        let taken = ContinuousClock().measure { frames = layout.arrangement(of: sizes, in: 402).frames.count }
        #expect(frames == 5000)
        #expect(taken < .seconds(1), "\(taken)")
    }
}
