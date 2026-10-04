import SwiftUI
#if os(iOS)
    import UIKit
#endif

/// Lays a preview's content out at `size` and draws it, for the preview smoke tests (F07 criterion 8), and says
/// whether it drew. On iOS the view is hosted in a window, as a preview shows it: an `ImageRenderer` that drew a
/// UIKit-backed container (a `NavigationStack`, a `ScrollView` with an appearance action) traps when it is released
/// (measured on the iOS 27.0 simulator). Elsewhere it is drawn with `RenderedImage`.
@MainActor
public func renderPreview(_ view: some View, size: CGSize) -> Bool {
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
