#if os(iOS)
    @testable import FeatureToday
    import Foundation
    import LedgerDesign
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F09 S4, gate G2: the off-schedule sheet (criterion 6, the brief's criterion 5) and the screen as a
    /// screen that scrolls (criterion 2). The reader cannot see inside a scroll view, so the sheet's rows are
    /// read from its page and its pinned parts with the reader's opt-in, as testing-strategy §2.6 says.
    @Suite("Adversarial F09 S4 · the sheet and the screen", .tags(.feature))
    struct TodayViewsSheetAdversarialTests {
        /// The rest day of the fixtures: Thursday of week 1, Upper A and Lower A already done.
        static func restDay() throws -> TodayModel.RestDay {
            let item = try #require(ViewsCases.all.first { $0.name == "rest day" })
            return try #require(item.model?.card.restDay)
        }

        @Test("The sheet's page reads its week, then one button per day of the program, Logged with a day done")
        func sheetPage_tree_isTheModels() throws {
            let model = try Self.restDay().offSchedule
            let found = TodayViews.stops(of: OffSchedulePage(model: model) { _ in })
            let difference = TodayViews.difference(found: found, expected: TodayViews.expectedSheetStops(model))
            #expect(difference.isEmpty, "\(difference.joined(separator: "\n"))")
            #expect(found.first?.description == "text \"Pick a day from week 1.\"")
            #expect(found.count == 5, "the brief's four days: \(found.count - 1) rows")
            #expect(found.count(where: { $0.label.hasSuffix(", Logged") }) == 2, "Upper A and Lower A are done")
        }

        @Test("Picking a day hands back exactly that day's route, once, a Logged day too")
        func sheetPage_pick_sendsTheDaysRoute() throws {
            let model = try Self.restDay().offSchedule
            var picked: [TodayRoute] = []
            let perStop = OffSchedulePage(model: model) { picked.append($0) }.withAccessibilityElements { elements in
                elements.map { element in
                    let before = picked.count
                    _ = element.accessibilityActivate()
                    return picked.count - before
                }
            }
            #expect(perStop == [0, 1, 1, 1, 1], "\(perStop)")
            #expect(picked.count == model.days.count)
            for (index, day) in model.days.enumerated() where index < picked.count {
                #expect(picked[index] == day.route, "row \(index + 1), \(day.name)")
            }
            #expect(Set(picked).count == 4, "four different days")
        }

        @Test("The routes of the sheet start each day of the program in the week on screen (criterion 5)")
        func sheetPage_routes_startEachDayOfTheWeek() throws {
            let program = try TodayAdversarial.seed()
            let routes = try Self.restDay().offSchedule.days.map(\.route)
            let expected = program.days.map { TodayRoute.startWorkout(program: program.id, weekIndex: 0, day: $0.id) }
            #expect(routes.count == expected.count)
            for (route, day) in zip(routes, expected) {
                #expect(route == day)
            }
        }

        @Test("A sheet with no days reads its week and nothing to tap; equal rows keep their own routes")
        func sheetPage_oddLists_areDrawnAsGiven() {
            let empty = ViewsCases.offSchedule(days: [])
            #expect(TodayViews.stops(of: OffSchedulePage(model: empty) { _ in }).map(\.description)
                == ["text \"From week 99.\""])
            let twins = ViewsCases.offSchedule(days: [
                .init(name: "Twin", detail: "1 exercise", logged: nil, route: .openProgram),
                .init(name: "Twin", detail: "1 exercise", logged: "Done before", route: .setUpProgram)
            ])
            var picked: [TodayRoute] = []
            let labels = OffSchedulePage(model: twins) { picked.append($0) }.withAccessibilityElements { elements in
                elements.map { element in
                    _ = element.accessibilityActivate()
                    return element.accessibilityLabel ?? ""
                }
            }
            #expect(labels == ["From week 99.", "Twin, 1 exercise", "Twin, 1 exercise, Done before"], "\(labels)")
            #expect(picked == [.openProgram, .setUpProgram], "\(picked.count) picks")
        }

        @Test(
            "The sheet's rows are 44 points high and inside the sheet at every text size",
            arguments: TodayViewsLayoutAdversarialTests.sizes
        )
        func sheetPage_everyTextSize_laysOutSanely(_ size: DynamicTypeSize) throws {
            let model = try Self.restDay().offSchedule
            let placed = TodayViewsLayoutAdversarialTests.placed(OffSchedulePage(model: model) { _ in }, at: size)
            let faults = TodayViewsLayoutAdversarialTests.faults(in: placed)
            #expect(faults.isEmpty, "\(size): \(faults.prefix(4).joined(separator: "\n"))")
        }

        @Test("Around its scroll view the sheet reads its title as a heading and Cancel, which cancels once")
        func sheet_pinnedParts_areTheTitleAndCancel() throws {
            let model = try Self.restDay().offSchedule
            let sent = TodayViews.Sent()
            let sheet = OffScheduleSheet(
                model: model,
                onPick: { sent.routes.append($0) },
                onCancel: { sent.cancels += 1 }
            )
            let found = sheet.withAccessibilityElements(outsideScrollViews: true) { elements in
                elements.map { element in
                    _ = element.accessibilityActivate()
                    return ViewStop(reading: element).description
                }
            }
            #expect(found == ["heading \"Train off-schedule\"", "button \"Cancel\""], "\(found)")
            #expect(sent.cancels == 1 && sent.routes.isEmpty, "\(sent.cancels) cancels, \(sent.routes.count) picks")
        }

        @Test("VoiceOver's escape gesture on the sheet cancels it")
        func sheet_escape_cancels() throws {
            let model = try Self.restDay().offSchedule
            let sent = TodayViews.Sent()
            let sheet = OffScheduleSheet(
                model: model,
                onPick: { sent.routes.append($0) },
                onCancel: { sent.cancels += 1 }
            )
            let escaped = sheet.withAccessibilityElements(outsideScrollViews: true) { elements in
                elements.first.map { ScrollViews.escape(from: $0) } ?? false
            }
            #expect(escaped && sent.cancels == 1, "escaped \(escaped), \(sent.cancels) cancels")
        }
    }

    // MARK: - A screen that scrolls

    /// Finds the scroll views under a hosted view, and offers VoiceOver's escape up an element's containers.
    /// A SwiftUI scroll view exists only in a window (measured in this slice's first run: none without one), so
    /// the view is hosted in `LedgerSnapshotTesting`'s scene-less window, which is internal to that module.
    enum ScrollViews {
        /// `view` in a window of an iPhone 17's size, handed to `body` once laid out.
        static func hosted<Result>(_ view: some View, _ body: (UIHostingController<AnyView>) -> Result) -> Result {
            let host = UIHostingController(rootView: AnyView(view))
            let frame = CGRect(x: 0, y: 0, width: SnapshotConfig.phoneWidth, height: 874)
            let window = SceneLessWindow.make(frame: frame)
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            return body(host)
        }

        static func count(in view: some View) -> Int {
            hosted(view) { scrollViews(under: $0.view).count }
        }

        static func scrollViews(under view: UIView) -> [UIScrollView] {
            ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews(under:))
        }

        static func escape(from element: NSObject) -> Bool {
            var candidate: NSObject? = element
            while let current = candidate {
                if current.accessibilityPerformEscape() {
                    return true
                }
                let selector = NSSelectorFromString("accessibilityContainer")
                let container = current.responds(to: selector)
                    ? current.perform(selector)?.takeUnretainedValue() as? NSObject : nil
                candidate = container ?? (current as? UIView)?.superview
            }
            return false
        }
    }

    extension TodayViewsSheetAdversarialTests {
        @Test(
            "The screen is one scroll view in every state, and the page and the sheet's page hold none",
            arguments: ViewsCases.all
        )
        func screen_isOneScrollViewAroundThePage(_ item: ViewsCase) {
            #expect(ScrollViews.count(in: TodayScreen(state: item.state) { _ in }) == 1, "\(item.name): the screen")
            #expect(ScrollViews.count(in: TodayViews.page(item)) == 0, "\(item.name): the page")
        }

        @Test(
            "The screen's page is as wide as the phone and never scrolls sideways, at the largest text size too",
            arguments: ViewsCases.all + ViewsCases.odd
        )
        func screen_neverScrollsSideways(_ item: ViewsCase) {
            for size in [DynamicTypeSize.large, .accessibility5] {
                let screen = TodayScreen(state: item.state) { _ in }.environment(\.dynamicTypeSize, size)
                let widths = ScrollViews.hosted(screen) { host in
                    ScrollViews.scrollViews(under: host.view).map(\.contentSize.width)
                }
                #expect(
                    widths.allSatisfy { $0 <= SnapshotConfig.phoneWidth + 0.5 },
                    "\(item.name) at \(size): \(widths)"
                )
            }
        }

        @Test("The sheet is one scroll view around its page")
        func sheet_isOneScrollViewAroundItsPage() throws {
            let model = try Self.restDay().offSchedule
            #expect(ScrollViews.count(in: OffScheduleSheet(model: model, onPick: { _ in }, onCancel: {})) == 1)
            #expect(ScrollViews.count(in: OffSchedulePage(model: model) { _ in }) == 0)
        }

        @Test("The screen has no pinned part: nothing is read outside its scroll view", arguments: ViewsCases.all)
        func screen_hasNoPinnedPart(_ item: ViewsCase) {
            let screen = TodayScreen(state: item.state) { _ in }.frame(height: 800)
            let outside = screen.withAccessibilityElements(outsideScrollViews: true) { $0.count }
            #expect(outside == 0, "\(item.name): \(outside) stops outside the scroll view")
        }

        @Test("A screen just drawn presents no sheet, on a rest day or any other", arguments: ViewsCases.all)
        func screen_justDrawn_presentsNothing(_ item: ViewsCase) {
            let presents = ScrollViews.hosted(TodayScreen(state: item.state) { _ in }) {
                $0.presentedViewController != nil || $0.view.window?.rootViewController?.presentedViewController != nil
            }
            #expect(!presents, "\(item.name)")
        }
    }
#endif
