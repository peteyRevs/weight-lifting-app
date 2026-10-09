#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    import UIKit

    /// The cover's intended VoiceOver trees (F10 S4 criterion 10, S5 criteria 1 and 9), as the implementation
    /// notes write them: for every preview state, the stops in reading order with their labels, values and
    /// traits. A live workout reads its header, then its page.
    enum WorkoutTrees {
        /// One set row as the tree's builder takes it: what VoiceOver says for the row, its state in the
        /// design system's words, and what its check will do.
        struct Row {
            let summary: String
            let state: String
            let check: String

            static func done(_ summary: String, undo check: String) -> Row {
                Row(summary: summary, state: "Done", check: check)
            }

            static func current(_ summary: String, log check: String) -> Row {
                Row(summary: summary, state: "Current set", check: check)
            }

            static func pending(_ summary: String, log check: String) -> Row {
                Row(summary: summary, state: "Pending", check: check)
            }
        }

        /// The weight stepper's step, and the shown row's weight and reps as the steppers speak them.
        struct Steppers {
            let step: String
            let weight: String
            let reps: String

            init(_ step: String, _ weight: String, _ reps: String) {
                self.step = step
                self.weight = weight
                self.reps = reps
            }
        }

        /// What a card's tree is built from.
        struct Card {
            let place: String
            let title: String
            let target: String
            let last: String
            var canRepeat = false
            var unit = "lb"
            let rows: [Row]
            /// The steppers, which follow the row whose state is "Current set".
            let steppers: Steppers
            var remaining: [String] = []
        }

        /// The header's five stops: its row, left to right, then the workout's name and its progress. The
        /// elapsed time is its name alone, with no time for VoiceOver to read stale.
        static func header(progress: String, isEnabled: Bool = true) -> [Stop] {
            let button: UIAccessibilityTraits = isEnabled ? .button : [.button, .notEnabled]
            return [
                Stop("Minimize", button),
                Stop("Elapsed time", []),
                Stop("Finish", button),
                Stop("Upper A — Push focus", [.header, .staticText]),
                Stop("Workout progress", value: progress, [])
            ]
        }

        /// The page's stops: the card from its place to "+ Add set", then "REMAINING" and its rows. Each set
        /// is two stops, the row and its check, as `LedgerDesign.SetRow` reads; the two steppers follow the
        /// shown row, each one adjustable stop named by its step with the row's value.
        ///
        /// While the page is not enabled (a discard runs, or the cover is closing) every stop of it says so,
        /// its texts too: the page is disabled as one, and VoiceOver reads each as dimmed.
        static func page(_ card: Card, isEnabled: Bool = true) -> [Stop] {
            let off: UIAccessibilityTraits = isEnabled ? [] : .notEnabled
            let text = UIAccessibilityTraits.staticText.union(off)
            let heading = text.union(.header)
            let button = UIAccessibilityTraits.button.union(off)
            let adjustable = UIAccessibilityTraits.adjustable.union(off)
            var stops = [
                Stop(card.place, text),
                Stop(card.title, heading),
                Stop("TARGET, \(card.target)", text),
                Stop("Last, \(card.last)", text)
            ]
            if card.canRepeat {
                stops.append(Stop("Repeat", button))
            }
            stops.append(Stop("#, \(card.unit), reps", text))
            for row in card.rows {
                let isDone = row.state == "Done"
                stops.append(Stop(row.summary, value: row.state, button))
                stops.append(Stop(row.check, value: isDone ? "Done" : "", isDone ? button.union(.selected) : button))
                if row.state == "Current set" {
                    stops.append(Stop(card.steppers.step, value: card.steppers.weight, adjustable))
                    stops.append(Stop("1 REP", value: card.steppers.reps, adjustable))
                }
            }
            stops.append(Stop("+ Add set", button))
            if !card.remaining.isEmpty {
                stops.append(Stop("REMAINING", heading))
                stops += card.remaining.map { Stop($0, button) }
            }
            return stops
        }
    }

    /// The trees of the preview states.
    extension WorkoutTrees {
        static let laterThanBench = [
            "Incline DB Press, 3 × 11", "Chest-Supported Row, 4 × 8", "Lat Pulldown, 3 × 13",
            "Cable Lateral Raise, 3 × 16"
        ]

        /// The bench press's card, its five rows in `states` ("Done", "Current set", "Pending").
        static func bench(_ states: [String], last: String, canRepeat: Bool) -> Card {
            Card(
                place: "Exercise 1 of 5",
                title: "Barbell Bench Press",
                target: "5 × 5 @ 200 lb · RPE 8",
                last: last,
                canRepeat: canRepeat,
                rows: states.enumerated().map { index, state in
                    Row(
                        summary: "Set \(index + 1), 200 pounds, 5 reps",
                        state: state,
                        check: "\(state == "Done" ? "Undo" : "Log") set \(index + 1)"
                    )
                },
                steppers: Steppers("5 LB", "200 pounds", "5 reps"),
                remaining: laterThanBench
            )
        }

        static let incline = Card(
            place: "Exercise 2 of 5",
            title: "Incline DB Press",
            target: "3 × 11 @ 52.5 lb · RPE 8",
            last: "No history yet",
            rows: [
                .done("Set 1, 52.5 pounds, 11 reps", undo: "Undo set 1"),
                .current("Set 2, 52.5 pounds, 11 reps", log: "Log set 2"),
                .pending("Set 3, 52.5 pounds, 11 reps", log: "Log set 3")
            ],
            steppers: Steppers("2.5 LB", "52.5 pounds", "11 reps"),
            remaining: Array(laterThanBench.dropFirst())
        )

        static let raise = Card(
            place: "Exercise 5 of 5",
            title: "Cable Lateral Raise",
            target: "3 × 16 @ 15 lb · RPE 9",
            last: "No history yet",
            rows: [
                .done("Set 1, 15 pounds, 16 reps", undo: "Undo set 1"),
                .current("Set 2, 15 pounds, 16 reps", log: "Log set 2"),
                .pending("Set 3, 15 pounds, 16 reps", log: "Log set 3")
            ],
            steppers: Steppers("2.5 LB", "15 pounds", "16 reps")
        )

        static let raiseInKilograms = Card(
            place: "Exercise 5 of 5",
            title: "Cable Lateral Raise",
            target: "3 × 16 @ 10 kg · RPE 9",
            last: "No history yet",
            unit: "kg",
            rows: [
                .done("Set 1, 10 kilograms, 16 reps", undo: "Undo set 1"),
                .current("Set 2, 10 kilograms, 16 reps", log: "Log set 2"),
                .pending("Set 3, 10 kilograms, 16 reps", log: "Log set 3"),
                .pending("Drop set, 8.75 kilograms, 16 reps", log: "Log drop set")
            ],
            steppers: Steppers("1.25 KG", "10 kilograms", "16 reps")
        )

        static let all: [WorkoutPreview: [Stop]] = [
            .started: header(progress: "Exercise 1 of 5") + page(bench(
                ["Current set", "Pending", "Pending", "Pending", "Pending"],
                last: "No history yet",
                canRepeat: false
            )),
            .minutes: header(progress: "Exercise 2 of 5") + page(incline),
            .hour: header(progress: "Exercise 5 of 5") + page(raise),
            .logging: header(progress: "Exercise 1 of 5") + page(bench(
                ["Done", "Done", "Current set", "Pending", "Pending"],
                last: "Sep 9 · 5×5 @ 195 lb",
                canRepeat: true
            )),
            .dropSet: header(progress: "Exercise 5 of 5") + page(raiseInKilograms),
            .discarding: header(progress: "Exercise 2 of 5", isEnabled: false) + page(incline, isEnabled: false),
            .loading: [],
            .failed: [
                Stop("Couldn't open this workout", [.header, .staticText]),
                Stop("Close this screen and try again.", .staticText),
                Stop("Close", .button)
            ]
        ]
    }
#endif
