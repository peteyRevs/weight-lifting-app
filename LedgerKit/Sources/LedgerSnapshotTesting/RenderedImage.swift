import CoreGraphics
import SwiftUI

/// Renders SwiftUI with `ImageRenderer`. swift-snapshot-testing 1.19 has no image strategy on
/// watchOS (its view and `UIImage` strategies are iOS/tvOS only), so watch snapshots and pixel
/// measurements go through here on every platform.
public enum RenderedImage {
    /// Rasterises `view` at 1× in the given appearance. `width`/`height` are the proposed size;
    /// `nil` lets the view take its ideal size in that dimension. The environment is set
    /// explicitly because `ImageRenderer` does not inherit the simulator's text size.
    public static func render(
        _ view: some View,
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        colorScheme: ColorScheme = .dark,
        dynamicTypeSize: DynamicTypeSize = SnapshotConfig.referenceDynamicTypeSize
    ) -> CGImage? {
        let renderer = ImageRenderer(
            content: view
                .environment(\.colorScheme, colorScheme)
                .environment(\.dynamicTypeSize, dynamicTypeSize)
        )
        renderer.scale = SnapshotConfig.scale
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        return renderer.cgImage
    }
}

/// One 8-bit sRGB pixel (premultiplied alpha).
public struct Pixel: Equatable, Sendable {
    public let red, green, blue, alpha: UInt8

    /// Whether any colour channel differs from `other` by more than `tolerance`.
    public func differs(from other: Pixel, by tolerance: Int) -> Bool {
        abs(Int(red) - Int(other.red)) > tolerance
            || abs(Int(green) - Int(other.green)) > tolerance
            || abs(Int(blue) - Int(other.blue)) > tolerance
    }

    /// An opaque pixel from a `0xRRGGBB` hex value.
    public init(hex: UInt32) {
        self.init(red: UInt8((hex >> 16) & 0xFF), green: UInt8((hex >> 8) & 0xFF), blue: UInt8(hex & 0xFF), alpha: 0xFF)
    }

    init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        (self.red, self.green, self.blue, self.alpha) = (red, green, blue, alpha)
    }
}

/// An image decoded to 8-bit premultiplied sRGB, for pixel measurements and diffs.
public struct PixelBuffer: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [Pixel]

    public init?(_ image: CGImage) {
        let (imageWidth, imageHeight) = (image.width, image.height)
        var bytes = [UInt8](repeating: 0, count: imageWidth * imageHeight * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: buffer.baseAddress, width: imageWidth, height: imageHeight, bitsPerComponent: 8,
                      bytesPerRow: imageWidth * 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            return true
        }
        guard drawn else { return nil }
        width = imageWidth
        height = imageHeight
        pixels = stride(from: 0, to: bytes.count, by: 4).map { offset in
            Pixel(red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2], alpha: bytes[offset + 3])
        }
    }

    public func pixel(column: Int, row: Int) -> Pixel {
        pixels[row * width + column]
    }

    /// The horizontal extent, in pixels, of everything that differs from `background` by more
    /// than `tolerance` in any channel: the "ink" of text drawn on a plain ground.
    public func inkedColumns(differingFrom background: Pixel, tolerance: Int = 24) -> ClosedRange<Int>? {
        let inked = (0 ..< width).filter { column in
            (0 ..< height).contains { row in pixel(column: column, row: row).differs(from: background, by: tolerance) }
        }
        guard let first = inked.first, let last = inked.last else { return nil }
        return first ... last
    }
}
