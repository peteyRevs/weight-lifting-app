#if os(iOS)
    import Darwin
    import SwiftUI
    import UIKit

    /// One element of a hosted view's accessibility tree, as UIKit hands it to VoiceOver.
    public struct AccessibilityElementSnapshot: Equatable, Sendable, CustomStringConvertible {
        public let label: String
        public let value: String
        public let traits: UIAccessibilityTraits
        /// In the hosting window, in points. For a button this is its tappable area.
        public let frame: CGRect

        public var description: String {
            "\"\(label)\" value \"\(value)\" traits \(traits.rawValue) frame \(frame)"
        }
    }

    public extension View {
        /// The view's accessibility elements in VoiceOver's order, with the view laid out as
        /// `assertPhoneSnapshot` lays it out: `appearance` in SwiftUI's environment, the iPhone 17 width,
        /// its own height (F06 criterion 6, `ComponentAccessibilityTests`).
        func accessibilityElements(
            _ appearance: SnapshotAppearance = SnapshotAppearance(.light, .large)
        ) -> [AccessibilityElementSnapshot] {
            withAccessibilityElements(appearance) { elements in
                elements.map { element in
                    AccessibilityElementSnapshot(
                        label: element.accessibilityLabel ?? "",
                        value: element.accessibilityValue ?? "",
                        traits: element.accessibilityTraits,
                        frame: element.accessibilityFrame
                    )
                }
            }
        }

        /// Hosts the view as ``accessibilityElements(_:)`` does and hands `body` the live elements, for
        /// a test that performs their actions (`accessibilityActivate()`, `accessibilityIncrement()`).
        ///
        /// SwiftUI builds its accessibility tree only for an assistive technology, so this turns on
        /// UIKit's accessibility automation while the view is hosted, and restores it afterwards.
        func withAccessibilityElements<Result>(
            _ appearance: SnapshotAppearance = SnapshotAppearance(.light, .large),
            _ body: ([NSObject]) -> Result
        ) -> Result {
            let width = SnapshotConfig.phoneWidth
            let host = UIHostingController(rootView: snapshotAppearance(appearance).frame(width: width))
            return AccessibilityAutomation.whileEnabled {
                let window = SceneLessWindow.make(frame: CGRect(x: 0, y: 0, width: width, height: 2000))
                window.rootViewController = host
                window.isHidden = false
                defer {
                    window.isHidden = true
                    window.rootViewController = nil
                }
                host.view.layoutIfNeeded()
                return body(elements(in: host.view))
            }
        }
    }

    /// Depth first, the way VoiceOver walks a container: an element, else its `accessibilityElements`,
    /// else its indexed elements, else (a view) its subviews.
    private func elements(in object: NSObject) -> [NSObject] {
        if object.isAccessibilityElement {
            return [object]
        }
        if let children = object.accessibilityElements as? [NSObject], !children.isEmpty {
            return children.flatMap(elements(in:))
        }
        let count = object.accessibilityElementCount()
        if count != NSNotFound, count > 0 {
            return (0 ..< count).compactMap { object.accessibilityElement(at: $0) as? NSObject }.flatMap(elements(in:))
        }
        return (object as? UIView)?.subviews.flatMap(elements(in:)) ?? []
    }

    /// `_AXSSetAutomationEnabled` in libAccessibility: private, test-only. It is how KIF and
    /// AccessibilitySnapshot make UIKit and SwiftUI build their accessibility trees in a test process;
    /// without it a hosted SwiftUI view reports no elements (checked on iOS 26.5, F06 slice 2).
    private enum AccessibilityAutomation {
        typealias IsEnabled = @convention(c) () -> Int32
        typealias SetEnabled = @convention(c) (Int32) -> Void

        static func whileEnabled<Result>(_ body: () -> Result) -> Result {
            guard let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
                  let getter = dlsym(library, "_AXSAutomationEnabled"),
                  let setter = dlsym(library, "_AXSSetAutomationEnabled")
            else {
                return body() // the tree stays empty, so every lookup in the test fails and says why
            }
            let setEnabled = unsafeBitCast(setter, to: SetEnabled.self)
            let wasEnabled = unsafeBitCast(getter, to: IsEnabled.self)()
            setEnabled(1)
            defer { setEnabled(wasEnabled) }
            return body()
        }
    }

    /// A window without a scene. iOS 26 deprecates `UIWindow(frame:)` for `init(windowScene:)`, but a
    /// package test process has no scene to pass (`connectedScenes` is empty), so this is the one way
    /// to make a window here, as swift-snapshot-testing does for its snapshots. The protocol keeps the
    /// deprecated call inside one declaration marked deprecated itself.
    private protocol WindowFactory {
        func window(frame: CGRect) -> UIWindow
    }

    private struct SceneLessWindow: WindowFactory {
        static func make(frame: CGRect) -> UIWindow {
            let factory: any WindowFactory = SceneLessWindow()
            return factory.window(frame: frame)
        }

        @available(iOS, deprecated: 26.0, message: "A package test process has no window scene")
        func window(frame: CGRect) -> UIWindow {
            UIWindow(frame: frame)
        }
    }
#endif
