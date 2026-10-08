#if os(iOS) && DEBUG
    @testable import FeatureToday
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// F09 S4, criteria 6 and 7: the intended VoiceOver tree of each state, as the implementation notes write
    /// them, pinned exactly (the stops, their order, labels, values and traits), and what each control sends.
    /// Read through UIKit's accessibility tree, as VoiceOver reads it, at the default text size and at the
    /// largest of the snapshot matrix.
    ///
    /// The trees are read from the page (`TodayParts`), not from the screen: the screen puts the page in a
    /// scroll view, which the hosted reader cannot see inside (testing-strategy §2.6). The same stops in the
    /// same order inside the real scroll view are S5's nightly UI test, when the screen is in the app.
    @Suite("Today accessibility", .serialized, .tags(.feature))
    struct TodayAccessibilityTests {
        nonisolated static let appearances = [
            SnapshotAppearance(.light, .large),
            SnapshotAppearance(.dark, .accessibility3)
        ]

        /// The view a state's tree is read from: its page, or the sheet's parts for the sheet's case.
        private static func parts(
            _ preview: TodayPreview,
            send: @escaping (TodayAction) -> Void = { _ in }
        ) throws -> AnyView {
            guard preview == .offSchedule else {
                return AnyView(TodayParts(preview: preview, send: send))
            }
            return try AnyView(OffScheduleParts.ofTheRestDay(onPick: { send(.route($0)) }, onCancel: {}))
        }

        @Test(
            "Every state has exactly its intended VoiceOver tree, at the default and the largest text size",
            arguments: TodayPreview.allCases
        )
        func tree_isExactlyTheTable(_ preview: TodayPreview) throws {
            for appearance in Self.appearances {
                let found = try Self.parts(preview).accessibilityElements(appearance).map {
                    Stop($0.label, value: $0.value, $0.traits)
                }
                let expected = try #require(TodayTrees.byState[preview], "no tree is written for this state")
                let difference = firstDifference(found: found, expected: expected)
                #expect(difference == nil, "\(preview.rawValue) at \(appearance)")
            }
        }

        @Test(
            "Every button's target is at least 44 by 44 points, at the default and the largest text size",
            arguments: TodayPreview.allCases
        )
        func buttons_haveA44PointTarget(_ preview: TodayPreview) throws {
            for appearance in Self.appearances {
                let buttons = try Self.parts(preview).accessibilityElements(appearance)
                    .filter { $0.traits.contains(.button) }
                let expected = try #require(TodayTrees.byState[preview]).count(where: \.isButton)
                #expect(buttons.count == expected)
                for button in buttons {
                    // UIKit's conversion to window coordinates can report 44 pt as 43.999999999999886.
                    #expect(
                        button.frame.width >= 44 - 0.001 && button.frame.height >= 44 - 0.001,
                        "\(button.label) at \(appearance): \(button.frame.size)"
                    )
                }
            }
        }

        /// Review n2: the rest day's two pills change from side by side to stacked by the size class, not by fit.
        /// The tightest case that is still side by side is the largest size below the accessibility ones on the
        /// narrowest phone iOS 26 runs on (375 pt).
        @Test("On a 375 pt phone at xxxLarge the rest day's two pills stand side by side inside the page's insets")
        func restDayPills_narrowPhoneLargestStandardSize_fit() throws {
            let narrow: CGFloat = 375
            let page = TodayParts(preview: .restDay).frame(width: narrow)
            let pills = page.accessibilityElements(SnapshotAppearance(.dark, .xxxLarge)).filter {
                $0.label == "Edit this week" || $0.label == "Train off-schedule"
            }
            let edit = try #require(pills.first).frame
            let train = try #require(pills.last).frame
            #expect(pills.count == 2)
            #expect(abs(edit.midY - train.midY) < 1, "side by side: \(edit) and \(train)")
            #expect(edit.maxX <= train.minX, "they do not overlap: \(edit) and \(train)")
            // The reader hosts the 375 pt page in the middle of its 402 pt window.
            let leading = (SnapshotConfig.phoneWidth - narrow) / 2 + 26
            let trailing = SnapshotConfig.phoneWidth - leading
            #expect(edit.minX >= leading - 0.5 && train.maxX <= trailing + 0.5, "\(edit) \(train)")
        }

        /// What activating every button of `preview`, top to bottom, sends.
        private static func sent(by preview: TodayPreview) throws -> [TodayAction] {
            var sent: [TodayAction] = []
            try parts(preview) { sent.append($0) }.withAccessibilityElements { elements in
                for element in elements where element.accessibilityTraits.contains(.button) {
                    #expect(element.accessibilityActivate(), "\(element.accessibilityLabel ?? "")")
                }
            }
            return sent
        }

        private static let program = Fixtures.programID
        private static let monday = TodayRoute.openWorkout(WorkoutID(Fixtures.uuid(1)))
        private static let wednesday = TodayRoute.openWorkout(WorkoutID(Fixtures.uuid(2)))

        /// The route of "Start workout" for the seed program's day at `index`, in program week `week`.
        private static func start(_ index: Int, week: Int = 0) throws -> TodayRoute {
            let day = try Fixtures.seedProgram().days[index].id
            return .startWorkout(program: program, weekIndex: week, day: day)
        }

        @Test("Up next: the gear, Start workout and a recent row each send the model's route, once")
        func upNext_buttons_sendTheirRoutes() throws {
            #expect(try Self.sent(by: .upNext) == [.route(.settings), .route(Self.start(1)), .route(Self.monday)])
        }

        @Test("A live workout: the button sends the resume route")
        func resume_button_sendsResume() throws {
            #expect(try Self.sent(by: .resume) == [.route(.settings), .route(.resumeWorkout), .route(Self.monday)])
        }

        @Test("Logged: View session opens today's workout")
        func logged_buttons_sendTheirRoutes() throws {
            let today = TodayRoute.openWorkout(WorkoutID(Fixtures.uuid(4)))
            #expect(try Self.sent(by: .logged) == [
                .route(.settings), .route(today), .route(today), .route(Self.monday)
            ])
        }

        @Test("Rest day: Edit this week sends its route, and Train off-schedule asks the screen for the sheet")
        func restDay_buttons_sendTheirActions() throws {
            #expect(try Self.sent(by: .restDay) == [
                .route(.settings),
                .route(.editWeek(program: Self.program, weekIndex: 0)),
                .pickOffScheduleDay,
                .route(Self.wednesday),
                .route(Self.monday)
            ])
        }

        @Test("No program and block complete: the card's button sends the model's route")
        func messageCards_buttons_sendTheirRoutes() throws {
            #expect(try Self.sent(by: .noProgram) == [.route(.settings), .route(.setUpProgram)])
            let last = TodayRoute.openWorkout(WorkoutID(Fixtures.uuid(5)))
            #expect(try Self.sent(by: .blockComplete) == [.route(.settings), .route(.openProgram), .route(last)])
        }

        @Test("The sheet: each day sends the start of that day, a logged one too, and Cancel cancels")
        func offSchedule_buttons_sendTheirRoutes() throws {
            var picked: [TodayRoute] = []
            var cancels = 0
            let sheet = try OffScheduleParts.ofTheRestDay(onPick: { picked.append($0) }, onCancel: { cancels += 1 })
            let escaped = sheet.withAccessibilityElements { elements in
                for element in elements where element.accessibilityTraits.contains(.button) {
                    _ = element.accessibilityActivate()
                }
                return elements.first?.accessibilityPerformEscape() ?? false
            }
            #expect(try picked == [Self.start(0), Self.start(1), Self.start(2), Self.start(3)])
            #expect(cancels == 2, "once by the button, once by VoiceOver's escape gesture")
            #expect(escaped)
        }

        @Test("Loading and failed hold no control: nothing can be sent")
        func loadingAndFailed_sendNothing() throws {
            #expect(try Self.sent(by: .loading).isEmpty)
            #expect(try Self.sent(by: .failed).isEmpty)
        }
    }
#endif
