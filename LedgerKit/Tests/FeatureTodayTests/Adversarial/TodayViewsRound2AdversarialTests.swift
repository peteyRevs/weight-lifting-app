#if os(iOS)
    @testable import FeatureToday
    import Foundation
    @testable import LedgerDesign
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F09 S4, gate G2, round 2: what the rulings after round 1 changed. Criterion 10: the resume button speaks
    /// "Resume workout" with no time, and `PrimaryButton`'s spoken label is optional. Criterion 11: at the
    /// accessibility sizes no recent row ends in a line that holds only the chevron, and "RECENT" clears its
    /// rule.
    @Suite("Adversarial F09 S4 · round 2: the spoken resume line and the recent list", .tags(.feature))
    struct TodayViewsRound2AdversarialTests {
        typealias Layout = TodayViewsLayoutAdversarialTests

        /// The five accessibility sizes.
        nonisolated static let largeSizes: [DynamicTypeSize] = [
            .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5
        ]

        /// Every state of the fixtures whose card resumes: two real ones and the contradictory model.
        nonisolated static let resuming: [ViewsCase] = (ViewsCases.all + ViewsCases.odd).filter { item in
            if case .resume? = item.model?.card.upNext?.action {
                return true
            }
            return false
        }

        @Test("Three fixtures resume a workout")
        func fixtures_resume() {
            #expect(Self.resuming.count == 3, "\(Self.resuming.map(\.name))")
        }

        @Test(
            "In every state that resumes, at every text size, one button reads Resume workout and sends the route",
            arguments: resuming
        )
        func resumeButton_everyState_readsResumeWorkout(_ item: ViewsCase) throws {
            let route = try #require(item.model?.card.upNext?.action.action.route)
            for size in Layout.sizes {
                let sent = TodayViews.Sent()
                let found = TodayViews.page(item, sent: sent)
                    .withAccessibilityElements(SnapshotAppearance(.light, size)) { elements in
                        elements.filter { $0.accessibilityLabel == "Resume workout" }.map { element in
                            _ = element.accessibilityActivate()
                            return ViewStop(reading: element).role
                        }
                    }
                #expect(found == [.button], "\(item.name) at \(size): \(found.count) such stops")
                #expect(sent.actions == [.route(route)], "\(item.name) at \(size): \(sent.actions.count) actions")
            }
        }

        @Test("Nothing a resuming page speaks carries a clock time, or the model's own title", arguments: resuming)
        func resumingPage_speaksNoTime(_ item: ViewsCase) throws {
            let title = try #require(item.model?.card.upNext?.action.action.title)
            for seconds in [0.0, 1200] {
                let page = TodayPage(state: item.state) { _ in }
                    .environment(\.todayTimerPause, item.now.addingTimeInterval(seconds))
                let buttons = TodayViews.stops(of: page).filter { $0.role == .button }
                let timed = buttons.filter { stop in
                    (stop.label + " " + stop.value).contains(/\d:\d\d/)
                }
                // A recent row of today's workout reads its length ("Today · 24:22 · …"): that is the row's own.
                let wrong = timed.filter { !$0.label.contains(" · ") || $0.label.hasPrefix("Resume") }
                #expect(wrong.isEmpty, "\(item.name) after \(Int(seconds)) s: \(wrong.map(\.description))")
                #expect(!buttons.contains { $0.label == title }, "\(item.name): the model's title is spoken")
            }
        }

        @Test("No stop of a resuming page is marked as updating by itself", arguments: resuming)
        func resumingPage_noStopUpdatesFrequently(_ item: ViewsCase) {
            let live = TodayPage(state: item.state) { _ in }.withAccessibilityElements { elements in
                elements.count { $0.accessibilityTraits.contains(.updatesFrequently) }
            }
            #expect(live == 0, "\(item.name): \(live) stops, with the time counting (no pause)")
        }
    }

    // MARK: - PrimaryButton, with and without a spoken line

    extension TodayViewsRound2AdversarialTests {
        typealias Components = TodayViewsComponentsAdversarialTests

        @Test("Without a spoken line, a Text button reads its label as drawn, as the String button does")
        func textButton_noSpokenLine_readsItsLabel() {
            var taps = 0
            let plain = Components.activated(PrimaryButton(label: Text(verbatim: "Start workout")) { taps += 1 })
            #expect(plain.map(\.stop.description) == ["button \"Start workout\""], "\(plain.map(\.stop))")
            #expect(plain.allSatisfy { !$0.traits.contains(.updatesFrequently) })
            #expect(taps == 1)
            let disabled = Components.activated(PrimaryButton(label: Text(verbatim: "Start workout")) { taps += 1 }
                .disabled(true))
            #expect(
                disabled.map(\.stop.description) == ["button \"Start workout\" (dimmed)"],
                "\(disabled.map(\.stop))"
            )
            #expect(taps == 1)
        }

        @Test("Without a spoken line, a timer button is one button that reads the time as it stands, 12:48")
        func timerButton_noSpokenLine_readsTheTime() {
            let found = Components.activated(PrimaryButton(label: Components.timerLabel(), icon: .arrow) {})
            #expect(found.map(\.stop.role) == [.button], "\(found.map(\.stop))")
            #expect(found.map(\.stop.label) == ["12:48"], "\(found.map(\.stop.label))")
            #expect(found.allSatisfy { $0.frame.height >= 43.5 })
        }

        @Test("With and without a spoken line the button draws alike: the line changes what is read, not what is seen")
        func textButton_spokenLine_changesNoPixel() throws {
            let width = SnapshotConfig.phoneWidth
            let spoken = RenderedImage.render(
                PrimaryButton(label: Components.timerLabel(), accessibilityLabel: "Resume workout", icon: .arrow) {},
                width: width
            )
            let silent = RenderedImage.render(
                PrimaryButton(label: Components.timerLabel(), icon: .arrow) {},
                width: width
            )
            let first = try #require(spoken.flatMap(PixelBuffer.init))
            let second = try #require(silent.flatMap(PixelBuffer.init))
            #expect(first == second, "the two draw differently")
        }

        @Test("An empty spoken line does not leave a button with nothing to read")
        func textButton_emptySpokenLine_isStillNamed() {
            let found = TodayViews.stops(of: PrimaryButton(
                label: Text(verbatim: "Start workout"),
                accessibilityLabel: ""
            ) {})
            #expect(found.count == 1 && found.allSatisfy { $0.role == .button && !$0.label.isEmpty }, "\(found)")
        }
    }

    // MARK: - The recent list at every text size (criterion 11)

    extension TodayViewsRound2AdversarialTests {
        static func recent() throws -> TodayModel.Recent {
            try #require(ViewsCases.all.first { $0.name == "logged" }?.model?.recent)
        }

        @Test(
            "At every text size the recent list reads its heading and one button per row, which sends its route",
            arguments: Layout.sizes
        )
        func recentList_everySize_isTheSameTree(_ size: DynamicTypeSize) throws {
            let model = try Self.recent()
            let sent = TodayViews.Sent()
            let found = RecentList(model: model) { sent.actions.append($0) }
                .withAccessibilityElements(SnapshotAppearance(.dark, size)) { elements in
                    elements.map { element in
                        _ = element.accessibilityActivate()
                        return ViewStop(reading: element)
                    }
                }
            let expected = [ViewStop.heading(model.eyebrow)] + model.rows.map { .button("\($0.name), \($0.meta)") }
            let difference = TodayViews.difference(found: found, expected: expected)
            #expect(difference.isEmpty, "\(size): \(difference.joined(separator: "\n"))")
            #expect(model.rows.count == 2 && sent.actions.count == 2, "\(sent.actions.count) actions")
            for (index, row) in model.rows.enumerated() where index < sent.actions.count {
                #expect(sent.actions[index] == .route(row.route), "\(size): row \(index + 1)")
            }
        }

        /// The heights of the list's rows at `size`, and of the same rows drawn with no accessory at all.
        static func rowHeights(at size: DynamicTypeSize) throws -> (list: [CGFloat], bare: [CGFloat]) {
            let model = try recent()
            let list = Layout.placed(RecentList(model: model) { _ in }, at: size)
                .filter { $0.stop.role == .button }.map(\.frame.height)
            let bare = Layout.placed(
                HairlineList {
                    ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                        HairlineRow(row.name, detail: row.meta, action: {})
                    }
                },
                at: size
            ).map(\.frame.height)
            return (list, bare)
        }

        @Test(
            "At the accessibility sizes a recent row is no taller than its two lines: no line for a chevron alone",
            arguments: largeSizes
        )
        func recentRow_accessibilitySizes_hasNoChevronLine(_ size: DynamicTypeSize) throws {
            let heights = try Self.rowHeights(at: size)
            #expect(heights.list.count == 2 && heights.bare.count == 2)
            for (row, bare) in zip(heights.list, heights.bare) {
                #expect(abs(row - bare) < 0.5, "\(size): a row is \(row) pt, its two lines alone \(bare) pt")
            }
        }

        /// Whether something taller than a rule is drawn in the trailing 20 points of the list: more inked rows
        /// in one column than the list has rules (three). At the standard sizes the two lines of a row end far
        /// from that edge, so only a chevron can be there. At the largest sizes a wrapped line reaches the edge
        /// (measured: this probe read text as a mark at accessibility4 and 5), so there the row's height is the
        /// proof, in `recentRow_accessibilitySizes_hasNoChevronLine`.
        static func drawsATrailingMark(at size: DynamicTypeSize) throws -> Bool {
            let model = try recent()
            let image = RenderedImage.render(
                RecentList(model: model) { _ in }.background(LedgerColor.ground),
                width: SnapshotConfig.phoneWidth, dynamicTypeSize: size
            )
            let buffer = try #require(image.flatMap(PixelBuffer.init))
            let ground = buffer.pixel(column: 0, row: 0)
            return (buffer.width - 20 ..< buffer.width).contains { column in
                (0 ..< buffer.height).count { buffer.pixel(column: column, row: $0).differs(from: ground, by: 24) } > 3
            }
        }

        @Test("The chevron is drawn at each of the seven standard sizes", arguments: Array(Layout.sizes.prefix(7)))
        func recentRow_chevron_isDrawnAtTheStandardSizes(_ size: DynamicTypeSize) throws {
            #expect(!size.isAccessibilitySize)
            #expect(try Self.drawsATrailingMark(at: size), "\(size): no chevron at the trailing edge")
        }

        @Test(
            "At the first three accessibility sizes nothing stands at the trailing edge where the chevron was",
            arguments: Array(largeSizes.prefix(3))
        )
        func recentRow_chevron_isGoneAtTheAccessibilitySizes(_ size: DynamicTypeSize) throws {
            #expect(try !Self.drawsATrailingMark(at: size), "\(size): a mark at the trailing edge")
        }

        @Test(
            "RECENT stands clear of the first row's rule at every text size, and further at the accessibility sizes",
            arguments: Layout.sizes
        )
        func recentEyebrow_clearsItsRule(_ size: DynamicTypeSize) throws {
            let placed = try Layout.placed(RecentList(model: Self.recent()) { _ in }, at: size)
            let eyebrow = try #require(placed.first { $0.stop.role == .heading })
            let firstRow = try #require(placed.first { $0.stop.role == .button })
            let gap = firstRow.frame.minY - eyebrow.frame.maxY
            #expect(gap >= (size.isAccessibilitySize ? 8 : 2), "\(size): \(gap) pt between RECENT and the rule")
        }

        @Test(
            "With no workout yet the empty sentence stands clear under RECENT at every text size",
            arguments: Layout.sizes
        )
        func recentEmpty_everySize_laysOutSanely(_ size: DynamicTypeSize) throws {
            let model = try #require(ViewsCases.all.first { $0.name == "no program" }?.model?.recent)
            let placed = Layout.placed(RecentList(model: model) { _ in }, at: size)
            #expect(placed.map(\.stop.role) == [.heading, .text], "\(size): \(placed.map(\.stop))")
            #expect(Layout.faults(in: placed).isEmpty, "\(size): \(Layout.faults(in: placed).prefix(3))")
        }
    }
#endif
