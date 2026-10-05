#if os(iOS)
    import Darwin
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // F08 S2 adversarial round 1: hosting the screen as a phone shows it. `LedgerSnapshotTesting`'s
    // `accessibilityElements` lays a view out at the iPhone 17's width and its own height; criterion 10 is about
    // a screen of a phone's size, so this hosts the view in a window of that size with that phone's safe area.

    /// A phone the screen is laid out on: its size in points and the safe area of a full-screen window.
    nonisolated struct PhoneFrame: Sendable, CustomStringConvertible {
        let name: String
        let width: CGFloat
        let height: CGFloat
        let safeTop: CGFloat
        let safeBottom: CGFloat

        var description: String {
            name
        }

        /// The narrowest and shortest phone iOS 26 runs on: iPhone SE (2nd and 3rd generation).
        static let smallest = PhoneFrame(name: "SE 375x667", width: 375, height: 667, safeTop: 20, safeBottom: 0)
        /// As narrow, with a sensor housing and a home indicator: iPhone 12 mini and 13 mini.
        static let mini = PhoneFrame(name: "mini 375x812", width: 375, height: 812, safeTop: 50, safeBottom: 34)
        /// The phone the snapshot references are drawn for.
        static let seventeen = PhoneFrame(name: "17 402x874", width: 402, height: 874, safeTop: 62, safeBottom: 34)

        /// The same phone with room for any text: what each element measures when nothing presses on it.
        var tall: PhoneFrame {
            PhoneFrame(name: "\(name), tall", width: width, height: 6000, safeTop: safeTop, safeBottom: safeBottom)
        }
    }

    /// One element as VoiceOver gets it.
    nonisolated struct Spoken: Sendable, CustomStringConvertible {
        let label: String
        let value: String
        let traits: UIAccessibilityTraits
        let frame: CGRect

        /// What VoiceOver says before the traits: the label, then the value.
        var text: String {
            [label, value].filter { !$0.isEmpty }.joined(separator: ", ")
        }

        var isButton: Bool {
            traits.contains(.button)
        }

        var isSelected: Bool {
            traits.contains(.selected)
        }

        var isEnabled: Bool {
            !traits.contains(.notEnabled)
        }

        var description: String {
            "\"\(text)\" traits \(traits.rawValue) frame \(frame.integral)"
        }
    }

    /// UIKit's accessibility automation switch (`_AXSSetAutomationEnabled` in libAccessibility: private, test-only),
    /// turned on while a hosted view's tree is read, as `LedgerSnapshotTesting` turns it on: SwiftUI builds the
    /// tree only for an assistive technology.
    enum AccessibilityTree {
        typealias IsEnabled = @convention(c) () -> UInt8
        typealias SetEnabled = @convention(c) (UInt8) -> Void

        static func whileBuilt<Result>(_ body: () throws -> Result) rethrows -> Result {
            guard let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
                  let getter = dlsym(library, "_AXSAutomationEnabled"),
                  let setter = dlsym(library, "_AXSSetAutomationEnabled")
            else {
                Issue.record("libAccessibility's automation switch is unavailable: every tree would be empty")
                return try body()
            }
            let setEnabled = unsafeBitCast(setter, to: SetEnabled.self)
            let wasEnabled = unsafeBitCast(getter, to: IsEnabled.self)()
            setEnabled(1)
            defer { setEnabled(wasEnabled) }
            return try body()
        }

        /// Depth first, as VoiceOver walks a container.
        static func elements(in object: NSObject) -> [NSObject] {
            if object.isAccessibilityElement {
                return [object]
            }
            if let children = object.accessibilityElements as? [NSObject], !children.isEmpty {
                return children.flatMap(elements(in:))
            }
            let count = object.accessibilityElementCount()
            if count != NSNotFound, count > 0 {
                return (0 ..< count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
                    .flatMap(elements(in:))
            }
            return (object as? UIView)?.subviews.flatMap(elements(in:)) ?? []
        }
    }

    /// A window without a scene: a package test process has none to give (`LedgerSnapshotTesting` does the same).
    private protocol WindowMaking {
        func window(frame: CGRect) -> UIWindow
    }

    private struct SceneLessWindowMaker: WindowMaking {
        @available(iOS, deprecated: 26.0, message: "A package test process has no window scene")
        func window(frame: CGRect) -> UIWindow {
            UIWindow(frame: frame)
        }
    }

    /// A view in a window of a phone's size, with that phone's safe area and one appearance of the matrix.
    final class PhoneHost {
        let phone: PhoneFrame
        private let window: UIWindow
        private let controller: UIHostingController<AnyView>

        init(
            _ view: some View,
            on phone: PhoneFrame,
            _ appearance: SnapshotAppearance = SnapshotAppearance(.light, .large)
        ) {
            self.phone = phone
            let content = view
                .environment(\.dynamicTypeSize, appearance.dynamicTypeSize)
                .environment(\.colorScheme, appearance.colorScheme)
            controller = UIHostingController(rootView: AnyView(content))
            controller.overrideUserInterfaceStyle = appearance.colorScheme == .dark ? .dark : .light
            let maker: any WindowMaking = SceneLessWindowMaker()
            window = maker.window(frame: CGRect(x: 0, y: 0, width: phone.width, height: phone.height))
            window.rootViewController = controller
            window.isHidden = false
            layout()
            // A window at the top of the simulator's screen takes that device's safe area (62 pt on an iPhone 17),
            // whatever its own size: the difference to the phone it stands for is added, or taken away.
            let given = controller.view.safeAreaInsets
            controller.additionalSafeAreaInsets = UIEdgeInsets(
                top: phone.safeTop - given.top, left: -given.left,
                bottom: phone.safeBottom - given.bottom, right: -given.right
            )
            layout()
            let made = controller.view.safeAreaInsets
            if abs(made.top - phone.safeTop) > 0.5 || abs(made.bottom - phone.safeBottom) > 0.5 {
                Issue.record("\(phone) is hosted with the safe area \(made), not its own")
            }
        }

        func layout() {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
        }

        /// Takes the view off screen and lets go of it, as when the app's root stops showing it.
        func close() {
            window.isHidden = true
            window.rootViewController = nil
        }

        /// The live elements, for a test that activates them. Read inside `AccessibilityTree.whileBuilt`.
        func elements() -> [NSObject] {
            layout()
            return AccessibilityTree.elements(in: controller.view)
        }

        /// What VoiceOver gets, in its order. Read inside `AccessibilityTree.whileBuilt`.
        func spoken() -> [Spoken] {
            elements().map { element in
                Spoken(
                    label: element.accessibilityLabel ?? "",
                    value: element.accessibilityValue ?? "",
                    traits: element.accessibilityTraits,
                    frame: element.accessibilityFrame
                )
            }
        }

        /// Every scroll view under the hosted view.
        var scrollViews: [UIScrollView] {
            func find(in view: UIView) -> [UIScrollView] {
                ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap(find(in:))
            }
            return find(in: controller.view)
        }

        /// Where `view` stands in the window.
        func frame(of view: UIView) -> CGRect {
            view.convert(view.bounds, to: controller.view)
        }

        /// The window as drawn, at 2×, for a reader's eyes.
        func png() -> Data? {
            let format = UIGraphicsImageRendererFormat.preferred()
            format.scale = 2
            let bounds = controller.view.bounds
            // The layer tree, drawn here: a window of a test process is not on the render server, so
            // `drawHierarchy` has nothing to copy.
            return UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
                controller.view.layer.render(in: context.cgContext)
            }
            .pngData()
        }
    }
#endif
