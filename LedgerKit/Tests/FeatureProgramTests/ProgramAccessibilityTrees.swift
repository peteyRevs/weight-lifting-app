#if os(iOS) && DEBUG
    @testable import FeatureProgram

    /// The intended VoiceOver tree of every state of the builder and of the exercise library sheet, as the
    /// implementation notes write them ("Slice S9", "The VoiceOver trees"). `ProgramAccessibilityTests` reads
    /// each from the state's parts and compares it exactly. Decorative parts (the rules, a row's chevron and
    /// mark, the short names on a day's row) are no stop and appear in no table.
    ///
    /// **The two text fields are in no table.** In a package test process UIKit does not make a text field an
    /// accessibility element, so the hosted reader passes the program's name and the search field in silence.
    /// `ProgramAccessibilityTests` reads the two fields through UIKit instead (their placeholder and their
    /// text), and `fields_areNotReadByTheHostedReader` keeps the limit known. That VoiceOver reads them as
    /// "Program name" and "Search exercises" is for the nightly UI tests of S13 and S14.
    nonisolated enum ProgramTrees {
        static let assignHint = "Double-tap to assign"

        /// The strip's seven stops, Monday first, by what each weekday trains.
        static func strip(_ values: [String]) -> [ViewStop] {
            let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
            return zip(names, values).map { .button($0, value: $1, hint: assignHint) }
        }

        /// One stop per week, the selected one marked: `values` are "4 days" or "Deload".
        static func weeks(_ values: [String], selected: Int) -> [ViewStop] {
            values.enumerated().map { place, value in
                .button("Week \(place + 1)", value: value, selected: place + 1 == selected)
            }
        }

        static let seedWeek = ["Upper A", "Rest", "Lower A", "Rest", "Upper B", "Lower B", "Rest"]
        static let deloadWeek = ["Upper A", "Rest", "Lower A", "Rest", "Upper B", "Rest", "Rest"]
        static let seedWeeks = Array(repeating: "4 days", count: 7) + ["Deload"]

        static let helper = ViewStop.text(
            "Shared by every week. The schedule above decides which day you train, and when."
        )
        static let seedDays: [ViewStop] = [
            .button("Upper A — Push focus", value: "5 exercises · 18 sets · ~39 min"),
            .button("Lower A — Squat focus", value: "4 exercises · 15 sets · ~38 min"),
            .button("Upper B — Pull focus", value: "4 exercises · 15 sets · ~37 min"),
            .button("Lower B — Hinge focus", value: "3 exercises · 10 sets · ~31 min")
        ]

        /// The training days of the seed program, with any day added after them.
        static func days(summary: String = "4 days · 58 sets a week", more: [ViewStop] = []) -> [ViewStop] {
            [.heading("TRAINING DAYS"), .text(summary), helper] + seedDays + more + [.button("+ Add training day")]
        }

        static let builder: [ViewStop] = [
            .heading("MY PROGRAM"),
            .heading("BLOCK · 8 WEEKS"),
            .adjustable("Block length", value: "8 weeks")
        ] + weeks(seedWeeks, selected: 1) + [
            .heading("WEEK 1"),
            .text("Tap to assign")
        ] + strip(seedWeek) + [
            .dimmedButton("First week"),
            .button("Apply to later weeks"),
            .button("Deload")
        ] + days()

        /// The last week: no "Apply to later weeks", and "Deload" is selected.
        static let deloadWeekSelected: [ViewStop] = [
            .heading("MY PROGRAM"),
            .heading("BLOCK · 8 WEEKS"),
            .adjustable("Block length", value: "8 weeks")
        ] + weeks(seedWeeks, selected: 8) + [
            .heading("WEEK 8 · DELOAD"),
            .text("Tap to assign")
        ] + strip(deloadWeek) + [
            .button("Copy week 7"),
            .button("Deload", selected: true)
        ] + days()

        /// The notice stands under the chips; the new day is on Tuesday and is the fifth row.
        static let emptyDay: [ViewStop] = [
            .heading("MY PROGRAM"),
            .heading("BLOCK · 8 WEEKS"),
            .adjustable("Block length", value: "8 weeks")
        ] + weeks(["5 days"] + seedWeeks.dropFirst(), selected: 1) + [
            .text("Add at least one exercise before scheduling this day."),
            .heading("WEEK 1"),
            .text("Tap to assign")
        ] + strip(["Upper A", "New day", "Lower A", "Rest", "Upper B", "Lower B", "Rest"]) + [
            .dimmedButton("First week"),
            .button("Apply to later weeks"),
            .button("Deload")
        ] + days(summary: "5 days · 58 sets a week", more: [.button("New day", value: "No exercises yet")])

        static let twoWeeks: [ViewStop] = [
            .heading("MY PROGRAM"),
            .heading("BLOCK · 2 WEEKS"),
            .adjustable("Block length", value: "2 weeks")
        ] + weeks(["4 days", "4 days"], selected: 1) + [
            .text("A block needs at least 2 weeks."),
            .heading("WEEK 1"),
            .text("Tap to assign")
        ] + strip(seedWeek) + [
            .dimmedButton("First week"),
            .button("Apply to later weeks"),
            .button("Deload")
        ] + days()

        /// Weeks 9 to 16 were added after the deload week and took its three days.
        static let sixteenWeeks: [ViewStop] = [
            .heading("MY PROGRAM"),
            .heading("BLOCK · 16 WEEKS"),
            .adjustable("Block length", value: "16 weeks")
        ] + weeks(seedWeeks + Array(repeating: "3 days", count: 8), selected: 12) + [
            .heading("WEEK 12"),
            .text("Tap to assign")
        ] + strip(deloadWeek) + [
            .button("Copy week 11"),
            .button("Apply to later weeks"),
            .button("Deload")
        ] + days()
    }

    // MARK: - The exercise library

    nonisolated extension ProgramTrees {
        /// The sheet's title and "Cancel", then the page's two rows of chips with Back and Cable chosen.
        static let libraryTop: [ViewStop] = [
            .heading("Exercise library"),
            .button("Cancel"),
            .button("Muscle: All"),
            .button("Muscle: Chest"),
            .button("Muscle: Back", selected: true),
            .button("Muscle: Shoulders"),
            .button("Muscle: Legs"),
            .button("Muscle: Arms"),
            .button("Equipment: All"),
            .button("Equipment: Barbell"),
            .button("Equipment: Dumbbell"),
            .button("Equipment: Cable", selected: true),
            .button("Equipment: Machine"),
            .button("Equipment: Bodyweight")
        ]

        /// The eight cable exercises for the back, in the list's order; `picked` are the places of the picked.
        static func rows(picked: Set<Int> = []) -> [ViewStop] {
            [
                ("Cable Shrug", "Cable · Back"),
                ("Lat Pulldown", "Cable · Back · already in this day"),
                ("Neutral-Grip Pulldown", "Cable · Back"),
                ("Reverse-Grip Lat Pulldown", "Cable · Back"),
                ("Seated Cable Row", "Cable · Back"),
                ("Single-Arm Cable Row", "Cable · Back"),
                ("Single-Arm Lat Pulldown", "Cable · Back"),
                ("Straight-Arm Pulldown", "Cable · Back")
            ]
            .enumerated().map { place, row in .button(row.0, value: row.1, selected: picked.contains(place)) }
        }

        static let library = libraryTop + rows() + [.dimmedButton("Select exercises to add")]
        static let libraryPicked = libraryTop + rows(picked: [0, 1, 3]) + [.button("Add 3 exercises")]
        static let libraryNothing = libraryTop + [
            .text("Nothing matches that filter."),
            .button("Clear filters"),
            .dimmedButton("Select exercises to add")
        ]

        /// The tree of each state of the preview registry; the Day editor's are `DayEditorTrees`'.
        static let byState: [ProgramPreview: [ViewStop]] = [
            .builder: builder, .deloadWeek: deloadWeekSelected, .emptyDay: emptyDay, .twoWeeks: twoWeeks,
            .sixteenWeeks: sixteenWeeks, .library: library, .libraryPicked: libraryPicked,
            .libraryNothing: libraryNothing
        ].merging(DayEditorTrees.byState) { builder, _ in builder }
    }
#endif
