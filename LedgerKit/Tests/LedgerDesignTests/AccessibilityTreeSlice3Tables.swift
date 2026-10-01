#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import UIKit

    /// `AccessibilityTreeTests`' tables for slice 3: every component in every state it offers, and the
    /// tree VoiceOver must find in it. The watch components are read on iOS: the tree comes from the
    /// same SwiftUI accessibility modifiers on both platforms, and only iOS hands it to a test (UIKit).
    extension TreeTables {
        nonisolated static let slice3: [TreeCase] = weekStrips + statTiles + progress + sheets + watch

        nonisolated static let weekStrips: [TreeCase] = [
            TreeCase("WeekStrip, the prototype's week", week) { WeekStripGallery() },
            TreeCase("WeekStrip at accessibility3", at: SnapshotAppearance(.dark, .accessibility3), week) {
                WeekStripGallery()
            },
            TreeCase(
                "WeekStrip, one day of each mark",
                [
                    day("Monday, August 17", "Done"), day("Tuesday, August 18", "Today"),
                    day("Wednesday, August 19", "Planned"), day("Thursday, August 20", "Rest day")
                ]
            ) {
                WeekStrip(days: [
                    WeekStrip.Day(weekday: "M", date: "17", mark: .done, accessibilitySummary: "Monday, August 17"),
                    WeekStrip.Day(weekday: "T", date: "18", mark: .today, accessibilitySummary: "Tuesday, August 18"),
                    WeekStrip.Day(
                        weekday: "W", date: "19", mark: .planned, accessibilitySummary: "Wednesday, August 19"
                    ),
                    WeekStrip.Day(weekday: "T", date: "20", mark: .rest, accessibilitySummary: "Thursday, August 20")
                ])
            },
            TreeCase("WeekStrip, no days", []) { WeekStrip(days: []) }
        ]

        nonisolated static let statTiles: [TreeCase] = [
            TreeCase("StatTile, value and caption", [.text("218, 1RM est")]) {
                StatTile(value: "218", caption: "1RM est")
            },
            TreeCase("StatTile with a unit", [.text("3/4, sessions this week")]) {
                StatTile(value: "3", unit: "/4", caption: "sessions this week")
            },
            TreeCase("StatTile with a unit and a delta", [.text("41.2k, lb moved, +8%")]) {
                StatTile(value: "41.2", unit: "k", caption: "lb moved", delta: "+8%")
            },
            TreeCase("StatTile named by the feature", [.text("3 of 4 sessions this week")]) {
                StatTile(
                    value: "3", unit: "/4", caption: "sessions this week",
                    accessibilitySummary: "3 of 4 sessions this week"
                )
            },
            TreeCase("StatTile gallery, in order", tiles) { StatTileGallery() },
            TreeCase(
                "StatTileRow at accessibility3 (stacked), in order",
                at: SnapshotAppearance(.dark, .accessibility3),
                tiles
            ) {
                StatTileGallery()
            }
        ]

        nonisolated static let progress: [TreeCase] = [
            TreeCase(
                "ProgressSegments gallery: start, middle, end",
                [
                    TreeNode("Workout progress", value: "Exercise 1 of 5", []),
                    TreeNode("Workout progress", value: "Exercise 3 of 5", []),
                    TreeNode("Workout progress", value: "Exercise 5 of 5", [])
                ]
            ) { ProgressSegmentsGallery() },
            TreeCase("ProgressSegments, no segments", [TreeNode("Workout progress", value: "Not started", [])]) {
                ProgressSegments([], label: "Workout progress", value: "Not started")
            }
        ]

        nonisolated static let sheets: [TreeCase] = [
            TreeCase("SheetChrome", sheet) {
                SheetChrome("Swap exercise", cancel: "Cancel") {} content: { Text(verbatim: "Content") }
            },
            TreeCase(
                "SheetChrome at accessibility3 (cancel under the title)",
                at: SnapshotAppearance(.dark, .accessibility3),
                sheet
            ) {
                SheetChrome("Swap exercise", cancel: "Cancel") {} content: { Text(verbatim: "Content") }
            },
            TreeCase("SheetChrome, pressed", sheet) {
                SheetChrome("Swap exercise", cancel: "Cancel") {} content: { Text(verbatim: "Content") }
                    .environment(\.ledgerDrawsPressed, true)
            },
            TreeCase(
                "SheetChrome gallery, in order",
                [
                    TreeNode.text("Swap exercise", .header).escaping, TreeNode.button("Cancel").escaping,
                    TreeNode.text("Same movement pattern, equipment you have.").escaping,
                    TreeNode.button("Dumbbell Bench Press, Similar pattern · 2 × 70 lb, Use").escaping,
                    TreeNode.button("Smith Machine Press, Machine · bench occupied?, Use").escaping
                ]
            ) { SheetChromeGallery() },
            TreeCase(
                "EmptyState without an action",
                [.text("No session today", .header), .text("Nothing scheduled.")]
            ) { EmptyState("No session today", body: "Nothing scheduled.") },
            TreeCase(
                "EmptyState with an action",
                [
                    .text("Nothing matches that filter", .header), .text("Try another muscle."),
                    .button("Clear filters")
                ]
            ) {
                EmptyState("Nothing matches that filter", body: "Try another muscle.", actionTitle: "Clear filters") {}
            },
            TreeCase(
                "EmptyState with an action, pressed",
                [.text("Nothing matches that filter", .header), .text("Try another muscle."), .button("Clear filters")]
            ) {
                EmptyState("Nothing matches that filter", body: "Try another muscle.", actionTitle: "Clear filters") {}
                    .environment(\.ledgerDrawsPressed, true)
            }
        ]

        nonisolated static let watch: [TreeCase] = [
            TreeCase(
                "WatchPrimaryButton gallery: normal, pressed, long, disabled",
                [
                    .button("Start"), .button("Done set"), .button("Save workout and finish"),
                    .button("Skip", .notEnabled)
                ]
            ) { WatchPrimaryButtonGallery() },
            TreeCase(
                "WatchRestRing gallery: full, half, empty",
                [
                    .text("2 minutes 30 seconds left", .updatesFrequently),
                    .text("1 minute 15 seconds left", .updatesFrequently),
                    .text("Rest over", .updatesFrequently)
                ]
            ) { WatchRestRingGallery() },
            TreeCase("WatchRestRing named by the feature", [.text("1 minute 15 seconds left", .updatesFrequently)]) {
                WatchRestRing(progress: 0.5, label: "1:15", accessibilitySummary: "1 minute 15 seconds left")
            },
            TreeCase(
                "WatchStatBlock gallery, in order",
                [.text("12/15, Sets"), .text("24,180, Lb moved"), .text("142, Avg BPM"), .text("2, New PR")]
            ) { WatchStatBlockGallery() },
            TreeCase("WatchStatBlock named by the feature", [.text("12 of 15 sets")]) {
                WatchStatBlock("12/15", caption: "Sets", accessibilitySummary: "12 of 15 sets")
            }
        ]

        /// `WeekStripGallery`: one element per day, Monday to Sunday.
        nonisolated static let week: [TreeNode] = [
            day("Monday, August 17", "Done"), day("Tuesday, August 18", "Done"),
            day("Wednesday, August 19", "Today"), day("Thursday, August 20", "Rest day"),
            day("Friday, August 21", "Planned"), day("Saturday, August 22", "Rest day"),
            day("Sunday, August 23", "Rest day")
        ]

        /// `StatTileGallery`: Today's two tiles, then Exercise history's three.
        nonisolated static let tiles: [TreeNode] = [
            .text("3/4, sessions this week"), .text("41.2k, lb moved, +8%"), .text("218, 1RM est"),
            .text("195×5, best set"), .text("34, sessions")
        ]

        /// A sheet with one line of content: its title as a heading, the cancel button, the content.
        /// Every stop hands VoiceOver's escape to `onCancel` (S3-4).
        nonisolated static let sheet: [TreeNode] = [
            TreeNode.text("Swap exercise", .header).escaping, TreeNode.button("Cancel").escaping,
            TreeNode.text("Content").escaping
        ]

        nonisolated static func day(_ label: String, _ mark: String) -> TreeNode {
            TreeNode(label, value: mark, .staticText)
        }
    }
#endif
