import CoreGraphics
import Foundation
import ImageIO
import LedgerSnapshotTesting
import SnapshotTesting
import Testing

/// An image size for the precision boundary: `0.5 %` of its pixels, rounded down, may differ.
nonisolated struct PrecisionCase: Sendable, CustomTestStringConvertible {
    let width: Int
    let height: Int

    var pixels: Int {
        width * height
    }

    /// Integer arithmetic, so the boundary itself carries no floating-point error.
    var allowed: Int {
        pixels * 5 / 1000
    }

    var testDescription: String {
        "\(width)×\(height), \(allowed) may differ"
    }

    /// 402 pt is the phone snapshot width; 402×999 is the first phone-width size where a `Float`
    /// match fraction rounds one pixel too many up to 0.995.
    static let all = [
        Self(width: 200, height: 1), Self(width: 999, height: 1), Self(width: 1000, height: 1),
        Self(width: 1001, height: 1), Self(width: 402, height: 874), Self(width: 402, height: 999)
    ]
}

extension RenderingSuites {
    /// Round 2: the `.png` comparator after the fix — its 0.995 boundary from both sides at several
    /// image sizes, and the difference image it now attaches.
    @Suite("Snapshot diff (adversarial, round 2)", .tags(.design, .snapshot))
    struct SnapshotDiffAdversarialTests {
        static let grey: UInt32 = 0x8080_80FF
        static let red: UInt32 = 0xFF00_00FF

        static func diff(_ reference: CGImage, _ actual: CGImage) -> (String, [DiffAttachment])? {
            Snapshotting<CGImage, Data>.png.diffing.diffV2(Bitmap.png(reference), Bitmap.png(actual))
        }

        static func attachment(named name: String, in attachments: [DiffAttachment]) -> Data? {
            attachments.lazy.compactMap { attachment -> Data? in
                if case let .data(data, attachmentName) = attachment, attachmentName == name {
                    return data
                }
                return nil
            }.first
        }

        /// `width`×`height` grey image whose first `changed` pixels (row-major) are red.
        static func image(_ size: PrecisionCase, changed: Int) -> CGImage? {
            Bitmap.make(width: size.width, height: size.height) { column, row in
                row * size.width + column < changed ? red : grey
            }
        }

        @Test("At each size, floor(0.5 %) differing pixels pass and one more fails.", arguments: PrecisionCase.all)
        func precision_boundary_holdsFromBothSides(size: PrecisionCase) throws {
            let reference = try #require(Self.image(size, changed: 0))
            let atLimit = try #require(Self.image(size, changed: size.allowed))
            let overLimit = try #require(Self.image(size, changed: size.allowed + 1))
            #expect(Self.diff(reference, atLimit) == nil, "\(size.allowed) of \(size.pixels) differing failed")
            #expect(Self.diff(reference, overLimit) != nil, "\(size.allowed + 1) of \(size.pixels) differing passed")
        }

        @Test("The difference image has the reference's size and marks exactly the pixels beyond ΔE 2.")
        func differenceImage_marksExactlyTheMismatches() throws {
            let (width, height) = (24, 12)
            let changed: (Int, Int) -> Bool = { column, row in (column + 2 * row) % 7 == 0 }
            // Every third remaining pixel moves by one grey step (ΔE < 2): it matches and stays unmarked.
            let nudged: (Int, Int) -> Bool = { column, row in !changed(column, row) && (column + row) % 3 == 0 }
            let reference = try #require(Bitmap.make(width: width, height: height) { _, _ in Self.grey })
            let actual = try #require(Bitmap.make(width: width, height: height) { column, row in
                changed(column, row) ? Self.red : nudged(column, row) ? 0x8181_81FF : Self.grey
            })
            let failure = try #require(Self.diff(reference, actual))
            let data = try #require(Self.attachment(named: "difference.png", in: failure.1), "no difference.png")
            let decoded = try #require(CGImageSourceCreateWithData(data as CFData, nil).flatMap {
                CGImageSourceCreateImageAtIndex($0, 0, nil)
            })
            let difference = try #require(PixelBuffer(decoded))
            #expect(difference.width == width && difference.height == height)
            let magenta = Pixel(hex: 0xFF00FF)
            for row in 0 ..< height {
                for column in 0 ..< width {
                    let marked = difference.pixel(column: column, row: row) == magenta
                    #expect(marked == changed(column, row), "pixel \(column),\(row) marked \(marked)")
                }
            }
        }

        @Test("A size change still shows where the images differ (difference image), not just the two inputs.")
        func sizeChange_attachesDifferenceImage() throws {
            let reference = try #require(Self.image(PrecisionCase(width: 100, height: 10), changed: 0))
            let actual = try #require(Self.image(PrecisionCase(width: 104, height: 10), changed: 0))
            let failure = try #require(Self.diff(reference, actual))
            #expect(Self.attachment(named: "actual.png", in: failure.1) != nil)
            #expect(Self.attachment(named: "reference.png", in: failure.1) != nil)
            #expect(
                Self.attachment(named: "difference.png", in: failure.1) != nil,
                "size mismatch: no difference image"
            )
        }

        @Test("An undecodable reference still attaches the new rendering, so a reviewer can see it.")
        func corruptReference_attachesActual() throws {
            let actual = try #require(Self.image(PrecisionCase(width: 10, height: 1), changed: 0))
            let failure = try #require(Snapshotting<CGImage, Data>.png.diffing.diffV2(
                Data("x".utf8),
                Bitmap.png(actual)
            ))
            #expect(Self.attachment(named: "actual.png", in: failure.1) == Bitmap.png(actual))
        }
    }
}
