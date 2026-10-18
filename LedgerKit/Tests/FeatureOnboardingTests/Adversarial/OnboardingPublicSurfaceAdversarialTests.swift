import FeatureOnboarding
import LedgerTestSupport
import SwiftUI
import Testing

/// F08 S2 adversarial round 1, criterion 11, from outside the module: this file imports `FeatureOnboarding` as
/// the app does, without `@testable`, so it compiles only against the public surface.
@Suite("Adversarial F08 S2 · the public surface, as the app sees it")
struct OnboardingPublicSurfaceAdversarialTests {
    static func isAView(_: some View) -> Bool {
        true
    }

    @Test("OnboardingRoot is a view made from a retry step, or from nothing")
    func root_isMadeFromARetryStep() {
        let roots = withTestDependencies {
            $0.inMemoryStores()
        } operation: {
            (OnboardingRoot(), OnboardingRoot(prepareRetry: {}), OnboardingRoot { await Task.yield() })
        }
        #expect(Self.isAView(roots.0))
        #expect(Self.isAView(roots.1))
        #expect(Self.isAView(roots.2))
    }
}
