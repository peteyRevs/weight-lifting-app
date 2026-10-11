#if os(iOS) && DEBUG
    import Dependencies
    @testable import FeatureWorkout
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// G2, F10 S6: the panel on the hosted screen. Its share of three phones at every text size (criteria 1
    /// and 13, and the brief's Dynamic Type to AX5), and `WorkoutRoot` itself running the store's tasks
    /// (criteria 3 and 7).
    extension WorkoutRestPanelAdversarialTests {
        // MARK: Criteria 1 and 13: the panel's share of the screen

        /// The top safe area the simulator's window keeps, scene or no scene: the PR plan's iPhone 17's.
        /// `screen_roomIsMeasured` checks it, so that a run on another simulator fails there and not in a
        /// finding.
        nonisolated static let simulatorTop: CGFloat = 62

        /// Three phones by the height the cover has between its safe areas: a 375 pt phone with a home
        /// button (667 pt tall, 20 pt of status bar), a 375 pt phone with a notch (812 pt, 50 and 34 pt of
        /// safe area), and an iPhone 17 (874 pt, 62 and 34 pt). Each is hosted in a window that is that
        /// much taller than the simulator's top safe area, and ends where the phone's bottom safe area
        /// would begin.
        nonisolated static let phones: [(name: String, size: CGSize)] = [
            ("375 pt, home button (647 pt between the safe areas)", CGSize(width: 375, height: 647 + simulatorTop)),
            ("375 pt, notch (728 pt)", CGSize(width: 375, height: 728 + simulatorTop)),
            ("iPhone 17 (778 pt)", CGSize(width: 402, height: 778 + simulatorTop))
        ]

        /// What the hosted screen gives the page and the panel.
        struct Room {
            /// The scroll view's height: from the header's end to the screen's.
            let scroll: CGFloat
            /// The panel's height with its margin: the room the scroll view keeps under the page.
            let panel: CGFloat
            /// Where the panel's last stop ends, from the screen's top.
            let panelEnd: CGFloat
            /// The height of the page that shows over the panel.
            var page: CGFloat {
                scroll - panel
            }
        }

        static func room(
            on phone: CGSize,
            at size: DynamicTypeSize,
            _ preview: WorkoutPreview = .resting
        ) throws -> Room {
            let screen = WorkoutScreen(model: preview.model, rest: preview.restPanel) { _ in }
                .environment(\.workoutTimeline, .fixed(at: preview.now))
            let host = UIHostingController(rootView: screen.environment(\.dynamicTypeSize, size))
            let window = SceneLessWindow.make(frame: CGRect(origin: .zero, size: phone))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            let found = try #require(WorkoutPageViewsAdversarialTests.scrollView(in: host.view))
            // The panel's stops, from a marker over the screen: the reader hosts the view where it likes.
            let marked = VStack(spacing: 0) {
                Color.clear.frame(height: 1).accessibilityElement().accessibilityLabel(Text(verbatim: "Top"))
                screen.frame(width: phone.width, height: phone.height)
            }
            let stops = marked.accessibilityElements(SnapshotAppearance(.light, size), outsideScrollViews: true)
            let top = try #require(stops.first { $0.label == "Top" }).frame.maxY
            let skip = try #require(stops.last { $0.label == "Skip rest" })
            return Room(
                scroll: found.bounds.height, panel: found.adjustedContentInset.bottom, panelEnd: skip.frame.maxY - top
            )
        }

        /// The shortest stretch of page that is of any use over the panel: one 44 pt target to see and to
        /// drag (a drag that starts on the panel scrolls nothing).
        nonisolated static let leastPage: CGFloat = 44

        /// The phones on which the panel leaves the page less than `leastPage`, or ends below the screen.
        static func crowded(at size: DynamicTypeSize) throws -> [String] {
            try phones.compactMap { phone in
                let room = try room(on: phone.size, at: size)
                var faults: [String] = []
                if room.page < leastPage {
                    faults.append("\(Int(room.page)) pt of page over a panel of \(Int(room.panel)) pt")
                }
                if room.panelEnd > phone.size.height + 0.5 {
                    faults.append("Skip rest ends \(Int(room.panelEnd - phone.size.height)) pt below the screen")
                }
                return faults.isEmpty ? nil : "\(phone.name): " + faults.joined(separator: ", ")
            }
        }

        @Test("The room is measured: the window's safe area is the one assumed, and the panel is the inset")
        func screen_roomIsMeasured() throws {
            for phone in Self.phones {
                let room = try Self.room(on: phone.size, at: .large)
                // At the default size the header is 112 pt with its margins (measured), under the safe area.
                let underTheHeader = phone.size.height - Self.simulatorTop - 112
                #expect(abs(room.scroll - underTheHeader) < 2, "\(phone.name): the scroll view is \(room.scroll) pt")
                #expect((170 ... 180).contains(room.panel), "\(phone.name): \(room.panel)")
                #expect(room.panelEnd < phone.size.height)
            }
            // The running app at Accessibility 5 on the iPhone 17 shows 64 pt of page over the panel
            // (the UI test's screenshot, `WorkoutRestAdversarial`): the model agrees.
            // F10 S6 fix round 1 (sanctioned edit, ruling 17): the panel is compact at the accessibility
            // sizes, and the page showing here was measured at 313.7 pt. The range was 55 ... 75, the old
            // panel's.
            let largest = try Self.room(on: Self.phones[2].size, at: .accessibility5)
            #expect((304 ... 324).contains(largest.page), "\(largest.page)")
        }

        @Test(
            "Up to Accessibility 3 (criterion 13) the panel leaves a strip of the page to show a row in and to drag",
            arguments: everySize.filter { $0 <= .accessibility3 }
        )
        func screen_leavesThePageRoom(_ size: DynamicTypeSize) throws {
            let crowded = try Self.crowded(at: size)
            #expect(crowded.isEmpty, "\(crowded.joined(separator: "; "))")
        }

        /// F10-S6-4 (the brief's accessibility line: Dynamic Type to AX5). Beyond criterion 13's size, on
        /// the two 375 pt phones: the page is left less than one 44 pt target, and on the shorter one at
        /// Accessibility 5 the panel is taller than the room under the header.
        @Test(
            "F10-S6-4: at Accessibility 4 and 5 the panel still leaves a strip of the page, and stays on the screen",
            arguments: [DynamicTypeSize.accessibility4, .accessibility5]
        )
        func screen_leavesThePageRoom_beyondTheCriterion(_ size: DynamicTypeSize) throws {
            let crowded = try Self.crowded(at: size)
            #expect(crowded.isEmpty, "\(crowded.joined(separator: "; "))")
        }

        // MARK: Criteria 3 and 7 in the hosted root

        /// One pass of the main run loop, without waiting: a synchronous function, because the run loop is
        /// not to be run from an asynchronous one.
        static func turnTheRunLoop() {
            RunLoop.main.run(mode: .default, before: Date())
        }

        /// Lets the run loop and the main actor's queue both turn until `condition` holds: SwiftUI starts a
        /// `.task` after its view appears, which is the run loop's doing. No time is waited for.
        static func turning(_ what: String, until condition: () -> Bool) async -> Bool {
            for _ in 0 ..< 20000 {
                if condition() {
                    return true
                }
                turnTheRunLoop()
                await Task.yield()
            }
            Issue.record("never came: \(what)")
            return false
        }

        /// `WorkoutRoot` in a window, over a store whose clock the test steps and whose haptics it reads.
        struct HostedRoot {
            let running: WorkoutState
            let store: WorkoutStore
            let clock = RestProbeClock()
            let haptics = FakeHaptics()
            let host: UIViewController
            let window: UIWindow

            init() throws {
                running = try Fixtures.seedSession()
                store = try WorkoutScene.onFake(live: running).store { [clock, haptics] in
                    $0.haptics = haptics
                    $0.continuousClock = clock
                    $0.date = DateGenerator { Fixtures.now.addingTimeInterval(clock.elapsed / .seconds(1)) }
                }
                let root = WorkoutRoot(store: store) { _ in }.environment(\.dynamicTypeSize, .accessibility3)
                host = UIHostingController(rootView: root)
                window = SceneLessWindow.make(frame: CGRect(origin: .zero, size: WorkoutScreenTests.phone))
                window.rootViewController = host
                window.isHidden = false
                host.view.layoutIfNeeded()
            }

            func close() {
                window.isHidden = true
                window.rootViewController = nil
            }

            /// `count` seconds go by, one at a time; after each the root's task has read the date and sleeps
            /// again, or the rest is over.
            func seconds(_ count: Int) async {
                for _ in 0 ..< count {
                    let sleeps = clock.sleeps.value
                    await clock.base.advance(by: .seconds(1))
                    _ = await turning("a second of the rest") {
                        clock.sleeps.value > sleeps || store.restPanel?.isOver == true
                    }
                    host.view.layoutIfNeeded()
                }
            }
        }

        @Test("WorkoutRoot keeps the rest's time itself: it counts down, the page stays where it was scrolled")
        func root_keepsTheRestsTime() async throws {
            let hosted = try HostedRoot()
            defer { hosted.close() }
            let (store, clock) = (hosted.store, hosted.clock)
            guard await Self.turning("the root's task to follow the session", until: { store.isHearingTheSession })
            else {
                return
            }
            #expect(store.moment == nil)
            store.send(.edit(.log(exerciseIndex: 0, setID: hosted.running.exercises[0].sets[0].id)))
            guard await Self.turning("the root's tasks to log the set and read the date", until: {
                store.moment != nil && clock.sleeps.value > 0
            }) else {
                return
            }
            #expect(store.restPanel?.clock == "2:30")
            hosted.host.view.layoutIfNeeded()
            let scroll = try #require(WorkoutPageViewsAdversarialTests.scrollView(in: hosted.host.view))
            scroll.setContentOffset(CGPoint(x: 0, y: 30), animated: false)
            await hosted.seconds(3)
            #expect(store.restPanel?.clock == "2:27")
            #expect(scroll.contentOffset.y == 30, "a second going by moves the page")
            let isTheSameView = WorkoutPageViewsAdversarialTests.scrollView(in: hosted.host.view) === scroll
            #expect(isTheSameView, "the scroll view was made again")
            // The rest reaches its end with the cover up: felt once.
            await hosted.seconds(147)
            #expect(store.restPanel?.status == "Rest over")
            for _ in 0 ..< 200 {
                Self.turnTheRunLoop()
                await Task.yield()
            }
            #expect(await hosted.haptics.played == [.setLogged, .restOver])
        }
    }
#endif
