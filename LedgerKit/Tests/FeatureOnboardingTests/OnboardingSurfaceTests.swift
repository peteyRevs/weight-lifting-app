import Foundation
import LedgerTestSupport
import Testing

/// F08 S2, criterion 11: `OnboardingRoot(prepareRetry:)` is the module's only public type. Read from the sources,
/// as `PreviewScan` reads previews: a second public declaration, or a re-exported import, fails here.
@Suite("FeatureOnboarding surface")
nonisolated struct OnboardingSurfaceTests {
    @Test("The module's public declarations are OnboardingRoot, its initializer and its body")
    func onlyTheRootIsPublic() throws {
        let sources = try CopyAudit.sources(ofModule: "FeatureOnboarding")
        #expect(sources.count >= 9, "the module's sources were not found: \(sources.keys.sorted())")
        let exposed = sources.sorted { $0.key < $1.key }.flatMap { _, text in
            text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("public ") || $0.hasPrefix("open ") || $0.hasPrefix("@_exported ") }
        }
        #expect(exposed == [
            "public struct OnboardingRoot: View {",
            "public init(prepareRetry: @escaping @MainActor () async -> Void = {}) {",
            "public var body: some View {"
        ])
    }
}
