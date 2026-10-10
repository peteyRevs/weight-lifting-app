#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    import LedgerDesign
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F10 S6, criteria 1, 9, 10 and 12 to 14: the rest panel as it is drawn. Its VoiceOver stops and what
    /// its buttons send; that nothing of it is cut, leaves the phone or lies over something else in any
    /// setting; its place on the real screen, as the scroll view's bottom inset; and its references.
    /// (`SceneLessWindow` is internal to `LedgerSnapshotTesting`, hence the `@testable` import.)
    @Suite("Rest panel", .serialized, .tags(.feature))
    struct RestPanelTests {
        nonisolated static let sizes = WorkoutPageLayoutTests.sizes
        nonisolated static let states: [WorkoutPreview] = [.resting, .restOver]

        static func model(_ preview: WorkoutPreview) throws -> RestPanelModel {
            try #require(preview.model.rest, "\(preview.rawValue) shows no rest")
        }

        static func panel(_ preview: WorkoutPreview, send: @escaping (WorkoutAction) -> Void = { _ in
        }) throws -> some View {
            try RestPanel(model: model(preview), send: send)
        }

        /// A panel whose next set is as long as a line gets: a number of three digits, a load of six with a
        /// fraction, reps of three.
        static func longWords() throws -> RestPanelModel {
            var workout = try Fixtures.seedSession()
            workout.exercises[0].sets = (0 ..< 120).map { index in
                LoggedSet(
                    id: .derived(from: workout.exercises[0].id, index: index),
                    weight: .pounds(1247.5),
                    reps: Reps(clamping: 125),
                    kind: .working,
                    doneAt: index < 119 ? workout.startedAt : nil
                )
            }
            workout.cursor = Cursor(exerciseIndex: 0, setIndex: 119)
            workout.rest = RestTimer(endsAt: workout.startedAt.addingTimeInterval(3540), total: .seconds(3600))
            return try #require(WorkoutPresentation.rest(
                workout, at: workout.startedAt.addingTimeInterval(1), selection: nil, isBusy: false,
                locale: Fixtures.locale
            ))
        }

        // MARK: Criteria 1 and 12: what it reads and sends

        @Test("The panel is three stops: the time left with the next set, then +30s by its spoken name, then Skip rest")
        func tree_isExactlyTheTable() throws {
            for preview in Self.states {
                for appearance in WorkoutAccessibilityTests.appearances {
                    let found = try Self.panel(preview).accessibilityElements(appearance).map {
                        Stop($0.label, value: $0.value, $0.traits)
                    }
                    let difference = try firstDifference(found: found, expected: #require(WorkoutTrees.rests[preview]))
                    #expect(difference == nil, "\(preview.rawValue) at \(appearance)")
                }
            }
        }

        @Test("VoiceOver hears the time left in words, never digits and a colon, and the stop updates often")
        func timeLeft_isSpokenAsADuration() throws {
            let stops = try Self.panel(.resting).accessibilityElements(SnapshotAppearance(.light, .large))
            let spoken = stops.map { $0.label + $0.value }.joined()
            #expect(!spoken.contains(":"))
            #expect(stops.first?.value == "1 minute, 15 seconds")
            #expect(stops.first?.traits.contains(.updatesFrequently) == true)
            let over = try Self.panel(.restOver).accessibilityElements(SnapshotAppearance(.light, .large))
            #expect(over.first?.label.hasPrefix("Rest over") == true)
            #expect(over.first?.traits.contains(.updatesFrequently) == false)
        }

        @Test("+30s and Skip rest each send their own edit, once; while a discard runs neither sends anything")
        func buttons_sendTheirEdits() throws {
            var sent: [WorkoutAction] = []
            try Self.panel(.resting) { sent.append($0) }.withAccessibilityElements { elements in
                for element in elements {
                    _ = element.accessibilityActivate()
                }
            }
            #expect(sent == [.edit(.extendRest), .edit(.skipRest)])
            sent = []
            let busy = try #require(WorkoutPreview.discarding.model.rest)
            #expect(!busy.isEnabled)
            RestPanel(model: busy) { sent.append($0) }.withAccessibilityElements { elements in
                for element in elements {
                    _ = element.accessibilityActivate()
                }
            }
            #expect(sent == [])
        }

        // MARK: Criterion 13: sizes and settings

        static func parts(of model: RestPanelModel) -> [LayoutPart] {
            [
                LayoutPart([model.status, model.next?.spoken].compactMap(\.self).joined(separator: ", ")) {
                    RestReading(model: model)
                },
                LayoutPart(model.skip) { PrimaryButton(model.skip) {} }
            ]
        }

        static func models() throws -> [RestPanelModel] {
            try states.map(model) + [longWords()]
        }

        @Test("No word of the panel is cut, in any setting", arguments: sizes)
        func panel_noWordIsCut(_ size: DynamicTypeSize) throws {
            for model in try Self.models() {
                let panel = RestPanel(model: model) { _ in }
                for setting in LayoutSetting.sweep(size) {
                    let cut = WorkoutLayoutProbe.cut(in: panel, parts: Self.parts(of: model), setting)
                    #expect(cut.isEmpty, "\(setting.testDescription): \(cut.prefix(2).joined(separator: "; "))")
                }
            }
        }

        @Test("Every stop is inside the phone, none lies over another, and both buttons are 44 pt", arguments: sizes)
        func panel_nothingLeavesOrOverlaps(_ size: DynamicTypeSize) throws {
            for model in try Self.models() {
                let panel = RestPanel(model: model) { _ in }
                for setting in LayoutSetting.sweep(size) {
                    let misplaced = WorkoutLayoutProbe.misplaced(in: panel, setting)
                    #expect(
                        misplaced.isEmpty,
                        "\(setting.testDescription): \(misplaced.prefix(2).joined(separator: "; "))"
                    )
                    let buttons = setting.elements(of: panel).filter { $0.traits.contains(.button) }
                    #expect(buttons.count == 2, "\(setting.testDescription)")
                    let small = buttons.filter { $0.frame.width < 44 - 0.001 || $0.frame.height < 44 - 0.001 }
                    #expect(small.isEmpty, "\(setting.testDescription): \(small.map(\.label))")
                }
            }
        }

        @Test("The check sees a next-set line that is cut")
        func check_seesACut() throws {
            let model = try Self.longWords()
            let parts = [Self.parts(of: model)[0]]
            let cutOne = RestReading(model: model).lineLimit(1).frame(width: 200, alignment: .leading)
            #expect(WorkoutLayoutProbe.cut(in: cutOne, parts: parts, LayoutSetting()).count == 1)
        }

        // MARK: Criterion 14: Reduce Motion

        @Test("With Reduce Motion the ring is not animated between two seconds; without, it moves over the second")
        func ring_reduceMotion() {
            #expect(RestPanel.ringAnimation(reduceMotion: true) == nil)
            #expect(RestPanel.ringAnimation(reduceMotion: false) == .linear(duration: 1))
        }
    }

    /// F10 S6, criteria 1 and 13: the panel's place on the real screen, hosted at an iPhone 17's size. It
    /// floats over the scroll view's end, which keeps room for it under the page.
    @Suite("Rest panel on the screen", .serialized, .tags(.feature))
    struct RestPanelPlaceTests {
        /// A scroll view as it was measured: its frame in the window, the room it keeps under its content,
        /// and the size of what it scrolls.
        struct Scroll {
            let frame: CGRect
            let bottomInset: CGFloat
            let content: CGSize
        }

        /// The real screen's scroll view, hosted at an iPhone 17's size at `textSize`.
        private static func scroll(_ model: WorkoutScreenModel, at textSize: DynamicTypeSize) throws -> Scroll {
            let phone = WorkoutScreenTests.phone
            let screen = WorkoutScreen(model: model) { _ in }
                .frame(height: phone.height)
                .environment(\.dynamicTypeSize, textSize)
            let host = UIHostingController(rootView: screen)
            let window = SceneLessWindow.make(frame: CGRect(origin: .zero, size: phone))
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            host.view.layoutIfNeeded()
            let found = try #require(WorkoutPageViewsAdversarialTests.scrollView(in: host.view))
            return Scroll(
                frame: found.convert(found.bounds, to: nil),
                bottomInset: found.adjustedContentInset.bottom,
                content: found.contentSize
            )
        }

        /// The same workout with no moment to read its rest at: the same page, and no panel.
        private static func withoutThePanel(_ preview: WorkoutPreview) throws -> WorkoutScreenModel {
            try WorkoutPresentation.screen(
                .loaded(preview.workout()), selection: preview.selection, now: nil, isBusy: false,
                locale: Fixtures.locale, calendar: Fixtures.calendar
            )
        }

        @Test(
            "On the screen the panel is the scroll view's bottom inset: the page's end scrolls clear of it",
            arguments: [DynamicTypeSize.large, .accessibility3, .accessibility5]
        )
        func screen_keepsRoomForThePanel(_ size: DynamicTypeSize) throws {
            let resting = try Self.scroll(WorkoutPreview.resting.model, at: size)
            let without = try Self.scroll(Self.withoutThePanel(.resting), at: size)
            #expect(resting.frame == without.frame, "the panel floats: it takes nothing from the scroll view's frame")
            #expect(resting.content == without.content, "the page is the same page")
            // The panel's three stops, outside the scroll view, in the window's coordinates.
            let panel = WorkoutScreenTests.screen(.resting)
                .accessibilityElements(SnapshotAppearance(.light, size), outsideScrollViews: true)
                .suffix(3)
            #expect(panel.map(\.label).last == "Skip rest")
            let top = try #require(panel.map(\.frame.minY).min())
            let bottom = try #require(panel.map(\.frame.maxY).max())
            let room = resting.bottomInset - without.bottomInset
            #expect(room >= bottom - top, "the page keeps \(room) pt; the panel's stops span \(bottom - top)")
        }
    }

    /// The panel against its references (F10 S6, criterion 13, as the plan's table lists them): alone,
    /// resting and at "Rest over", light and dark at `.large` and `.xLarge`, and once dark at
    /// `.accessibility3`; and the whole screen resting, light and dark. Recorded on the PR plan's iPhone 17
    /// (iOS 27.0); the Mac host draws none.
    @Suite("Rest panel snapshots", .serialized, .tags(.feature, .snapshot))
    struct RestPanelSnapshotTests {
        private func alone(_ preview: WorkoutPreview) throws -> some View {
            try RestPanelTests.panel(preview)
                .padding(LedgerSpacing.l)
                .frame(width: SnapshotConfig.phoneWidth)
                .background(LedgerColor.ground)
        }

        @Test("The panel while resting matches its references: half a ring, 1:15, the next set")
        func panel_resting_matchesReferences() throws {
            try assertLedgerSnapshot(of: alone(.resting), devices: [.phone], typeSizes: [.large, .xLarge])
        }

        @Test("The panel at Rest over matches its references: an empty ring, 0:00")
        func panel_restOver_matchesReferences() throws {
            try assertLedgerSnapshot(of: alone(.restOver), devices: [.phone], typeSizes: [.large, .xLarge])
        }

        @Test("The panel at the largest text size of the matrix: the lines under the ring, the buttons stacked")
        func panel_resting_accessibility3_matchesReference() throws {
            try assertLedgerSnapshot(
                of: alone(.resting),
                devices: [.phone],
                themes: [.dark],
                typeSizes: [.accessibility3]
            )
        }

        @Test("The whole screen while resting: the panel floats over the page's end")
        func screen_resting_matchesReferences() {
            let screen = WorkoutScreenTests.screen(.resting).frame(width: SnapshotConfig.phoneWidth)
            assertLedgerSnapshot(of: screen, devices: [.phone], typeSizes: [.large])
        }
    }
#endif
