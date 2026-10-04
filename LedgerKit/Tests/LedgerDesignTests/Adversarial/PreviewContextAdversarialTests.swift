#if DEBUG
    import Dependencies
    import Foundation
    import LedgerDependencies
    import LedgerDomain
    import LedgerFakes
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing

    /// F07 S3 fix round 1 verification (S3-SF1): `renderPreview` draws in swift-dependencies' preview context. A
    /// preview
    /// that reads `deviceID` and `date`, or overrides a key with a nested `withDependencies`, renders without an
    /// issue; and the context ends with the render, so the test around it is a test again.
    extension RenderingSuites {
        @Suite("Adversarial F07 S3 close-out · preview context")
        struct PreviewContextAdversarialTests {
            @Test("A preview reading deviceID and the date, with a nested override, renders with preview values")
            func preview_readsDeviceAndDate() {
                let seen = PreviewContextSeen()
                #expect(renderPreview(size: CGSize(width: 390, height: 200)) { ReadsDeviceAndDate(seen: seen) })
                #expect(seen.device == Fixtures.deviceID.rawValue.uuidString)
                #expect(seen.overridden == "00000000-0000-4000-8000-0000000000EE")
            }

            @Test("After the render, the test is in the test context again: an unconfigured key fails it")
            func contextEndsWithTheRender() {
                #expect(renderPreview(size: CGSize(width: 390, height: 100)) { Text("x") })
                withKnownIssue {
                    @Dependency(\.deviceID) var deviceID
                    _ = deviceID
                } matching: { issue in
                    issue.description.contains("@Dependency(\\.deviceID)")
                }
            }
        }
    }

    final class PreviewContextSeen {
        var device = ""
        var overridden = ""
    }

    struct ReadsDeviceAndDate: View {
        let seen: PreviewContextSeen

        var body: some View {
            @Dependency(\.deviceID) var deviceID
            @Dependency(\.date.now) var now
            seen.device = deviceID.rawValue.uuidString
            let inner = withDependencies {
                $0.deviceID = DeviceID(UUID(uuidString: "00000000-0000-4000-8000-0000000000EE") ?? UUID())
            } operation: {
                @Dependency(\.deviceID) var nested
                return nested.rawValue.uuidString
            }
            seen.overridden = inner
            return Text("\(now.timeIntervalSince1970) \(inner)")
        }
    }
#endif
