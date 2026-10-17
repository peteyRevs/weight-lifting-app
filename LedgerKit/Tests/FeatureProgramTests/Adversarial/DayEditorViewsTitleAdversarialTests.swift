#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    // F11 S10, gate G2, round 2: three claims of the review's second pass ("S10 — review, round 2": B-2, S-5,
    // S-6), each made by reading, settled here by measurement.

    extension DayEditorViewsNameAdversarialTests {
        /// The title block under `name` with no word in its tag, so that the only ink is the name's: the
        /// last row of the name's ink and the first row of the tag's pill, in pixels at 3×, and how many of
        /// the name's ink pixels stand inside the pill's own box.
        struct NameOverTag {
            var nameBottom = -1
            var pillTop = -1
            var inkInThePill = 0

            /// The room between the name's lowest ink and the pill, in points; negative when they share rows.
            var gap: CGFloat {
                CGFloat(pillTop - nameBottom - 1) / 3
            }
        }

        static func nameOverTag(_ name: String, _ setting: ViewsSetting) throws -> NameOverTag {
            let model = try DayViewsText(change: { path, text in
                ["header.name": name, "header.tag": ""][path] ?? text
            }).content(ProgramPreview.dayEditor.dayEditorModel())
            let header = DayEditorHeader(model: model) { _ in }
                .environment(\.dynamicTypeSize, setting.size)
                .environment(\.legibilityWeight, setting.isBold ? .bold : .regular)
            let drawn = try ProgramDrawing.pixels(of: header, .dark, width: setting.width, scale: 3)
            var found = NameOverTag()
            // The pill's quiet fill is darker than any letter and lighter than the ground. A letter's soft
            // edge passes through that grey for a pixel or two, and a dash's for a row or two; the pill
            // holds it for 30 pt on end in each of its rows. `streak` counts such rows on end.
            var pill = (minX: Int.max, maxX: -1, maxY: -1)
            var streak = 0
            for down in 0 ..< drawn.height {
                let row = drawn.pixels[down * drawn.width ..< (down + 1) * drawn.width]
                if row.contains(where: { $0.red > 150 }) {
                    found.nameBottom = down
                }
                var (run, start, longest) = (0, 0, 0 ..< 0)
                for (across, pixel) in row.enumerated() {
                    run = (20 ... 70).contains(Int(pixel.red)) ? run + 1 : 0
                    start = run == 1 ? across : start
                    longest = run > longest.count ? start ..< across + 1 : longest
                }
                streak = longest.count >= 90 ? streak + 1 : 0
                if streak >= 12 {
                    found.pillTop = found.pillTop < 0 ? down - 11 : found.pillTop
                    pill = (min(pill.minX, longest.lowerBound), max(pill.maxX, longest.upperBound - 1), down)
                }
            }
            guard found.pillTop >= 0, found.nameBottom >= 0 else {
                throw NotDrawn()
            }
            for down in found.pillTop ... pill.maxY {
                for across in pill.minX ... pill.maxX where drawn.pixels[down * drawn.width + across].red > 150 {
                    found.inkInThePill += 1
                }
            }
            return found
        }

        struct NotDrawn: Error {}

        /// Round 2's finding F11-S10-6 (the review's B-2), closed by ruling 21: the name kept the title's tight
        /// line and stood `xs` above the tag, so a tail on its last line reached into the tag's pill, from
        /// `.xLarge` for a wrapped seed name and from `.accessibility2` for a name of one line. Now `s` more
        /// stands under the name. Measured again at the twelve sizes on both widths, plain and bold, for
        /// two wrapped seed names, "Gyp" and a long name that ends on a tail: the least room between the
        /// name's lowest ink and the pill is 1.3 pt (the long name, Bold Text, `.accessibility5`, 375 pt) and
        /// 1.7 pt for the seed names and "Gyp" (Bold Text, `.accessibility5`); no ink in the pill anywhere.
        /// Five sizes are kept, the largest with Bold Text, and a point of room is asked for.
        @Test(
            "A name's lowest ink stands above the tag's pill, wrapped or not",
            arguments: [DynamicTypeSize.large, .xLarge, .xxxLarge, .accessibility3, .accessibility5]
        )
        func name_standsAboveTheTag(_ size: DynamicTypeSize) throws {
            var lines: [String] = []
            for name in ["Lower A — Squat focus", "Lower B — Hinge focus", "Gyp"] {
                for width in ViewsSetting.widths {
                    // Bold Text at the largest size is the tightest cell measured: 1.7 pt clear.
                    let setting = ViewsSetting(size: size, width: width, isBold: size == .accessibility5)
                    let found = try Self.nameOverTag(name, setting)
                    if found.gap < 1 || found.inkInThePill > 0 {
                        lines.append("\(Int(width)) pt, \(name): \(found.gap) pt, \(found.inkInThePill) px in the pill")
                    }
                }
            }
            #expect(lines.isEmpty, "\(lines.count) reach the pill: \(lines.joined(separator: "; "))")
        }

        /// The review's S-5, refuted: the references would draw the bar squeezed (49 pt against 61.3 at
        /// `.accessibility3`), since the screen and not the bar holds the bar at its own height. Measured:
        /// the parts the references are taken from, less their page, are 60.0, 61.3 and 70.3 pt at `.large`,
        /// `.accessibility3` and `.accessibility5`; the bar alone and the screen's bar are the same.
        @Test("In the parts the references draw, the bar is as high as on the screen", arguments: [
            DynamicTypeSize.large, .accessibility3, .accessibility5
        ])
        func parts_barIsTheScreensBar(_ size: DynamicTypeSize) throws {
            let model = try ProgramPreview.dayEditor.dayEditorModel()
            func height(_ view: some View) throws -> CGFloat {
                try CGFloat(ProgramDrawing.pixels(of: view.environment(\.dynamicTypeSize, size), .dark, scale: 3)
                    .height) / 3
            }
            let inTheParts = try height(DayEditorParts(model: model)) - height(DayEditorPage(model: model) { _ in })
            let alone = try height(DayEditorBar(model: model.header) { _ in })
            let onTheScreen = try DayEditorViewsRoomAdversarialTests.hosted(width: 402, height: 812, at: size).header
            #expect(abs(inTheParts - onTheScreen) < 1 && abs(alone - onTheScreen) < 1)
            let stops = DayEditorParts(model: model).placedStops(SnapshotAppearance(.dark, size)).prefix(3)
            let buttons = stops.prefix(2).map(\.frame)
            #expect(buttons.allSatisfy { $0.height >= 43.5 }, "\(buttons)")
            #expect(buttons.allSatisfy { $0.maxY <= (stops.last?.frame.minY ?? 0) }, "a button over the heading")
        }

        /// The review's S-6, refuted as it reads, with a remainder: with the draft emptied the text under the field has
        /// no line, so at large sizes
        /// the field, with its placeholder and caret, would be higher than the 44 pt the name field keeps,
        /// hang over the tag and the summary, and the page would jump at the first letter typed.
        @Test(
            "With an empty draft the field stays inside the name's target, which is as high as one letter's",
            arguments: [
                DynamicTypeSize.large, .accessibility3, .accessibility5
            ]
        )
        func emptyDraft_keepsALine(_ size: DynamicTypeSize) throws {
            let (empty, letter) = try (Shown("", at: size), Shown("A", at: size))
            defer {
                empty.close()
                letter.close()
            }
            try empty.focus(true)
            let field = empty.field.convert(empty.field.bounds, to: empty.hosted.host.view)
            let (target, lettered) = try (empty.target(), letter.target())
            // Measured: the field is 2.0 and 2.7 pt higher than its target at the two accessibility sizes,
            // inside the `xs` that parts it from the tag, and the target 2.3 and 2.7 pt higher than under one
            // letter. Nothing is covered; the rows under the name move by that much at the first letter.
            let hang = field.maxY - target.maxY
            #expect(hang < LedgerSpacing.xs, "the field hangs \(hang) pt under its target and reaches the tag")
            let jump = abs(target.height - lettered.height)
            #expect(jump < LedgerSpacing.xs, "empty \(target.height) pt, one letter \(lettered.height)")
        }
    }
#endif
