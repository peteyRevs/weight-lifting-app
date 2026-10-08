#if os(iOS)
    @testable import FeatureToday
    import Foundation
    import LedgerDesign
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F09 S4, gate G2: the layout by measurement at every text size (criteria 3 and 6, the brief's Dynamic Type
    /// non-functional), the resume button's time (criterion 5), and the two states that draw no model.
    @Suite("Adversarial F09 S4 · layout, the timer, loading and failed", .tags(.feature))
    struct TodayViewsLayoutAdversarialTests {
        nonisolated static let sizes: [DynamicTypeSize] = [
            .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
            .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5
        ]

        /// A stop with where it stands.
        struct Placed {
            let stop: ViewStop
            let frame: CGRect
        }

        static func placed(_ view: some View, at size: DynamicTypeSize) -> [Placed] {
            view.withAccessibilityElements(SnapshotAppearance(.light, size)) { elements in
                elements.map { Placed(stop: ViewStop(reading: $0), frame: $0.accessibilityFrame) }
            }
        }

        /// What is wrong with the frames of `stops` on a page 402 points wide, a line each.
        nonisolated static func faults(in stops: [Placed]) -> [String] {
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
                if item.stop.role == .button, frame.height < 43.5 || frame.width < 43.5 {
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
            "At every text size no stop is empty, outside the page, under 44 points or over another",
            arguments: ViewsCases.all
        )
        func page_everyTextSize_laysOutSanely(_ item: ViewsCase) {
            for size in Self.sizes {
                let faults = Self.faults(in: Self.placed(TodayViews.page(item), at: size))
                #expect(faults.isEmpty, "\(item.name) at \(size): \(faults.prefix(4).joined(separator: "\n"))")
            }
        }

        @Test(
            "Long, empty and right-to-left texts stay inside the page at the default and the largest size",
            arguments: ViewsCases.odd
        )
        func page_oddModels_layOutSanely(_ item: ViewsCase) {
            for size in [DynamicTypeSize.large, .accessibility5] {
                let faults = Self.faults(in: Self.placed(TodayViews.page(item), at: size))
                #expect(faults.isEmpty, "\(item.name) at \(size): \(faults.prefix(4).joined(separator: "\n"))")
            }
        }

        @Test("Stops are read from the top of the page down at every text size", arguments: ViewsCases.all)
        func page_readingOrder_followsThePage(_ item: ViewsCase) {
            for size in [DynamicTypeSize.large, .accessibility3, .accessibility5] {
                let tops = Self.placed(TodayViews.page(item), at: size)
                // The gear stands beside the date and the title, and a tile beside a tile: one row.
                let gear = item.model?.header.settings.title
                let backwards = zip(tops, tops.dropFirst())
                    .filter { $1.frame.maxY <= $0.frame.minY && $1.stop.label != gear }
                    .map { "\($1.stop) is read after \($0.stop) and stands above it" }
                #expect(backwards.isEmpty, "\(item.name) at \(size): \(backwards.prefix(3).joined(separator: "\n"))")
            }
        }
    }

    // MARK: - Right to left, and where orange is

    extension TodayViewsLayoutAdversarialTests {
        @Test(
            "Laid out right to left the page reads the same tree and stays inside the page",
            arguments: ViewsCases.all
        )
        func page_rightToLeft_readsTheSameTree(_ item: ViewsCase) {
            let page = TodayViews.page(item).environment(\.layoutDirection, .rightToLeft)
            let difference = TodayViews.difference(
                found: TodayViews.stops(of: page), expected: TodayViews.expectedStops(for: item.state)
            )
            #expect(difference.isEmpty, "\(item.name): \(difference.joined(separator: "\n"))")
            for size in [DynamicTypeSize.large, .accessibility5] {
                let faults = Self.faults(in: Self.placed(page, at: size))
                #expect(faults.isEmpty, "\(item.name) at \(size): \(faults.prefix(4).joined(separator: "\n"))")
            }
        }

        /// How many pixels of `view`, drawn dark, are orange in hue: far more red than green, more green than
        /// blue. Every grey of the ground and the ink has the three alike, and thin text need not reach a
        /// token's exact colour at 1×, so the scan goes by hue.
        static func orangePixels(in view: some View) throws -> Int {
            try drawn(view).pixels.count { pixel in
                Int(pixel.red) > Int(pixel.green) + 40 && Int(pixel.green) > Int(pixel.blue) + 15 && pixel.red > 110
            }
        }

        @Test("Orange is the main button's, UP NEXT's, today's mark's and the change's alone (decision #17)")
        func orange_isOnlyWhereTheBriefAllowsIt() throws {
            let logged = try #require(ViewsCases.all.first { $0.name == "logged" }?.model)
            let rest = try #require(ViewsCases.all.first { $0.name == "rest day" }?.model)
            let card = try #require(logged.card.logged)
            let restCard = try #require(rest.card.restDay)
            #expect(try Self.orangePixels(in: LoggedCard(model: card) { _ in }) == 0, "the Logged card")
            #expect(try Self.orangePixels(in: RestDayCard(model: restCard) { _ in }) == 0, "the rest-day card")
            #expect(try Self.orangePixels(in: RecentList(model: logged.recent) { _ in }) == 0, "the recent list")
            #expect(try Self.orangePixels(in: TodayHeader(model: logged.header) { _ in }) == 0, "the header")
            #expect(try Self.orangePixels(in: OffSchedulePage(model: restCard.offSchedule) { _ in }) == 0, "the sheet")
            // Controls: the scan does see orange where it is meant to be.
            let monday = try #require(ViewsCases.all.first { $0.name == "Monday, nothing moved" }?.model)
            #expect(monday.stats.volume.delta != nil && logged.stats.volume.delta == nil, "the fixtures' changes")
            #expect(try Self.orangePixels(in: StatsRow(model: monday.stats)) > 0, "the change against last week")
            #expect(try Self.orangePixels(in: StatsRow(model: logged.stats)) == 0, "tiles with no change")
            #expect(try Self.orangePixels(in: WeekStrip(days: rest.weekStrip)) > 0, "today's mark")
        }
    }

    // MARK: - Loading and failed

    extension TodayViewsLayoutAdversarialTests {
        static func drawn(_ view: some View, height: CGFloat? = nil) throws -> PixelBuffer {
            let image = RenderedImage.render(
                view.background(LedgerColor.ground), width: SnapshotConfig.phoneWidth, height: height
            )
            return try #require(image.flatMap(PixelBuffer.init))
        }

        @Test("While loading, and before, the page draws nothing at all", arguments: ["loading", "idle"])
        func page_loading_drawsNothing(_ name: String) throws {
            let item = try #require(ViewsCases.all.first { $0.name == name })
            let buffer = try Self.drawn(TodayViews.page(item).frame(width: SnapshotConfig.phoneWidth, height: 600))
            let ground = buffer.pixel(column: 0, row: 0)
            #expect(!buffer.pixels.contains { $0 != ground }, "\(name) draws something on the ground")
            #expect(TodayViews.stops(of: TodayViews.page(item).frame(height: 600)).isEmpty)
        }

        @Test("A failed load reads the two texts of Pete's decision 5 and offers nothing to tap")
        func page_failed_readsTheTwoTexts() throws {
            let item = try #require(ViewsCases.all.first { $0.name == "failed" })
            let found = TodayViews.stops(of: TodayViews.page(item)).map(\.description)
            #expect(found == [
                "heading \"Can't show today right now\"",
                "text \"Your workouts are still on this iPhone. Open the app again to try once more.\""
            ], "\(found)")
        }

        @Test("A failed load never shows the error it was handed")
        func page_failed_showsNoRawError() {
            struct Loud: Error, CustomStringConvertible {
                let description = "SQLITE_CORRUPT 11"
            }
            let labels = TodayViews.stops(of: TodayViews.page(ViewsCase(name: "loud", state: .failed(Loud()))))
                .map(\.label)
            #expect(!labels.contains { $0.contains("SQLITE") || $0.contains("Loud") }, "\(labels)")
        }
    }

    // MARK: - The resume button's time

    extension TodayViewsLayoutAdversarialTests {
        /// The live card with its time standing still `seconds` after the model's moment.
        static func liveCard(pausedAfter seconds: TimeInterval) throws -> PixelBuffer {
            let item = try #require(ViewsCases.all.first { $0.name == "live workout" })
            let card = try #require(item.model?.card.upNext)
            return try drawn(
                UpNextCard(model: card) { _ in }.environment(\.todayTimerPause, item.now.addingTimeInterval(seconds))
            )
        }

        @Test("Frozen, the resume button draws the same every time; a second later it draws another time")
        func resumeButton_frozen_isStillAndCountsFromTheStart() throws {
            let atTheMoment = try Self.liveCard(pausedAfter: 0)
            #expect(try atTheMoment == Self.liveCard(pausedAfter: 0), "two drawings of one frozen moment differ")
            #expect(try atTheMoment != Self.liveCard(pausedAfter: 1), "3:00 and 3:01 draw alike: the time is not drawn")
            #expect(try atTheMoment != Self.liveCard(pausedAfter: 600), "3:00 and 13:00 draw alike")
        }

        /// How many columns the ink of `text` spans, in the body role.
        static func inkWidth(of text: Text) throws -> Int {
            let image = RenderedImage.render(text.ledgerFont(.body).padding(8).background(LedgerColor.ground))
            let buffer = try #require(image.flatMap(PixelBuffer.init))
            return try #require(buffer.inkedColumns(differingFrom: buffer.pixel(column: 0, row: 0))).count
        }

        @Test("The timer line is the catalog's Resume · %@ with the time as m:ss", arguments: [
            (180, "Resume · 3:00"), (9, "Resume · 0:09"), (3725, "Resume · 1:02:05")
        ])
        func resumeLine_readsAsTheModelsTitle(_ seconds: Int, _ line: String) throws {
            let start = Fixtures.now
            let timer = TodayCopy.resume(since: start, pausedAt: start.addingTimeInterval(Double(seconds)))
            let drawn = try Self.inkWidth(of: timer)
            let written = try Self.inkWidth(of: Text(verbatim: line))
            #expect(abs(drawn - written) <= 4, "the timer line is \(drawn) px wide, \"\(line)\" is \(written)")
            #expect(TodayCopy.resume(TodayAdversarialClock.text(seconds), locale: Fixtures.locale) == line)
        }

        @Test("VoiceOver reads the resume button as the model's title, a button that does not update by itself")
        func resumeButton_isReadAsTheModelsTitle() throws {
            let item = try #require(ViewsCases.all.first { $0.name == "live workout" })
            let traits = TodayViews.page(item).withAccessibilityElements { elements in
                elements.filter { $0.accessibilityLabel == "Resume · 3:00" }.map(\.accessibilityTraits)
            }
            #expect(traits.count == 1, "\(traits.count) stops read Resume · 3:00")
            #expect(traits.allSatisfy { $0.contains(.button) && !$0.contains(.updatesFrequently) })
        }

        /// Spec question F9-S4 (see the findings): what VoiceOver reads once the drawn time has moved on. The
        /// plan gives the model's title, which is the time at the model's moment; this pins what is read 20
        /// minutes later, with no new model.
        @Test("Twenty minutes on, with no new model, VoiceOver still reads the model's moment (characterisation)")
        func resumeButton_spokenTime_isTheModelsMoment() throws {
            let item = try #require(ViewsCases.all.first { $0.name == "live workout" })
            let later = TodayPage(state: item.state) { _ in }
                .environment(\.todayTimerPause, item.now.addingTimeInterval(1200))
            let resume = TodayViews.stops(of: later).filter { $0.role == .button && $0.label.hasPrefix("Resume") }
            #expect(resume.map(\.label) == ["Resume · 3:00"], "\(resume)")
        }
    }

    /// m:ss as the Domain writes a clock, for the tests above: written here, not asked of the feature.
    nonisolated enum TodayAdversarialClock {
        static func text(_ seconds: Int) -> String {
            let (hours, minutes, rest) = (seconds / 3600, seconds % 3600 / 60, seconds % 60)
            let tail = rest < 10 ? "0\(rest)" : "\(rest)"
            guard hours > 0 else {
                return "\(minutes):\(tail)"
            }
            return "\(hours):" + (minutes < 10 ? "0\(minutes)" : "\(minutes)") + ":\(tail)"
        }
    }
#endif
