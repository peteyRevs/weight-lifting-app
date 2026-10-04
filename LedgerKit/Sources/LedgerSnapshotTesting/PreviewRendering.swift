import Dependencies
import SwiftUI
#if os(iOS)
    import UIKit
#endif

/// Builds a preview's content, lays it out at `size` and draws it, for the preview smoke tests (F07 criterion 8), and
/// says whether it drew. It runs in swift-dependencies' `preview` context, as Xcode runs a `#Preview`, so a view that
/// reads a key gets its seeded preview value (F07 S1), not the test value that would fail the test.
///
/// On iOS the view is hosted in a window, as a preview shows it: an `ImageRenderer` that drew a UIKit-backed container
/// (a `NavigationStack`, a `ScrollView` with an appearance action) traps when it is released (measured on the iOS 27.0
/// simulator). Elsewhere it is drawn with `RenderedImage`.
@MainActor
public func renderPreview(size: CGSize, @ViewBuilder _ content: () -> some View) -> Bool {
    withDependencies {
        $0.context = .preview
    } operation: {
        draw(content(), size: size)
    }
}

@MainActor
private func draw(_ view: some View, size: CGSize) -> Bool {
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
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        return image.size == size
    #else
        return RenderedImage.render(view, width: size.width, height: size.height) != nil
    #endif
}
