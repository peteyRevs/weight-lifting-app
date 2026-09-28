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
    /// Why `actual` does not match `reference`, and where (the reference dimmed, mismatches in
    /// magenta); nil when it matches.
    static func failure(reference: CGImage, actual: CGImage) -> (message: String, difference: CGImage?)? {
        guard reference.width == actual.width, reference.height == actual.height else {
            let sizes = "\(actual.width)×\(actual.height) against \(reference.width)×\(reference.height)"
            return ("The image size differs from the reference: \(sizes)", nil)
        }
        guard let old = PixelBuffer(reference), let new = PixelBuffer(actual) else {
            return ("Could not decode the images to compare them", nil)
        }
        // Float arithmetic, like the thresholds: 995 of 1000 pixels is exactly `precision` 0.995.
        let threshold = Double(100 - 100 * SnapshotConfig.perceptualPrecision)
        let mismatches = zip(old.pixels, new.pixels).map { $0 != $1 && deltaE($0, $1) > threshold }
        let mismatched = mismatches.count { $0 }
        let matching = Float(mismatches.count - mismatched) / Float(mismatches.count)
        guard matching < SnapshotConfig.precision else { return nil }
        let difference = PixelBuffer(width: old.width, height: old.height, pixels: zip(old.pixels, mismatches).map {
            $1 ? Pixel(hex: 0xFF00FF) : Pixel(red: $0.red / 3, green: $0.green / 3, blue: $0.blue / 3, alpha: 0xFF)
        })
        let message = "\(mismatched) pixels differ by more than ΔE \(threshold): \(matching) match, "
            + "\(SnapshotConfig.precision) required"
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
