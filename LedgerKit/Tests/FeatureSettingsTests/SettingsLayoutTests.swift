#if os(iOS) && DEBUG
    @testable import FeatureSettings
    import LedgerDesign
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F14 S1, N10, by measurement: at every text size, with Bold Text and laid out right to left, every stop of
    /// every state has a size, stands inside the page, is over no other stop and, when it can be tapped, is a 44 pt
    /// target; and at accessibility sizes each row's control stands under its label, the units' options on one row.
    /// What a frame cannot show (a word cut short inside its frame) is in the references, which were looked at.
    @Suite("Settings layout", .serialized, .tags(.feature))
    struct SettingsLayoutTests {
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
                if [.button, .toggle].contains(item.stop.kind), frame.height < 43.5 || frame.width < 43.5 {
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
            arguments: SettingsPreview.allCases, Setting.all
        )
        func parts_layOutSanely(_ preview: SettingsPreview, _ setting: Setting) {
            let stops = Self.placed(SettingsParts(preview: preview), setting)
            #expect(stops.count >= 12, "the parts were not read")
            let faults = Self.faults(in: stops)
            #expect(faults.isEmpty, "\(faults.prefix(4).joined(separator: "\n"))")
        }

        @Test(
            "N10. The units' options keep one row; at accessibility sizes they and the menu stand under their labels",
            arguments: Setting.all
        )
        func controls_moveUnderTheirLabels(_ setting: Setting) throws {
            let stops = Self.placed(SettingsParts(preview: .pounds), setting)
            let pounds = try #require(stops.first { $0.stop.label == "pounds" }).frame
            let kilograms = try #require(stops.first { $0.stop.label == "kilograms" }).frame
            #expect(abs(pounds.minY - kilograms.minY) < 0.5, "the options stand on one row")
            let training = try #require(stops.first { $0.stop == .heading("TRAINING") }).frame
            let week = try #require(stops.first { $0.stop.label == "Week starts on" }).frame
            let rest = try #require(stops.first { $0.stop.label == "Default rest" }).frame
            // The label is hidden from VoiceOver; the row's top is the stop before it, and its control's place
            // against the page's leading edge tells the two layouts apart.
            let leading = setting.isRightToLeft ? SnapshotConfig.phoneWidth - pounds.maxX : pounds.minX
            if setting.size.isAccessibilitySize {
                #expect(leading < LedgerSpacing.screen + 4, "the units stand under their label, at the leading edge")
            } else {
                #expect(leading > SnapshotConfig.phoneWidth / 2, "the units stand beside their label")
            }
            #expect(pounds.minY > training.maxY && rest.minY > pounds.maxY && week.minY > rest.maxY)
        }
    }
#endif
