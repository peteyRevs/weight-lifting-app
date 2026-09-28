import CoreGraphics
import CoreText
import Foundation
import ImageIO
import LedgerSnapshotTesting
import SwiftUI
import UniformTypeIdentifiers

// Helpers for the F06 adversarial suites (slice 1: tokens + Archivo). Every expected value is
// derived in the test from docs/product-spec.md §8, the brief or the prototypes, never read back
// from the implementation.

/// An sRGB colour as the prototypes write it: gamma-encoded channels in 0…1 and an alpha.
nonisolated struct SRGB: Equatable, Sendable, CustomStringConvertible {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(_ hex: UInt32, alpha: Double = 1) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ resolved: Color.Resolved) {
        self.init(
            red: Double(resolved.red), green: Double(resolved.green),
            blue: Double(resolved.blue), alpha: Double(resolved.opacity)
        )
    }

    var description: String {
        let channels = [red, green, blue].map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
        return "#\(channels) @ \(String(format: "%.3f", alpha))"
    }

    /// Within half an 8-bit step per channel and 0.002 of alpha.
    func matches(_ other: Self) -> Bool {
        let step = 0.6 / 255
        return abs(red - other.red) <= step && abs(green - other.green) <= step
            && abs(blue - other.blue) <= step && abs(alpha - other.alpha) <= 0.002
    }

    /// Source-over onto an opaque `background` in gamma-encoded sRGB, the way a browser draws the
    /// prototype's `rgba(…)` text.
    func composited(over background: Self) -> Self {
        func mix(_ top: Double, _ bottom: Double) -> Double {
            top * alpha + bottom * (1 - alpha)
        }
        return Self(
            red: mix(red, background.red), green: mix(green, background.green),
            blue: mix(blue, background.blue), alpha: 1
        )
    }

    /// WCAG 2.x relative luminance.
    var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2.x contrast ratio of `self` (composited) against an opaque `background`.
    func contrast(on background: Self) -> Double {
        let foreground = composited(over: background).luminance
        let ground = background.luminance
        return (max(foreground, ground) + 0.05) / (min(foreground, ground) + 0.05)
    }
}

enum Resolve {
    /// A token resolved in a colour scheme through SwiftUI's own resolution path.
    static func color(_ color: Color, in scheme: ColorScheme) -> SRGB {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        return SRGB(color.resolve(in: environment))
    }
}

/// The Archivo file shipped in LedgerDesign's resource bundle, read directly so references are
/// built without going through `LedgerFont`.
enum ArchivoFile {
    static let fileName = "Archivo[wdth,wght].ttf"
    static let bundleName = "LedgerKit_LedgerDesign.bundle"
    /// OpenType tags 'wght' and 'wdth' as Core Text axis identifiers.
    static let weightTag = 0x7767_6874
    static let widthTag = 0x7764_7468

    static let url: URL? = {
        let roots = (Bundle.allBundles + Bundle.allFrameworks).flatMap { bundle in
            [bundle.bundleURL, bundle.resourceURL, bundle.bundleURL.deletingLastPathComponent()].compactMap(\.self)
        }
        return roots.lazy
            .map { $0.appending(path: bundleName).appending(path: fileName) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }()

    static let data: Data? = url.flatMap { try? Data(contentsOf: $0) } // nil → the test reports it

    static var descriptor: CTFontDescriptor? {
        data.flatMap { CTFontManagerCreateFontDescriptorFromData($0 as CFData) }
    }

    static var postScriptName: String? {
        descriptor.flatMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }
    }

    /// Archivo from the file at explicit axis values, optionally with tabular figures.
    static func font(size: CGFloat, weight: CGFloat, width: CGFloat, tabular: Bool = false) -> CTFont? {
        guard let base = descriptor else { return nil }
        var attributes: [CFString: Any] = [
            kCTFontVariationAttribute: [weightTag: weight, widthTag: width] as NSDictionary
        ]
        if tabular {
            attributes[kCTFontFeatureSettingsAttribute] = [
                [kCTFontOpenTypeFeatureTag: "tnum", kCTFontOpenTypeFeatureValue: 1] as NSDictionary
            ] as NSArray
        }
        let copy = CTFontDescriptorCreateCopyWithAttributes(base, attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(copy, size, nil)
    }

    static func swiftUIFont(size: CGFloat, weight: CGFloat, width: CGFloat, tabular: Bool = false) -> Font? {
        font(size: size, weight: weight, width: width, tabular: tabular).map { Font($0) }
    }
}

/// Pixel measurements of rendered views.
enum Probe {
    static func image(
        _ view: some View,
        scale: CGFloat = 1,
        dynamicTypeSize: DynamicTypeSize = .large,
        colorScheme: ColorScheme = .dark
    ) -> CGImage? {
        let renderer = ImageRenderer(
            content: view
                .environment(\.dynamicTypeSize, dynamicTypeSize)
                .environment(\.colorScheme, colorScheme)
        )
        renderer.scale = scale
        return renderer.cgImage
    }

    static func buffer(
        _ view: some View,
        scale: CGFloat = 1,
        dynamicTypeSize: DynamicTypeSize = .large,
        colorScheme: ColorScheme = .dark
    ) -> PixelBuffer? {
        image(view, scale: scale, dynamicTypeSize: dynamicTypeSize, colorScheme: colorScheme).flatMap(PixelBuffer.init)
    }

    /// `text` drawn white on black with a margin, so ink is every pixel brighter than half.
    static func inked(
        _ text: some View,
        scale: CGFloat,
        dynamicTypeSize: DynamicTypeSize = .large
    ) -> PixelBuffer? {
        buffer(
            text.foregroundStyle(Color.white).padding(8).background(Color.black),
            scale: scale, dynamicTypeSize: dynamicTypeSize
        )
    }

    /// Runs of consecutive rows that contain ink.
    static func inkRuns(_ buffer: PixelBuffer) -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        var start: Int?
        for row in 0 ... buffer.height {
            let inked = row < buffer.height && (0 ..< buffer.width).contains { column in
                buffer.pixels[row * buffer.width + column].red > 127
            }
            if inked, start == nil {
                start = row
            } else if !inked, let first = start {
                runs.append(first ... row - 1)
                start = nil
            }
        }
        return runs
    }

    /// Height in pixels of all ink, top of the first run to bottom of the last.
    static func inkHeight(_ buffer: PixelBuffer) -> Int? {
        let runs = inkRuns(buffer)
        guard let first = runs.first, let last = runs.last else { return nil }
        return last.upperBound - first.lowerBound + 1
    }

    /// Number of pixels brighter than half: how much ink a glyph run lays down.
    static func inkCount(_ buffer: PixelBuffer) -> Int {
        buffer.pixels.count { $0.red > 127 }
    }
}

/// Synthetic bitmaps and PNG data for exercising the snapshot comparator.
enum Bitmap {
    static func make(width: Int, height: Int, pixel: (Int, Int) -> UInt32) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0 ..< height {
            for column in 0 ..< width {
                let rgba = pixel(column, row)
                let offset = (row * width + column) * 4
                bytes[offset] = UInt8((rgba >> 24) & 0xFF)
                bytes[offset + 1] = UInt8((rgba >> 16) & 0xFF)
                bytes[offset + 2] = UInt8((rgba >> 8) & 0xFF)
                bytes[offset + 3] = UInt8(rgba & 0xFF)
            }
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData)
        else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    static func png(_ image: CGImage) -> Data {
        let data = NSMutableData()
        if let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
        return data as Data
    }
}
