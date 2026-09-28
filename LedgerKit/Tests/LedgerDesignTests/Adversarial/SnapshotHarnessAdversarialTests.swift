import CoreGraphics
import Foundation
import LedgerDesign
import LedgerSnapshotTesting
import SnapshotTesting
import SwiftUI
import Testing

/// The pixel pipeline every F06 snapshot relies on: `RenderedImage` must be deterministic, and the
/// `.png` comparator (the only one on watchOS) must fail loudly, readably and at the right threshold.
@Suite("Snapshot harness (adversarial)", .tags(.design, .snapshot))
struct SnapshotHarnessAdversarialTests {
    static func diff(_ reference: CGImage, _ actual: CGImage) -> (String, [DiffAttachment])? {
        Snapshotting<CGImage, Data>.png.diffing.diffV2(Bitmap.png(reference), Bitmap.png(actual))
    }

    /// `width`×1 opaque grey strip with the first `changed` pixels turned red.
    static func strip(width: Int, changed: Int) -> CGImage? {
        Bitmap.make(width: width, height: 1) { column, _ in column < changed ? 0xFF00_00FF : 0x8080_80FF }
    }

    static var specimen: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("UP NEXT").ledgerFont(.eyebrow).foregroundStyle(LedgerColor.accent)
            Text("Upper A — Push focus").ledgerFont(.heading).foregroundStyle(LedgerColor.ink)
            Text("185 × 5").ledgerFont(.numeralL).foregroundStyle(LedgerColor.inkSecondary)
            Rectangle().fill(LedgerColor.hairline).frame(height: LedgerHairline.width)
        }
        .padding(12)
        .background(LedgerColor.ground)
    }

    @Test("Rendering the same view five times yields identical pixels (determinism).")
    func render_sameViewRepeatedly_isPixelIdentical() throws {
        let first = try #require(RenderedImage.render(Self.specimen, width: 240).flatMap(PixelBuffer.init))
        for attempt in 1 ... 4 {
            let again = RenderedImage.render(Self.specimen, width: 240).flatMap(PixelBuffer.init)
            #expect(again == first, "render \(attempt + 1) differs from the first")
        }
    }

    @Test("The PNG round trip is lossless: a rendered image compares equal to its own reference.")
    func pngDiffing_identicalImages_pass() throws {
        let image = try #require(RenderedImage.render(Self.specimen, width: 240))
        #expect(Self.diff(image, image) == nil)
    }

    @Test("One changed digit fails the comparison with a message that says how much differs.")
    func pngDiffing_oneDigitChanged_failsReadably() throws {
        let reference = try #require(RenderedImage.render(Text("185 × 5").ledgerFont(.numeralL).padding(4)))
        let actual = try #require(RenderedImage.render(Text("185 × 6").ledgerFont(.numeralL).padding(4)))
        let failure = try #require(Self.diff(reference, actual), "a changed digit passed the comparator")
        #expect(failure.0.contains("pixels differ"), "message: \(failure.0)")
        #expect(failure.0.contains("0.995"), "message should state the required precision: \(failure.0)")
    }

    @Test("A failure attaches a difference image, not just the two inputs (testing-strategy §2.5).")
    func pngDiffing_failure_attachesDifferenceImage() throws {
        let reference = try #require(Self.strip(width: 100, changed: 0))
        let actual = try #require(Self.strip(width: 100, changed: 50))
        let failure = try #require(Self.diff(reference, actual))
        let names = failure.1.compactMap { attachment -> String? in
            if case let .data(_, name) = attachment {
                return name
            }
            return nil
        }
        #expect(names.contains("actual.png") && names.contains("reference.png"), "attachments: \(names)")
        #expect(names.contains { !["actual.png", "reference.png"].contains($0) }, "no difference image in \(names)")
    }

    @Test("A size change fails and names both sizes.")
    func pngDiffing_sizeChange_namesBothSizes() throws {
        let reference = try #require(Self.strip(width: 100, changed: 0))
        let actual = try #require(Self.strip(width: 101, changed: 0))
        let message = try #require(Self.diff(reference, actual)).0
        #expect(message.contains("101×1") && message.contains("100×1"), "message: \(message)")
    }

    @Test("Exactly 99.5 % matching pixels passes: precision 0.995 is inclusive.")
    func pngDiffing_exactlyAtPrecision_passes() throws {
        let reference = try #require(Self.strip(width: 1000, changed: 0))
        let actual = try #require(Self.strip(width: 1000, changed: 5))
        #expect(Self.diff(reference, actual) == nil, "5 of 1000 pixels differ = 99.5 % match")
    }

    @Test("99.4 % matching pixels fails.")
    func pngDiffing_belowPrecision_fails() throws {
        let reference = try #require(Self.strip(width: 1000, changed: 0))
        let actual = try #require(Self.strip(width: 1000, changed: 6))
        #expect(Self.diff(reference, actual) != nil)
    }

    @Test("A shift below ΔE 2 (0x80 → 0x81 grey) passes: perceptual precision 0.98.")
    func pngDiffing_imperceptibleShift_passes() throws {
        let reference = try #require(Bitmap.make(width: 50, height: 50) { _, _ in 0x8080_80FF })
        let actual = try #require(Bitmap.make(width: 50, height: 50) { _, _ in 0x8181_81FF })
        #expect(Self.diff(reference, actual) == nil)
    }

    @Test("Opaque versus transparent is a full-scale difference.")
    func pngDiffing_alphaOnlyChange_fails() throws {
        let reference = try #require(Bitmap.make(width: 20, height: 20) { _, _ in 0x0000_00FF })
        let actual = try #require(Bitmap.make(width: 20, height: 20) { _, _ in 0x0000_0000 })
        #expect(Self.diff(reference, actual) != nil)
    }

    @Test("Undecodable reference data fails with a message instead of crashing or passing.")
    func pngDiffing_corruptReference_fails() throws {
        let actual = try #require(Self.strip(width: 10, changed: 0))
        let failure = Snapshotting<CGImage, Data>.png.diffing.diffV2(Data("not a png".utf8), Bitmap.png(actual))
        #expect(failure != nil)
    }

    @Test("The phone matrix is exactly {light, dark} × {large, xLarge, AX3} (criterion 3).")
    func phoneMatrix_coversCriterionThree() {
        let cells = SnapshotAppearance.phoneMatrix.map(\.description)
        #expect(Set(cells) == [
            "light-large", "light-xLarge", "light-accessibility3",
            "dark-large", "dark-xLarge", "dark-accessibility3"
        ])
        #expect(cells.count == 6)
        #expect(SnapshotConfig.precision == 0.995 && SnapshotConfig.perceptualPrecision == 0.98)
    }
}
