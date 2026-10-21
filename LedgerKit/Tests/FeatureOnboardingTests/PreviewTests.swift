#if DEBUG
    @testable import FeatureOnboarding
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// Every `#Preview` in FeatureOnboarding is a case of `OnboardingPreview`, and every case renders (the
    /// convention F07's criterion 8 set for each module with previews).
    @Suite("Previews (FeatureOnboarding)", .serialized, .tags(.feature))
    struct PreviewTests {
        @Test("Every #Preview in FeatureOnboarding is an OnboardingPreview case, by name, and every case has one")
        func registry_listsEveryPreview() throws {
            let names = try PreviewScan.previews(inModule: "FeatureOnboarding")
            #expect(!names.contains(nil), "a #Preview without a name cannot be listed")
            #expect(names.count == Set(names).count, "a name appears twice: \(names)")
            #expect(Set(names.compactMap(\.self)) == Set(OnboardingPreview.allCases.map(\.rawValue)))
        }

        @Test("Every preview renders", arguments: OnboardingPreview.allCases)
        func preview_renders(_ preview: OnboardingPreview) {
            #expect(renderPreview(size: CGSize(width: SnapshotConfig.phoneWidth, height: 874)) { preview.content })
        }
    }
#endif
