import CoreGraphics
import Foundation
import ImageIO
import SnapshotTesting
import UniformTypeIdentifiers

public extension Snapshotting where Value == CGImage, Format == Data {
    /// PNG references compared with ``SnapshotConfig``'s precision: a pixel matches when its
    /// CIE76 ΔE is at most `(1 − perceptualPrecision) × 100`, the threshold swift-snapshot-testing
    /// applies with Core Image on iOS.
    static var png: Snapshotting {
        Snapshotting(pathExtension: "png", diffing: .pixels, snapshot: PNG.encode)
    }
}

extension Diffing where Value == Data {
    static var pixels: Diffing {
        .diff(toData: { $0 }, fromData: { $0 }, diffV2: { reference, actual in
            let inputs: [DiffAttachment] = [.data(actual, name: "actual.png"), .data(reference, name: "reference.png")]
            guard let old = PNG.decode(reference), let new = PNG.decode(actual) else {
                return ("Could not decode the reference or the new image as PNG", inputs)
            }
            guard let failure = PixelComparison.failure(reference: old, actual: new) else { return nil }
            let difference = failure.difference.map { DiffAttachment.data(PNG.encode($0), name: "difference.png") }
            return (failure.message, inputs + [difference].compactMap(\.self))
        })
    }
}

enum PixelComparison {
    /// Why `actual` does not match `reference`, and where; nil when it matches. The difference
    /// image lays both on one canvas the size of the larger: the reference dimmed, mismatches in
    /// magenta, including every pixel only one of the two images has (a size change).
    static func failure(reference: CGImage, actual: CGImage) -> (message: String, difference: CGImage?)? {
        guard let old = PixelBuffer(reference), let new = PixelBuffer(actual) else {
            return ("Could not decode the images to compare them", nil)
        }
        let threshold = Double(100 - 100 * SnapshotConfig.perceptualPrecision)
        let (width, height) = (max(old.width, new.width), max(old.height, new.height))
        let mismatches = (0 ..< width * height).map { index in
            guard let lhs = old[index % width, index / width], let rhs = new[index % width, index / width] else {
                return true
            }
            return lhs != rhs && deltaE(lhs, rhs) > threshold
        }
        let mismatched = mismatches.count { $0 }
        let sameSize = old.width == new.width && old.height == new.height
        // Whole pixels against the precision in parts per million, so no rounding moves the
        // boundary: 0.995 lets exactly floor(0.5 %) of the pixels differ.
        let allowedPerMillion = Int(((1 - Double(SnapshotConfig.precision)) * 1_000_000).rounded())
        if sameSize, mismatched * 1_000_000 <= mismatches.count * allowedPerMillion {
            return nil
        }
        let difference = PixelBuffer(width: width, height: height, pixels: mismatches.indices.map { index in
            guard !mismatches[index], let pixel = old[index % width, index / width] else { return Pixel(hex: 0xFF00FF) }
            return Pixel(red: pixel.red / 3, green: pixel.green / 3, blue: pixel.blue / 3, alpha: 0xFF)
        })
        let matching = Double(mismatches.count - mismatched) / Double(mismatches.count)
        let message = sameSize
            ? "\(mismatched) pixels differ by more than ΔE \(threshold): \(matching) match, "
            + "\(SnapshotConfig.precision) required"
            : "The image size differs from the reference: \(new.width)×\(new.height) against \(old.width)×\(old.height)"
        return (message, difference.cgImage)
    }

    /// CIE76 distance between two pixels; an alpha difference counts as a full-scale difference.
    static func deltaE(_ lhs: Pixel, _ rhs: Pixel) -> Double {
        let alphaDelta = abs(Double(lhs.alpha) - Double(rhs.alpha)) / 255 * 100
        let (old, new) = (Lab(lhs), Lab(rhs))
        let lightness = old.lightness - new.lightness
        let greenRed = old.greenRed - new.greenRed
        let blueYellow = old.blueYellow - new.blueYellow
        return max(alphaDelta, (lightness * lightness + greenRed * greenRed + blueYellow * blueYellow).squareRoot())
    }
}

private extension PixelBuffer {
    /// The pixel at `column`, `row`, or nil outside the image.
    subscript(column: Int, row: Int) -> Pixel? {
        column < width && row < height ? pixel(column: column, row: row) : nil
    }
}

/// CIE L*a*b* (D65) of an sRGB pixel.
struct Lab {
    let lightness, greenRed, blueYellow: Double

    init(_ pixel: Pixel) {
        func linear(_ value: UInt8) -> Double {
            let channel = Double(value) / 255
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        func pivot(_ value: Double) -> Double {
            value > 216.0 / 24389 ? cbrt(value) : (24389.0 / 27 * value + 16) / 116
        }
        let (red, green, blue) = (linear(pixel.red), linear(pixel.green), linear(pixel.blue))
        let xyzX = pivot((0.4124 * red + 0.3576 * green + 0.1805 * blue) / 0.95047)
        let xyzY = pivot(0.2126 * red + 0.7152 * green + 0.0722 * blue)
        let xyzZ = pivot((0.0193 * red + 0.1192 * green + 0.9505 * blue) / 1.08883)
        lightness = 116 * xyzY - 16
        greenRed = 500 * (xyzX - xyzY)
        blueYellow = 200 * (xyzY - xyzZ)
    }
}

enum PNG {
    static func encode(_ image: CGImage) -> Data {
        let data = NSMutableData()
        if let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
        return data as Data
    }

    static func decode(_ data: Data) -> CGImage? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }
}
