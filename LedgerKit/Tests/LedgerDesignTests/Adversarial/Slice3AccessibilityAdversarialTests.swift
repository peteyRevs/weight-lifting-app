#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// Weeks as F09 would pass them, and what VoiceOver must say for each day. Built from the brief and
    /// F09's accessibility line ("Wednesday 16, today"), not from the component.
    enum Slice3Weeks {
        static func day(_ weekday: String, _ date: String, _ mark: WeekStrip.Mark, _ summary: String) -> WeekStrip.Day {
            WeekStrip.Day(weekday: weekday, date: date, mark: mark, accessibilitySummary: summary)
        }

        /// Monday 29 December 2025 to Sunday 4 January 2026: across a month and a year, today the 31st.
        static let yearBoundary: [WeekStrip.Day] = [
            day("M", "29", .done, "Monday, December 29, 2025"), day("T", "30", .done, "Tuesday, December 30, 2025"),
            day("W", "31", .today, "Wednesday, December 31, 2025"), day("T", "1", .rest, "Thursday, January 1, 2026"),
            day("F", "2", .planned, "Friday, January 2, 2026"), day("S", "3", .rest, "Saturday, January 3, 2026"),
            day("S", "4", .planned, "Sunday, January 4, 2026")
        ]

        /// A Sunday-first week (en-US) across a month: Sunday 30 August to Saturday 5 September.
        static let sundayFirst: [WeekStrip.Day] = [
            day("Sun", "30", .rest, "Sunday, August 30"), day("Mon", "31", .done, "Monday, August 31"),
            day("Tue", "1", .rest, "Tuesday, September 1"), day("Wed", "2", .today, "Wednesday, September 2"),
            day("Thu", "3", .rest, "Thursday, September 3"), day("Fri", "4", .planned, "Friday, September 4"),
            day("Sat", "5", .planned, "Saturday, September 5")
        ]

        /// The mark in words, as the brief's WeekStrip doc and F09 speak it.
        static func spoken(_ mark: WeekStrip.Mark) -> String {
            switch mark {
            case .rest: "Rest day"
            case .planned: "Planned"
            case .today: "Today"
            case .done: "Done"
            }
        }

        static func expected(_ days: [WeekStrip.Day]) -> [TreeNode] {
            days.map { TreeNode($0.accessibilitySummary, value: spoken($0.mark), .staticText) }
        }
    }

    extension RenderingSuites {
        /// F06 slice 3, adversarial round 1: VoiceOver and hit targets beyond the tree tables' two text
        /// sizes, weeks the gallery does not show, right-to-left, the progress bar's edge states and the
        /// sheet's escape gesture.
        @Suite("Slice 3 accessibility (adversarial, slice 3 round 1)", .tags(.design))
        struct Slice3AccessibilityAdversarialTests {
            nonisolated static let sizes: [SnapshotAppearance] = [
                SnapshotAppearance(.light, .xSmall), SnapshotAppearance(.dark, .xxxLarge),
                SnapshotAppearance(.light, .accessibility1), SnapshotAppearance(.dark, .accessibility5)
            ]

            /// The tree as `AccessibilityTreeTests` reads it: label, value, traits and containers.
            static func tree(_ view: some View, _ appearance: SnapshotAppearance) -> [TreeNode] {
                view.withAccessibilityElements(appearance) { elements in
                    elements.map { element in
                        TreeNode(
                            element.accessibilityLabel ?? "",
                            value: element.accessibilityValue ?? "",
                            element.accessibilityTraits,
                            containers: AccessibilityTreeTests.containers(above: element)
                        )
                    }
                }
            }

            @Test("A week across a month and a year reads every day by its full date, in order", arguments: sizes)
            func weekStrip_yearBoundary_readsEveryDayInOrder(_ appearance: SnapshotAppearance) {
                let found = Self.tree(WeekStrip(days: Slice3Weeks.yearBoundary), appearance)
                #expect(found == Slice3Weeks.expected(Slice3Weeks.yearBoundary), "\(appearance): \(found)")
            }

            @Test("A Sunday-first week keeps the caller's order, on screen and for VoiceOver", arguments: sizes)
            func weekStrip_sundayFirst_keepsTheCallersOrder(_ appearance: SnapshotAppearance) {
                let view = WeekStrip(days: Slice3Weeks.sundayFirst)
                #expect(Self.tree(view, appearance) == Slice3Weeks.expected(Slice3Weeks.sundayFirst))
                let frames = view.accessibilityElements(appearance).map(\.frame)
                #expect(frames.count == 7)
                #expect(zip(frames, frames.dropFirst()).allSatisfy { $0.maxX <= $1.minX + 0.001 }, "\(frames)")
                #expect(frames.allSatisfy { $0.minX >= 0 && $0.maxX <= SnapshotConfig.phoneWidth }, "\(frames)")
            }

            @Test("Right to left, the week runs from the right and VoiceOver still starts at its first day")
            func weekStrip_rightToLeft_mirrorsTheWeek() {
                let days = Slice3Weeks.yearBoundary
                let view = WeekStrip(days: days).environment(\.layoutDirection, .rightToLeft)
                let elements = view.accessibilityElements()
                #expect(elements.map(\.label) == days.map(\.accessibilitySummary))
                let midpoints = elements.map(\.frame.midX)
                #expect(zip(midpoints, midpoints.dropFirst()).allSatisfy { $0 > $1 }, "RTL midpoints \(midpoints)")
            }

            /// Each state's words (VoiceOver's value) and its segments.
            static let progress: [(value: String, segments: [ProgressSegment])] = [
                ("Not started", [5, 3, 4].map { ProgressSegment(length: $0, state: .upcoming) }),
                ("Exercise 1 of 1", [ProgressSegment(length: 5, state: .current)]),
                ("Finished", [5, 3, 4].map { ProgressSegment(length: $0, state: .done) }),
                ("No exercises", [])
            ]

            @Test("ProgressSegments is one element in every state, full width, saying the caller's words")
            func progressSegments_edgeStates_areOneElement() {
                for state in Self.progress {
                    let view = ProgressSegments(state.segments, label: "Workout progress", value: state.value)
                    let found = Self.tree(view, SnapshotAppearance(.light, .large))
                    #expect(found == [TreeNode("Workout progress", value: state.value, [])], "\(found)")
                    let frame = view.accessibilityElements().first?.frame ?? .zero
                    #expect(abs(frame.width - SnapshotConfig.phoneWidth) < 0.001, "\(state.value): \(frame)")
                }
            }

            @Test(
                "SheetChrome's cancel and EmptyState's action are 44 pt buttons on screen at every size",
                arguments: sizes
            )
            func dismissAndAction_everySize_areTargetsOnScreen(_ appearance: SnapshotAppearance) {
                let sheet = SheetChrome("Replace Barbell Bench Press", cancel: "Cancel") {} content: {
                    Text(verbatim: "Same movement pattern, equipment you have.")
                }
                let empty = EmptyState(
                    "Nothing matches that filter",
                    body: "Try another muscle.",
                    actionTitle: "Clear"
                ) {}
                for (label, view) in [("Cancel", AnyView(sheet)), ("Clear", AnyView(empty))] {
                    let buttons = view.accessibilityElements(appearance).filter { $0.traits.contains(.button) }
                    #expect(buttons.map(\.label) == [label], "\(appearance): \(buttons)")
                    for button in buttons {
                        expectButton(button)
                        #expect(button.frame.maxX <= SnapshotConfig.phoneWidth + 0.001, "\(appearance): \(button)")
                    }
                }
            }

            @Test("WatchPrimaryButton is a full-width target at least 44 pt tall at every text size and watch width")
            func watchPrimaryButton_everyWidthAndSize_meetsTheWatchDefault() {
                for width in [162, 176, 187, 205, 208, 211] as [CGFloat] {
                    for appearance in Self.sizes {
                        let button = WatchPrimaryButton("Go") {}.frame(width: width)
                        let elements = button.accessibilityElements(appearance)
                        let frame = elements.first?.frame ?? .zero
                        #expect(elements.count == 1 && elements[0].traits.contains(.button), "\(elements)")
                        #expect(frame.height >= 44 - 0.001, "\(width) pt, \(appearance): \(frame)")
                        #expect(abs(frame.width - width) < 0.001, "\(width) pt, \(appearance): \(frame)")
                    }
                }
            }

            @Test("StatTileRow reads its tiles in order at every size, side by side or stacked", arguments: sizes)
            func statTileRow_everySize_readsInOrder(_ appearance: SnapshotAppearance) {
                #expect(Self.tree(StatTileGallery(), appearance) == TreeTables.tiles)
            }
        }

        /// SheetChrome as a presented sheet: its title in a sheet-sized container, and VoiceOver's escape.
        @Suite("Slice 3 sheet accessibility (adversarial, slice 3 round 1)", .tags(.design))
        struct Slice3SheetAccessibilityAdversarialTests {
            /// A sheet is laid out in the sheet's height, not at its ideal height as the snapshot harness
            /// lays it out (`snapshotAppearance`'s `fixedSize`). Read in a UIKit host, the title's frame must
            /// be as tall as the same title alone at the same width: every line it needs, however short the
            /// content under it.
            @Test(
                "In a sheet-sized container SheetChrome's title gets every line it needs, at every accessibility size",
                arguments: [
                    DynamicTypeSize.accessibility1,
                    .accessibility2,
                    .accessibility3,
                    .accessibility4,
                    .accessibility5
                ]
            )
            func sheetChrome_sheetSizedContainer_titleGetsEveryLine(_ size: DynamicTypeSize) {
                let appearance = SnapshotAppearance(.dark, size)
                for title in ["Replace Barbell Bench Press", "Replace Single-Arm Dumbbell Romanian Deadlift"] {
                    let sheet = SheetChrome(title, cancel: "Cancel") {} content: {
                        Text(verbatim: "Same movement pattern, equipment you have.")
                    }
                    .padding(LedgerSpacing.screen)
                    .frame(height: 874, alignment: .top) // iPhone 17's screen height
                    let alone = Text(title).ledgerFont(.subheading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(LedgerSpacing.screen + LedgerSpacing.xl) // the page's and the sheet's insets
                    let inSheet = sheet.accessibilityElements(appearance).first { $0.label == title }?.frame ?? .zero
                    let needed = alone.accessibilityElements(appearance).first?.frame ?? .zero
                    #expect(
                        abs(inSheet.height - needed.height) < 0.5,
                        "\(title), \(size): \(inSheet.size) in the sheet, \(needed.size) alone"
                    )
                }
            }

            /// VoiceOver's two-finger scrub ("escape") dismisses a modal view (HIG, VoiceOver). UIKit offers
            /// it to the focused element, then up its accessibility containers and views, until one handles it.
            @Test("VoiceOver's escape gesture on a sheet does what its cancel does")
            func sheetChrome_escapeGesture_callsOnCancel() {
                var cancels = 0
                let sheet = SheetChrome("Swap exercise", cancel: "Cancel") { cancels += 1 } content: {
                    Text(verbatim: "Content")
                }
                let handled = sheet.withAccessibilityElements { elements in
                    elements.last.map(Self.performEscape) ?? false
                }
                #expect(handled, "no element, container or view handled escape")
                #expect(cancels == 1)
            }

            @Test("The escape probe finds an escape action set above the element (positive control)")
            func escapeProbe_actionAbove_isFound() {
                var escapes = 0
                let view = VStack { Text(verbatim: "Content") }.accessibilityAction(.escape) { escapes += 1 }
                let handled = view.withAccessibilityElements { elements in
                    elements.last.map(Self.performEscape) ?? false
                }
                #expect(handled && escapes == 1)
            }

            /// UIKit's escape routing: the element, then each accessibility container above it, then the
            /// views from the hosting view up.
            static func performEscape(_ element: NSObject) -> Bool {
                var candidate: NSObject? = element
                while let current = candidate {
                    if current.accessibilityPerformEscape() {
                        return true
                    }
                    candidate = AccessibilityTreeTests.container(of: current) ?? (current as? UIView)?.superview
                }
                return false
            }
        }
    }
#endif
