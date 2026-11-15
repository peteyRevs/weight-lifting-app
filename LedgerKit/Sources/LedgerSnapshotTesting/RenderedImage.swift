import CoreGraphics
import Foundation
import SwiftUI
import Testing

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
        _ = isWarm
        let renderer = ImageRenderer(
            content: view
                .environment(\.colorScheme, colorScheme)
                .environment(\.dynamicTypeSize, dynamicTypeSize)
        )
        renderer.scale = SnapshotConfig.scale
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        return renderer.cgImage
    }

    /// The process's first `ImageRenderer` render, of an opaque square, before any render a test reads. On the
    /// hosted runner the first render of a test process has come back undrawn, and only the first: the orange
    /// audit's estimate (nightly 43692994418, FeatureLibraryTests) and the onboarding pill's whole picture
    /// (PR 43695702125, both attempts; PR 43157142440), each the first render of its target's process, while
    /// every later render in the same process drew. A developer Mac has never shown it, alone or under load.
    /// This render takes no part in any verdict, and is never repeated: one that draws nothing is recorded as a
    /// warning, which fails nothing, so a runner's bundle shows when it happened.
    private static let isWarm: Bool = {
        let probe = ImageRenderer(content: Color.black.frame(width: 8, height: 8))
        probe.scale = SnapshotConfig.scale
        let buffer = probe.cgImage.flatMap { PixelBuffer($0) }
        let isDrawn = buffer?.pixels.contains { $0.alpha == 0xFF } == true
        if !isDrawn {
            Issue.record("the process's first ImageRenderer render drew nothing", severity: .warning)
        }
        return isDrawn
    }()
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

    /// Whether a `Pixel` is laid out as an RGBA pixel of a bitmap, which `PixelBuffer.init(_:)` draws into.
    static let isPackedRGBA = MemoryLayout<Pixel>.stride == 4
        && MemoryLayout<Pixel>.offset(of: \.red) == 0 && MemoryLayout<Pixel>.offset(of: \.green) == 1
        && MemoryLayout<Pixel>.offset(of: \.blue) == 2 && MemoryLayout<Pixel>.offset(of: \.alpha) == 3
}

/// An image decoded to 8-bit premultiplied sRGB, for pixel measurements and diffs.
public struct PixelBuffer: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [Pixel]

    /// `image` drawn into the pixels' own storage: a `Pixel` is its four bytes in RGBA order, so the context's
    /// premultiplied RGBA rows are the array as it is. Copying the bytes into the array one pixel at a time
    /// took about as long as the drawing in the unoptimized test builds (2026-10-21,
    /// `tasks/chores/ci-test-time-2.md`).
    public init?(_ image: CGImage) {
        precondition(Pixel.isPackedRGBA, "Pixel is no longer four bytes in RGBA order")
        let (imageWidth, imageHeight) = (image.width, image.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var drawn = false
        let drawnPixels = [Pixel](unsafeUninitializedCapacity: imageWidth * imageHeight) { buffer, count in
            let bytes = UnsafeMutableRawBufferPointer(buffer)
            bytes.initializeMemory(as: UInt8.self, repeating: 0)
            count = buffer.count
            guard let context = CGContext(
                data: bytes.baseAddress, width: imageWidth, height: imageHeight, bitsPerComponent: 8,
                bytesPerRow: imageWidth * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            drawn = true
        }
        guard drawn else { return nil }
        (width, height, pixels) = (imageWidth, imageHeight, drawnPixels)
    }

    init(width: Int, height: Int, pixels: [Pixel]) {
        (self.width, self.height, self.pixels) = (width, height, pixels)
    }

    /// The buffer as an sRGB image (premultiplied RGBA).
    public var cgImage: CGImage? {
        let bytes = pixels.flatMap { [$0.red, $0.green, $0.blue, $0.alpha] }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData)
        else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
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
