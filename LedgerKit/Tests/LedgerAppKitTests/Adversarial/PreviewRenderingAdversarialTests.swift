import Dependencies
@testable import LedgerAppKit
import LedgerDesign
import LedgerSnapshotTesting
import SwiftUI
import Synchronization
import Testing

/// F09 S1 adversarial round 1: `renderPreview`, whose Mac-host half this slice changed (a hosting window in place of
/// `ImageRenderer`, which traps on a `NavigationStack` with a path inside a `Tab`). It must still build and draw the
/// view in the preview context, and draw the shell in the states the registry's previews do not show: every tab
/// selected, with and without a pushed screen, light and dark, at the default and the largest text size.
@Suite("Adversarial F09 S1 · preview rendering")
struct PreviewRenderingAdversarialTests {
    static let size = CGSize(width: SnapshotConfig.phoneWidth, height: 874)

    /// Tells the test the dependency context its body was built in.
    struct Probe: View {
        @Dependency(\.context) private var context
        let seen: (DependencyContext) -> Void

        var body: some View {
            LedgerColor.accent.onAppear { seen(context) }
        }
    }

    @Test("A preview is built in the preview context, laid out and shown: its body's appearance action runs")
    func renderPreview_showsTheViewInThePreviewContext() {
        let contexts = Mutex<[DependencyContext]>([])
        let drew = renderPreview(size: Self.size) {
            Probe { context in contexts.withLock { $0.append(context) } }
        }
        #expect(drew)
        #expect(contexts.withLock { $0 } == [.preview])
    }

    @Test("The shell draws with any tab selected, at its root or under a pushed screen", arguments: AppTab.allCases)
    func renderPreview_drawsTheShellInEveryState(_ tab: AppTab) {
        for depth in [0, 1, 3] {
            for scheme in [ColorScheme.light, .dark] {
                for textSize in [DynamicTypeSize.large, .accessibility5] {
                    let router = AppRouter()
                    router.selectedTab = tab
                    for _ in 0 ..< depth {
                        router.open(.settings, in: tab)
                    }
                    let drew = renderPreview(size: Self.size) {
                        AppTabs(router: router)
                            .environment(\.colorScheme, scheme)
                            .environment(\.dynamicTypeSize, textSize)
                    }
                    #expect(drew, "\(tab) depth \(depth) \(scheme) \(textSize)")
                }
            }
        }
    }
}
