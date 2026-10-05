import Foundation
import LedgerTestSupport
import Testing

/// F08 S2, criterion 11: `OnboardingRoot(prepareRetry:)` is the module's only public type. A tripwire, not a
/// proof: it reads the sources line by line, as `PreviewScan` reads previews, for the word `public` (or `open`,
/// `package`, a re-exported import) in a line of code. A second public declaration fails here however it is
/// attributed; so does wrapping the initializer over two lines, with nothing wrong.
@Suite("FeatureOnboarding surface", .tags(.feature))
nonisolated struct OnboardingSurfaceTests {
    @Test("The module's public declarations are OnboardingRoot, its initializer and its body")
    func onlyTheRootIsPublic() throws {
        let sources = try CopyAudit.sources(ofModule: "FeatureOnboarding")
        #expect(sources.count >= 9, "the module's sources were not found: \(sources.keys.sorted())")
        // The access word anywhere in a line of code (`@MainActor public struct`, `nonisolated public enum`):
        // comments are left out, and so is a log line's `privacy: .public`.
        let access = /\b(?:public|open|package)\s|@_exported\b/
        let exposed = sources.sorted { $0.key < $1.key }.flatMap { _, text in
            text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.hasPrefix("//") && $0.contains(access) }
        }
        #expect(exposed == [
            "public struct OnboardingRoot: View {",
            "public init(prepareRetry: @escaping @MainActor () async -> Void = {}) {",
            "public var body: some View {"
        ])
    }
}
