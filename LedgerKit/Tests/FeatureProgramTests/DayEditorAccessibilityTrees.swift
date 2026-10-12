#if os(iOS) && DEBUG
    @testable import FeatureProgram

    /// The intended VoiceOver tree of every state of the Day editor, as the implementation notes write it
    /// ("S10 — the Day editor's views", "The VoiceOver tree"). `ProgramAccessibilityTests` reads each from the
    /// state's parts, the pinned bar over the page, and compares it exactly. Decorative parts (the rules,
    /// a row's caret, the day's tag) are no stop and appear in no table.
    ///
    /// **The day's name is in no table**, as the program's is in none: the hosted reader passes a text field
    /// in silence. `DayEditorTextFieldTests` reads it through UIKit and keeps the limit known.
    nonisolated enum DayEditorTrees {
        /// The pinned bar, "Program" and "Done", and the page's header without its field: the day's place
        /// and the summary line.
        static func header(_ position: String, meta: String) -> [ViewStop] {
            [.button("Program"), .button("Done"), .heading(position), .text(meta)]
        }

        static let superset = ViewStop.heading("Superset", value: "2 exercises back to back · rest after B")
        static let foot: [ViewStop] = [.button("+ Add exercise from library"), .button("Delete day")]

        /// The steppers of a slot, "Sets" first: each one adjustable element.
        static func steppers(_ fields: [(String, String)]) -> [ViewStop] {
            fields.map { .adjustable($0.0, value: $0.1) }
        }

        /// "PROGRESSION", its three chips with the chosen one read as selected and no button, and the note.
        static func progression(chosen: String, note: String) -> [ViewStop] {
            [.heading("PROGRESSION")] + ["Linear", "Double", "Fixed"].map {
                $0 == chosen ? .chosen($0) : .button($0)
            } + [.text(note)]
        }

        static let dropSetOff = ViewStop.toggle(
            "Drop set", isOn: false, hint: "One extra set at −15% after the last working set."
        )
        static let dropSetOn = ViewStop.toggle(
            "Drop set", isOn: true, hint: "One extra set at −15%, straight after the last working set."
        )

        // MARK: Upper A, week 1

        static let upperAHeader = header("DAY 1 OF 4", meta: "Week 1 · 5 exercises · 18 sets · ~39 min")
        static let bench = ("1, Barbell Bench Press", "5×5 · 180 lb · Barbell · +5/wk · RPE 8 · 2:30 rest")
        static let incline = ("2, Incline DB Press", "3×10 · 50 lb · Dumbbell · Reps 10–12 · RPE 8 · 1:30 rest")
        static let upperARest: [ViewStop] = [
            .row("3, Chest-Supported Row", value: "4×8 · 65 lb · Machine · +2.5/wk · RPE 8 · 1:30 rest"),
            superset,
            .row("4A, Lat Pulldown", value: "3×12 · 100 lb · Cable · Reps 12–14 · RPE 9 · no rest"),
            .row("4B, Cable Lateral Raise", value: "3×15 · 12.5 lb · Cable · Reps 15–17 · RPE 9 · 1:15 rest")
        ]

        static let closed: [ViewStop] = upperAHeader
            + [.row(bench.0, value: bench.1), .row(incline.0, value: incline.1)] + upperARest + foot

        /// The bench press open: the first of the day has no "Move up".
        static let openLinear: [ViewStop] = upperAHeader + [
            .row(bench.0, value: bench.1, isOpen: true),
            .text("WEEK 1", value: "5 × 5 @ 180 lb · RPE 8")
        ] + steppers([
            ("Sets", "5"), ("Reps", "5"), ("Start load", "180 lb"), ("Target RPE", "8"), ("Rest", "2:30")
        ]) + progression(
            chosen: "Linear", note: "Adds 5 lb a week from 180 lb. A week with a missed set holds the load."
        ) + [
            dropSetOff, .button("Superset with next"), .button("Move down"), .button("Remove"),
            .text("W1 180 · W2 185 · W3 190 · W4 195 · W5 200 · W6 205 · W7 210 · W8 185 (deload)"),
            .row(incline.0, value: incline.1)
        ] + upperARest + foot

        /// Incline DB Press open: a double progression has "Rep floor" and "Top of range".
        static let openDouble: [ViewStop] = upperAHeader + [
            .row(bench.0, value: bench.1),
            .row(incline.0, value: incline.1, isOpen: true),
            .text("WEEK 1", value: "3 × 10 @ 50 lb · RPE 8")
        ] + steppers([
            ("Sets", "3"), ("Rep floor", "10"), ("Top of range", "12"), ("Start load", "50 lb"), ("Target RPE", "8"),
            ("Rest", "1:30")
        ]) + progression(chosen: "Double", note: "Adds a rep each week up to 12, then +2.5 lb back at 10.") + [
            dropSetOff, .button("Superset with next"), .button("Move up"), .button("Move down"), .button("Remove"),
            .text("W1 50 · W2 50 · W3 50 · W4 52.5 · W5 52.5 · W6 52.5 · W7 55 · W8 47.5 (deload)")
        ] + upperARest + foot

        /// Week 8: the rows and the week line read the deload week's numbers; the steppers the slot's own.
        static let deload: [ViewStop] = header("DAY 1 OF 4", meta: "Week 8 · 5 exercises · 13 sets · ~29 min") + [
            .row(bench.0, value: "4×5 · 185 lb · Barbell · +5/wk · RPE 6 · 2:30 rest", isOpen: true),
            .text("WEEK 8 · DELOAD", value: "4 × 5 @ 185 lb · RPE 6")
        ] + steppers([
            ("Sets", "5"), ("Reps", "5"), ("Start load", "180 lb"), ("Target RPE", "8"), ("Rest", "2:30")
        ]) + progression(
            chosen: "Linear", note: "Adds 5 lb a week from 180 lb. A week with a missed set holds the load."
        ) + [
            dropSetOff, .button("Superset with next"), .button("Move down"), .button("Remove"),
            .text("W1 180 · W2 185 · W3 190 · W4 195 · W5 200 · W6 205 · W7 210 · W8 185 (deload)"),
            .row(incline.0, value: "2×11 · 47.5 lb · Dumbbell · Reps 10–12 · RPE 6 · 1:30 rest"),
            .row("3, Chest-Supported Row", value: "3×8 · 70 lb · Machine · +2.5/wk · RPE 6 · 1:30 rest"),
            superset,
            .row("4A, Lat Pulldown", value: "2×13 · 90 lb · Cable · Reps 12–14 · RPE 7 · no rest"),
            .row("4B, Cable Lateral Raise", value: "2×16 · 15 lb · Cable · Reps 15–17 · RPE 7 · 1:15 rest")
        ] + foot

        static let longNames: [ViewStop] = upperAHeader + [
            .row(
                "1, \(ProgramPreviewData.longExerciseName)",
                value: "5×5 · 180 lb · Barbell · +5/wk · RPE 8 · 2:30 rest"
            ),
            .row(incline.0, value: incline.1),
            .row("3, Chest-Supported Row", value: "4×8 · 65 lb · Machine · +2.5/wk · RPE 8 · 1:30 rest"),
            superset,
            .row(
                "4A, \(ProgramPreviewData.longExerciseName)",
                value: "3×12 · 100 lb · Cable · Reps 12–14 · RPE 9 · no rest"
            ),
            .row("4B, Cable Lateral Raise", value: "3×15 · 12.5 lb · Cable · Reps 15–17 · RPE 9 · 1:15 rest")
        ] + foot
    }

    // MARK: - Lower A and Upper B

    nonisolated extension DayEditorTrees {
        /// Lower A with the second exercise of its superset open: "Break out", and the last has no "Move down".
        static let supersetOpen: [ViewStop] = header(
            "DAY 2 OF 4", meta: "Week 1 · 4 exercises · 15 sets · ~38 min"
        ) + [
            .row("1, Back Squat", value: "5×5 · 250 lb · Barbell · +5/wk · RPE 8 · 3 min rest"),
            .row("2, Romanian Deadlift", value: "3×8 · 205 lb · Barbell · +5/wk · RPE 8 · 2 min rest"),
            superset,
            .row("3A, Leg Press", value: "3×12 · 320 lb · Machine · Reps 12–14 · RPE 9 · no rest"),
            .row(
                "3B, Standing Calf Raise", value: "4×12 · 160 lb · Machine · Fixed · RPE 9 · 1:30 rest", isOpen: true
            ),
            .text("WEEK 1", value: "4 × 12 @ 160 lb · RPE 9")
        ] + steppers([
            ("Sets", "4"), ("Reps", "12"), ("Start load", "160 lb"), ("Target RPE", "9"), ("Rest", "1 min")
        ]) + progression(chosen: "Fixed", note: "Stays at 160 lb for the whole block.") + [
            dropSetOff, .button("Break out"), .button("Move up"), .button("Remove"),
            .text("W1 160 · W2 160 · W3 160 · W4 160 · W5 160 · W6 160 · W7 160 · W8 135 (deload)")
        ] + foot

        /// Upper B's curl, the last exercise and on its own: no superset action, no "Move down".
        static let dropSet: [ViewStop] = header("DAY 3 OF 4", meta: "Week 1 · 4 exercises · 15 sets · ~37 min") + [
            .row("1, Weighted Pull-Up", value: "4×6 · 35 lb · Bodyweight · +2.5/wk · RPE 8 · 2:30 rest"),
            .row("2, Overhead Press", value: "4×6 · 115 lb · Barbell · +5/wk · RPE 8 · 2 min rest"),
            .row("3, Barbell Row", value: "3×10 · 155 lb · Barbell · +5/wk · RPE 8 · 1:30 rest"),
            .row(
                "4, Barbell Curl", value: "3×12 · 75 lb · Barbell · Reps 12–14 · drop · RPE 9 · 1 min rest",
                isOpen: true
            ),
            .text("WEEK 1", value: "3 × 12 @ 75 lb · RPE 9")
        ] + steppers([
            ("Sets", "3"), ("Rep floor", "12"), ("Top of range", "14"), ("Start load", "75 lb"), ("Target RPE", "9"),
            ("Rest", "1 min")
        ]) + progression(chosen: "Double", note: "Adds a rep each week up to 14, then +5 lb back at 12.") + [
            dropSetOn, .button("Move up"), .button("Remove"),
            .text("W1 75 · W2 75 · W3 75 · W4 80 · W5 80 · W6 80 · W7 85 · W8 70 (deload)")
        ] + foot

        /// The tree of each Day editor state of the preview registry.
        static let byState: [ProgramPreview: [ViewStop]] = [
            .dayEditor: closed, .daySuperset: supersetOpen, .dayOpenLinear: openLinear, .dayOpenDouble: openDouble,
            .dayDropSet: dropSet, .dayDeload: deload, .dayLongNames: longNames
        ]
    }
#endif
