#if os(iOS)
    @testable import LedgerSnapshotTesting
    import Observation
    import SwiftUI
    import UIKit

    /// A view in a window that stays up across a test's suspensions, so that a root's `.task`s start and keep
    /// running, and a scroll view can be reached and moved. (`withLiveAccessibilityElements` takes a synchronous
    /// body and takes its window down on return.) The window is `LedgerSnapshotTesting`'s internal
    /// `SceneLessWindow`, which is why this one file imports that module `@testable` (review S2-N7: a public
    /// helper there is the chore's).
    enum Hosted {
        /// An iPhone 17's screen, the phone the references are drawn for.
        nonisolated static let phone = CGSize(width: SnapshotConfig.phoneWidth, height: 874)

        /// Hosts `view` in a window of `size` for as long as `body` runs, and hands `body` the hosting view.
        static func view(
            _ view: some View,
            size: CGSize = phone,
            _ body: (UIView) async throws -> Void
        ) async rethrows {
            let host = UIHostingController(rootView: view)
            let window = SceneLessWindow.make(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            try await body(host.view)
        }

        /// Suspends until `condition` holds of what an observable store shows. No polling: `Observations` wakes
        /// on each change of what `condition` read.
        static func until(_ condition: @escaping @MainActor @Sendable () -> Bool) async {
            for await holds in Observations(condition) where holds {
                return
            }
        }

        /// Lays `view` out until SwiftUI has nothing left to apply from a state change: the change itself, what
        /// an `onChange` answered it with, and what that moved.
        static func settle(_ view: UIView) {
            for _ in 0 ..< 3 {
                view.setNeedsLayout()
                view.layoutIfNeeded()
            }
        }

        /// The scroll view under `view`: a screen that scrolls has exactly one.
        static func scrollViews(in view: UIView) -> [UIScrollView] {
            ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews(in:))
        }
    }
#endif
