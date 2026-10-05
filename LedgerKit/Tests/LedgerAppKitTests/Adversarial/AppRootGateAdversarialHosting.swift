#if os(iOS)
    import Darwin
    @testable import LedgerAppKit
    @testable import LedgerSnapshotTesting
    import Observation
    import SwiftUI
    import Testing
    import UIKit

    // F08 S3 adversarial round 1 (G2): the app's real root in a window that stays up across a test's
    // suspensions, so its tasks run, with the scene's phase in the test's hands. The window is
    // `LedgerSnapshotTesting`'s internal `SceneLessWindow`, which is why this file imports that module
    // `@testable`, as `FeatureOnboardingTests`' `Hosted` does.

    /// The scene's phase as the hosted root sees it: the test changes it as the system would.
    @Observable
    final class GateScene {
        var phase: ScenePhase

        init(_ phase: ScenePhase) {
            self.phase = phase
        }
    }

    /// What a hosted root shows, read two ways: the UIKit views under it (a tab bar, a scroll view) and what
    /// VoiceOver gets outside any scroll view (onboarding's pinned buttons, a tab's title, the unavailable
    /// screen's two texts). The page inside onboarding's scroll view is not read here: the hosted reader cannot
    /// see it (testing-strategy §2.6), and the UI test `OnboardingAdversarial` reads it in the real app.
    nonisolated struct GateShown: Equatable, Sendable, CustomStringConvertible {
        var labels: [String]
        var tabBars: Int
        var scrollViews: Int

        /// The ground colour alone: no tab bar, no scroll view, nothing for VoiceOver.
        var isGround: Bool {
            labels.isEmpty && tabBars == 0 && scrollViews == 0
        }

        /// Onboarding, full screen: its one scroll view over its pinned buttons, and no tab bar.
        var isOnboarding: Bool {
            tabBars == 0 && scrollViews == 1 && labels.last == "Skip setup"
        }

        /// The tabs, on Today.
        var isTabs: Bool {
            tabBars == 1 && labels == ["Today"]
        }

        /// Product decision #29's screen and nothing else.
        var isUnavailable: Bool {
            tabBars == 0 && scrollViews == 0 && labels.first == "Can't open your data right now" && labels.count == 2
        }

        var description: String {
            "\(labels) tab bars \(tabBars) scroll views \(scrollViews)"
        }
    }

    /// A view hosted as the app's window hosts its root, at an iPhone 17's size.
    final class GateHost {
        nonisolated static let phone = CGSize(width: SnapshotConfig.phoneWidth, height: 874)

        let scene: GateScene
        private let window: UIWindow
        private let controller: UIHostingController<AnyView>

        init(_ root: some View, phase: ScenePhase = .active) {
            let phased = GateScene(phase)
            scene = phased
            controller = UIHostingController(rootView: AnyView(GateSceneView(scene: phased, content: root)))
            window = SceneLessWindow.make(frame: CGRect(origin: .zero, size: Self.phone))
            window.rootViewController = controller
            window.isHidden = false
            settle()
        }

        /// Lays the view out until SwiftUI has nothing left to apply from a change of state.
        func settle() {
            for _ in 0 ..< 3 {
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
            }
        }

        /// Takes the root off screen and lets go of it, as when the app ends.
        func close() {
            window.isHidden = true
            window.rootViewController = nil
        }

        /// What the root shows now.
        var shown: GateShown {
            settle()
            let labels = GateAccessibility.whileBuilt { pinned().map { $0.accessibilityLabel ?? "" } }
            return GateShown(
                labels: labels,
                tabBars: views(UITabBar.self).count,
                scrollViews: views(UIScrollView.self).count { !($0 is UITextView) }
            )
        }

        /// Activates the element VoiceOver reads as `label`, outside any scroll view, as a double tap does.
        /// False when there is none, or it is not enabled.
        @discardableResult
        func activate(_ label: String) -> Bool {
            settle()
            let isActivated = GateAccessibility.whileBuilt { () -> Bool in
                guard let element = pinned().first(where: { $0.accessibilityLabel == label }),
                      !element.accessibilityTraits.contains(.notEnabled)
                else {
                    return false
                }
                return element.accessibilityActivate()
            }
            settle()
            return isActivated
        }

        /// Taps the tab bar's button at `index` (0 is Today), as a lifter does. False when there is none.
        @discardableResult
        func tapTab(at index: Int) -> Bool {
            settle()
            guard let bar = views(UITabBar.self).first else {
                return false
            }
            let buttons = views(UIControl.self).filter { $0.isDescendant(of: bar) }
            guard buttons.indices.contains(index) else {
                return false
            }
            buttons[index].sendActions(for: .touchUpInside)
            settle()
            return true
        }

        private func pinned() -> [NSObject] {
            GateAccessibility.elements(in: controller.view)
        }

        private func views<Kind: UIView>(_: Kind.Type) -> [Kind] {
            func find(in view: UIView) -> [Kind] {
                ((view as? Kind).map { [$0] } ?? []) + view.subviews.flatMap(find(in:))
            }
            return find(in: controller.view)
        }
    }

    private struct GateSceneView<Content: View>: View {
        let scene: GateScene
        let content: Content

        var body: some View {
            content.environment(\.scenePhase, scene.phase)
        }
    }

    /// UIKit's accessibility automation switch (`_AXSSetAutomationEnabled` in libAccessibility: private,
    /// test-only), turned on while a hosted view's tree is read, as `LedgerSnapshotTesting` turns it on. Each
    /// read is synchronous, so the switch is never left on across a suspension.
    enum GateAccessibility {
        typealias IsEnabled = @convention(c) () -> UInt8
        typealias SetEnabled = @convention(c) (UInt8) -> Void

        static func whileBuilt<Result>(_ body: () -> Result) -> Result {
            guard let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
                  let getter = dlsym(library, "_AXSAutomationEnabled"),
                  let setter = dlsym(library, "_AXSSetAutomationEnabled")
            else {
                Issue.record("libAccessibility's automation switch is unavailable: every tree would be empty")
                return body()
            }
            let setEnabled = unsafeBitCast(setter, to: SetEnabled.self)
            let wasEnabled = unsafeBitCast(getter, to: IsEnabled.self)()
            setEnabled(1)
            defer { setEnabled(wasEnabled) }
            return body()
        }

        /// Depth first, as VoiceOver walks a container, leaving every scroll view out whole.
        static func elements(in object: NSObject) -> [NSObject] {
            if object.isAccessibilityElement {
                return [object]
            }
            if object is UIScrollView {
                return []
            }
            if let listed = object.accessibilityElements as? [NSObject], !listed.isEmpty {
                return listed.flatMap(elements(in:))
            }
            let count = object.accessibilityElementCount()
            if count != NSNotFound, count > 0 {
                return (0 ..< count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
                    .flatMap(elements(in:))
            }
            return (object as? UIView)?.subviews.flatMap(elements(in:)) ?? []
        }
    }
#endif
