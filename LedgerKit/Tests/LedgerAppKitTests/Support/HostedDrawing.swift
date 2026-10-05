#if os(macOS)
    import AppKit
#endif
@testable import LedgerSnapshotTesting
import SwiftUI
#if os(iOS)
    import UIKit
#endif

/// What a view draws when it is hosted in a window, as `renderPreview` hosts it, for a test that must tell a
/// screen from the ground colour alone. `renderPreview` says that a view was hosted and did not trap; on iOS
/// its picture is empty whatever the view is (`drawHierarchy` draws nothing in a window without a scene:
/// measured on the iOS 27.0 simulator, F08 S3 touch-up). Here the hosting view's layer is rendered, which
/// draws what SwiftUI drew. The window is `LedgerSnapshotTesting`'s internal `SceneLessWindow`, hence that
/// module's `@testable` import.
@MainActor
enum HostedDrawing {
    /// Whether the hosted view's picture holds more than one colour: a title, a bar, a rule. A view that draws
    /// its background alone, as the root does until its gate has an answer, is one flat colour.
    ///
    /// The pixels are compared here, to one `Bool`: a pixel buffer is never handed to an expectation, which
    /// would write every pixel of it into the result when it fails.
    static func isMoreThanOneColour(_ view: some View, size: CGSize) -> Bool {
        guard let pixels = pixels(of: view, size: size)?.pixels, let first = pixels.first else {
            return false
        }
        return pixels.contains { $0 != first }
    }

    private static func pixels(of view: some View, size: CGSize) -> PixelBuffer? {
        #if os(iOS)
            let host = UIHostingController(rootView: view)
            let window = SceneLessWindow.make(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { context in
                host.view.layer.render(in: context.cgContext)
            }
            return image.cgImage.flatMap(PixelBuffer.init)
        #elseif os(macOS)
            let host = NSHostingView(rootView: view)
            host.frame = CGRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.contentView = nil }
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                return nil
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            return bitmap.cgImage.flatMap(PixelBuffer.init)
        #else
            return RenderedImage.render(view, width: size.width, height: size.height).flatMap(PixelBuffer.init)
        #endif
    }
}
