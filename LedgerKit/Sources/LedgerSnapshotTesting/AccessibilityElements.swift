#if os(iOS)
    import Darwin
    import SwiftUI
    import Testing
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
        ///
        /// **Scroll views.** The reader cannot see inside a scroll view (docs/testing-strategy.md §2.6), and
        /// the two readers below share its walk and its rule:
        /// - By default it fails the test when the view holds one: read the page a screen scrolls, not the
        ///   screen. What it returns then is only what stands outside the scroll view.
        /// - With `outsideScrollViews: true` it leaves every scroll view out, content and all, without
        ///   failing, and returns the elements outside them. That is for a caller that knowingly reads the
        ///   pinned parts around a scroll view (a sheet's title over its scrolling rows), and never for
        ///   reading a page: what scrolls is not in the result.
        func accessibilityElements(
            _ appearance: SnapshotAppearance = SnapshotAppearance(.light, .large),
            outsideScrollViews: Bool = false
        ) -> [AccessibilityElementSnapshot] {
            withAccessibilityElements(appearance, outsideScrollViews: outsideScrollViews) { elements in
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

        /// Hosts the view as ``accessibilityElements(_:outsideScrollViews:)`` does and hands `body` the live
        /// elements, for a test that performs their actions (`accessibilityActivate()`,
        /// `accessibilityIncrement()`). `outsideScrollViews` is that reader's: false fails the test on a
        /// scroll view, true reads only what stands outside one.
        func withAccessibilityElements<Result>(
            _ appearance: SnapshotAppearance = SnapshotAppearance(.light, .large),
            outsideScrollViews: Bool = false,
            _ body: ([NSObject]) -> Result
        ) -> Result {
            withLiveAccessibilityElements(appearance, outsideScrollViews: outsideScrollViews) { read in
                body(read())
            }
        }

        /// Hosts the view and hands `body` a reader that lays the view out again and returns its
        /// elements, for a test that changes the view's state through an element (an adjustable's
        /// increment) and then reads what VoiceOver would announce. `outsideScrollViews` is
        /// ``accessibilityElements(_:outsideScrollViews:)``'s, for every read `body` makes.
        ///
        /// SwiftUI builds its accessibility tree only for an assistive technology, so this turns on
        /// UIKit's accessibility automation while the view is hosted, and restores it afterwards.
        func withLiveAccessibilityElements<Result>(
            _ appearance: SnapshotAppearance = SnapshotAppearance(.light, .large),
            outsideScrollViews: Bool = false,
            _ body: (_ read: () -> [NSObject]) -> Result
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
                return body {
                    host.view.setNeedsLayout()
                    host.view.layoutIfNeeded()
                    return elements(in: host.view, outsideScrollViews: outsideScrollViews)
                }
            }
        }
    }

    /// Depth first, the way VoiceOver walks a container: an element, else its `accessibilityElements`,
    /// else its indexed elements, else (a view) its subviews.
    ///
    /// A scroll view that yields no element fails the test. In a package test process a hosted SwiftUI
    /// `ScrollView` hands UIKit no accessibility children (measured on iOS 27.0, F08 S2: its
    /// `accessibilityElements` are nil, its element count is 0, and no subview has any), so the walk would
    /// return what stands around the scroll view and nothing of what scrolls, in silence, and a tree pinned
    /// from that reading would pin the wrong thing.
    ///
    /// With `outsideScrollViews` the caller has said that the parts around a scroll view are all it reads:
    /// the walk then leaves each scroll view out whole, and records nothing.
    private func elements(in object: NSObject, outsideScrollViews: Bool) -> [NSObject] {
        if object.isAccessibilityElement {
            return [object]
        }
        if outsideScrollViews, object is UIScrollView {
            return []
        }
        let found = children(of: object).flatMap { elements(in: $0, outsideScrollViews: outsideScrollViews) }
        if found.isEmpty, object is UIScrollView {
            // Loud, not silent, for the same reason as the automation switch below.
            Issue.record(
                """
                The accessibility reader cannot see inside a scroll view (\(type(of: object))): it read \
                nothing of what scrolls. Host the page the scroll view holds, without the scroll view, \
                and read that; the screen is its pinned parts plus `ScrollView { Page }` \
                (docs/testing-strategy.md §2.6, "A screen that scrolls"). A test that reads only the \
                parts around a scroll view says so with `outsideScrollViews: true`, which is never the \
                way to read a page: what scrolls is then missing from the result.
                """
            )
        }
        return found
    }

    /// What `object` holds, as the walk meets it: its `accessibilityElements`, else its indexed elements,
    /// else (a view) its subviews.
    private func children(of object: NSObject) -> [NSObject] {
        if let listed = object.accessibilityElements as? [NSObject], !listed.isEmpty {
            return listed
        }
        let count = object.accessibilityElementCount()
        if count != NSNotFound, count > 0 {
            return (0 ..< count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
        }
        return (object as? UIView)?.subviews ?? []
    }

    /// `_AXSSetAutomationEnabled` in libAccessibility: private, test-only. It is how KIF and
    /// AccessibilitySnapshot make UIKit and SwiftUI build their accessibility trees in a test process;
    /// without it a hosted SwiftUI view reports no elements (checked on iOS 26.5, F06 slice 2).
    private enum AccessibilityAutomation {
        /// `Boolean _AXSAutomationEnabled(void)` and `void _AXSSetAutomationEnabled(Boolean)`; `Boolean` is
        /// an unsigned char.
        typealias IsEnabled = @convention(c) () -> UInt8
        typealias SetEnabled = @convention(c) (UInt8) -> Void

        static func whileEnabled<Result>(_ body: () -> Result) -> Result {
            guard let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
                  let getter = dlsym(library, "_AXSAutomationEnabled"),
                  let setter = dlsym(library, "_AXSSetAutomationEnabled")
            else {
                // Loud, not silent: without the switch every tree is empty, and a test that expects
                // no elements of some kind would pass on nothing (review R2-N10).
                Issue.record("libAccessibility's automation switch is unavailable; the accessibility tree is empty")
                return body()
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

    struct SceneLessWindow: WindowFactory {
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
