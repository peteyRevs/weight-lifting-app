#if os(iOS) && DEBUG
    import LedgerDesign
    @testable import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// Draws views as a phone draws them and counts colours, for the orange audit. A view is hosted in a
    /// window and its layer is rendered, as swift-snapshot-testing draws the references: `ImageRenderer` draws
    /// a text field as a yellow placeholder, and `drawHierarchy` draws nothing in a process with no host app.
    /// (`SceneLessWindow` is internal to `LedgerSnapshotTesting`, hence the `@testable` import.)
    enum ProgramDrawing {
        /// `view` at the iPhone 17 width and its own height, on the ground, at 1×.
        static func pixels(of view: some View, _ colorScheme: ColorScheme) throws -> PixelBuffer {
            let width = SnapshotConfig.phoneWidth
            let content = view
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .background(LedgerColor.ground)
                .environment(\.colorScheme, colorScheme)
            let host = UIHostingController(rootView: content)
            host.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
            host.safeAreaRegions = []
            let size = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            let window = SceneLessWindow.make(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = SnapshotConfig.scale
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image {
                host.view.layer.render(in: $0.cgContext)
            }
            return try #require(image.cgImage.flatMap(PixelBuffer.init))
        }

        /// How many pixels of `view` are orange in hue: far more red than green, more green than blue. Every
        /// grey of the grounds and the inks has the three alike, and thin text need not reach a token's exact
        /// colour at 1×, so the count goes by hue. Both accents pass: #FF5B22, and #B2390E, the text's on paper.
        static func orangePixels(in view: some View, _ colorScheme: ColorScheme) throws -> Int {
            try pixels(of: view, colorScheme).pixels.count { pixel in
                Int(pixel.red) > Int(pixel.green) + 40 && Int(pixel.green) > Int(pixel.blue) + 15 && pixel.red > 110
            }
        }
    }
#endif
