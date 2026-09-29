import CoreGraphics
import Foundation
import ImageIO
import LedgerSnapshotTesting
import SnapshotTesting
import Testing

/// SplitMix64: a seeded generator, so a failing seed is a fixed regression case (testing-strategy §3).
nonisolated struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(truncatingIfNeeded: seed) &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// Round 3: the `.png` comparator after fix round 2, as properties over seeded image sizes rather
/// than round 2's six fixed ones — the 0.995 boundary with the changed pixels anywhere and
/// sub-threshold noise everywhere else, and the difference image of a size change.
@Suite("Snapshot comparator properties (adversarial, round 3)", .tags(.design, .snapshot))
struct ComparatorPropertyAdversarialTests {
    static let grey: UInt32 = 0x8080_80FF
    /// One grey step: ΔE well under 2, so it must never count as a mismatch.
    static let nudged: UInt32 = 0x8181_81FF
    static let red: UInt32 = 0xFF00_00FF
    static let magenta = Pixel(hex: 0xFF00FF)

    static func diff(_ reference: CGImage, _ actual: CGImage) -> (String, [DiffAttachment])? {
        Snapshotting<CGImage, Data>.png.diffing.diffV2(Bitmap.png(reference), Bitmap.png(actual))
    }

    static func difference(in attachments: [DiffAttachment]) throws -> PixelBuffer {
        let data = try #require(attachments.lazy.compactMap { attachment -> Data? in
            if case let .data(data, name) = attachment, name == "difference.png" {
                return data
            }
            return nil
        }.first, "no difference.png attached")
        let image = try #require(CGImageSourceCreateWithData(data as CFData, nil).flatMap {
            CGImageSourceCreateImageAtIndex($0, 0, nil)
        })
        return try #require(PixelBuffer(image))
    }

    @Test(
        "Any size, changed pixels anywhere, sub-threshold noise elsewhere: floor(0.5 %) pass, one more fails.",
        arguments: 0 ..< 40
    )
    func precisionBoundary_anySizeAnyPositions_isFloorHalfPercent(seed: Int) throws {
        var random = SplitMix64(seed: seed)
        // Every fifth seed is a whole multiple of 200 pixels, where 0.5 % is exact.
        let width = Int.random(in: 1 ... 402, using: &random)
        let height = seed % 5 == 0 ? 200 : Int.random(in: 1 ... 60, using: &random)
        let pixels = width * height
        let allowed = pixels * 5 / 1000
        let order = (0 ..< pixels).shuffled(using: &random)
        let changed = Dictionary(uniqueKeysWithValues: order.prefix(allowed + 1).enumerated().map { ($1, $0) })
        let noisy = Set(order.dropFirst(allowed + 1).filter { $0 % 3 == seed % 3 })
        let reference = try #require(Bitmap.make(width: width, height: height) { _, _ in Self.grey })
        func actual(changing count: Int) throws -> CGImage {
            try #require(Bitmap.make(width: width, height: height) { column, row in
                let index = row * width + column
                if let rank = changed[index], rank < count {
                    return Self.red
                }
                return noisy.contains(index) ? Self.nudged : Self.grey
            })
        }
        let label = "seed \(seed): \(width)×\(height), \(allowed) of \(pixels) may differ"
        #expect(try Self.diff(reference, actual(changing: allowed)) == nil, "\(label); \(allowed) failed")
        #expect(try Self.diff(reference, actual(changing: allowed + 1)) != nil, "\(label); \(allowed + 1) passed")
    }

    @Test(
        "A size change fails; its difference image spans both canvases and marks non-overlap plus real changes.",
        arguments: 0 ..< 24
    )
    func sizeChange_differenceImage_marksUnionOfCanvases(seed: Int) throws {
        var random = SplitMix64(seed: seed)
        let old = (width: Int.random(in: 1 ... 40, using: &random), height: Int.random(in: 1 ... 40, using: &random))
        var new = (width: Int.random(in: 1 ... 40, using: &random), height: Int.random(in: 1 ... 40, using: &random))
        if new == old {
            new.width += 1
        }
        let changedIndices = Set((0 ..< new.width * new.height).filter { _ in
            Int.random(in: 0 ..< 10, using: &random) == 0
        })
        let reference = try #require(Bitmap.make(width: old.width, height: old.height) { _, _ in Self.grey })
        let actual = try #require(Bitmap.make(width: new.width, height: new.height) { column, row in
            changedIndices.contains(row * new.width + column) ? Self.red : Self.grey
        })
        let label = "seed \(seed): \(old.width)×\(old.height) → \(new.width)×\(new.height)"
        let failure = try #require(Self.diff(reference, actual), "\(label) passed")
        #expect(failure.0.contains("\(new.width)×\(new.height)"), "\(label): message \(failure.0)")
        let difference = try Self.difference(in: failure.1)
        let canvas = (width: max(old.width, new.width), height: max(old.height, new.height))
        try #require(
            difference.width == canvas.width && difference.height == canvas.height,
            "\(label): \(difference.width)×\(difference.height)"
        )
        var wrong: [String] = []
        for row in 0 ..< canvas.height {
            for column in 0 ..< canvas.width {
                let inBoth = column < min(old.width, new.width) && row < min(old.height, new.height)
                let expected = !inBoth || changedIndices.contains(row * new.width + column)
                if (difference.pixel(column: column, row: row) == Self.magenta) != expected {
                    wrong.append("\(column),\(row)")
                }
            }
        }
        #expect(wrong.isEmpty, "\(label): \(wrong.count) pixels marked wrongly, first \(wrong.prefix(5))")
    }

    @Test("Same pixel count, other shape (20×10 against 10×20) fails with a 20×20 difference image.")
    func transposedSize_fails() throws {
        let reference = try #require(Bitmap.make(width: 10, height: 20) { _, _ in Self.grey })
        let actual = try #require(Bitmap.make(width: 20, height: 10) { _, _ in Self.grey })
        let failure = try #require(Self.diff(reference, actual), "a transposed image passed")
        let difference = try Self.difference(in: failure.1)
        #expect(difference.width == 20 && difference.height == 20)
    }

    @Test("A one-pixel image: identical passes, one changed pixel fails (0.5 % of 1 is 0).")
    func onePixel_boundary() throws {
        let reference = try #require(Bitmap.make(width: 1, height: 1) { _, _ in Self.grey })
        let changed = try #require(Bitmap.make(width: 1, height: 1) { _, _ in Self.red })
        #expect(Self.diff(reference, reference) == nil)
        #expect(Self.diff(reference, changed) != nil)
    }
}
