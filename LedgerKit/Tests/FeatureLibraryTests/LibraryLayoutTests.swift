#if os(iOS) && DEBUG
    @testable import FeatureLibrary
    import LedgerDesign
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F12 S1, by measurement: at every text size, with Bold Text and laid out right to left, every stop of every
    /// state has a size, stands inside the page, is over no other stop and, when it can be tapped, is a 44 pt
    /// target; the title keeps its one line, with "New exercise" beside it and, at accessibility sizes, under
    /// it. What a frame cannot show (a word cut short inside its frame) is in the references, which were looked
    /// at. The sizes and settings go through `TestSweep` (ruling R6).
    @Suite("Library layout", .serialized, .tags(.feature))
    struct LibraryLayoutTests {
        /// One way the system can be set.
        nonisolated struct Setting: Sendable, CustomTestStringConvertible {
            let size: DynamicTypeSize
            var isBold = false
            var isRightToLeft = false

            var testDescription: String {
                "\(size)" + (isBold ? ", Bold Text" : "") + (isRightToLeft ? ", right to left" : "")
            }

            /// On the hosted PR runner the representative sizes, each plain and bold right to left.
            static let all: [Setting] = TestSweep.sizes([.xSmall, .large, .xxxLarge, .accessibility3, .accessibility5])
                .flatMap { size in
                    TestSweep.subset([
                        Setting(size: size), Setting(size: size, isBold: true),
                        Setting(size: size, isRightToLeft: true),
                        Setting(size: size, isBold: true, isRightToLeft: true)
                    ]) { $0.isBold == $0.isRightToLeft }
                }
        }

        static func placed(_ view: some View, _ setting: Setting) -> [PlacedStop] {
            view
                .environment(\.legibilityWeight, setting.isBold ? .bold : .regular)
                .environment(\.layoutDirection, setting.isRightToLeft ? .rightToLeft : .leftToRight)
                .placedStops(SnapshotAppearance(.dark, setting.size))
        }

        /// What is wrong with the frames of `stops` on a page 402 points wide, a line each.
        nonisolated static func faults(in stops: [PlacedStop]) -> [String] {
            let width = SnapshotConfig.phoneWidth
            var lines: [String] = []
            for item in stops {
                let frame = item.frame
                if frame.width < 1 || frame.height < 1 {
                    lines.append("no size: \(item.stop) \(frame.size)")
                }
                if frame.minX < -0.5 || frame.maxX > width + 0.5 {
                    lines.append("outside the page: \(item.stop) x \(frame.minX)...\(frame.maxX)")
                }
                if item.stop.kind == .button, frame.height < 43.5 || frame.width < 43.5 {
                    lines.append("target under 44 pt: \(item.stop) \(frame.size)")
                }
            }
            for (index, first) in stops.enumerated() {
                for second in stops[(index + 1)...] {
                    let shared = first.frame.intersection(second.frame)
                    if !shared.isNull, shared.width > 2, shared.height > 2 {
                        lines.append("overlap \(shared.size): \(first.stop) and \(second.stop)")
                    }
                }
            }
            return lines
        }

        @Test(
            "In every state and setting no stop is empty, outside the page, under 44 points or over another",
            arguments: LibraryPreview.allCases, Setting.all
        )
        func parts_layOutSanely(_ preview: LibraryPreview, _ setting: Setting) {
            let stops = Self.placed(LibraryParts(preview: preview), setting)
            #expect(stops.count >= 15, "the parts were not read")
            let faults = Self.faults(in: stops)
            #expect(faults.isEmpty, "\(faults.prefix(4).joined(separator: "\n"))")
        }

        @Test(
            "The title keeps one line at every size; New exercise stands beside it, and under it at the largest",
            arguments: Setting.all
        )
        func header_titleKeepsOneLine(_ setting: Setting) throws {
            let stops = Self.placed(LibraryParts(preview: .noExercises), setting)
            let title = try #require(stops.first { $0.stop == .heading("Library") }).frame
            let button = try #require(stops.first { $0.stop == .button("New exercise") }).frame
            let line = try #require(Self.placed(Text("Library").ledgerFont(.title), setting).first).frame
            #expect(
                abs(title.height - line.height) < 1,
                "the title wrapped: \(title.height) for one line of \(line.height)"
            )
            if setting.size.isAccessibilitySize {
                #expect(button.minY >= title.maxY - 0.5, "the button stands under the title")
            } else {
                #expect(button.midY > title.minY && button.midY < title.maxY, "the button stands beside the title")
            }
        }
    }
#endif
