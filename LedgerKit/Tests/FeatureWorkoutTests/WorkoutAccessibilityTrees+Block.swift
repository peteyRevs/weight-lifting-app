#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    import UIKit

    /// F10 S9 criterion 20: a superset's block. The eyebrow, the round (a heading), each legend row as one
    /// button (selected for the current member) followed by its swap button when shown, the rest line with
    /// its time in words, "Last" and "Repeat", the rows with their checks and the steppers after the shown
    /// row, "+ Add set", then "REMAINING".
    extension WorkoutTrees {
        /// One legend row: what VoiceOver reads for it, whether it is the current member's, and its swap
        /// button's name when it has one.
        struct Legend {
            let spoken: String
            var isCurrent = false
            var swap: String?
        }

        struct Block {
            let place: String
            let round: String
            let legend: [Legend]
            let rest: String
            let last: String
            var canRepeat = false
            var unit = "lb"
            let rows: [Row]
            let steppers: Steppers
            var remaining: [String] = []
        }

        static func page(_ block: Block) -> [Stop] {
            var stops = [Stop(block.place, .staticText), Stop(block.round, [.header, .staticText])]
            for row in block.legend {
                stops.append(Stop(row.spoken, row.isCurrent ? [.button, .selected] : .button))
                if let swap = row.swap {
                    stops.append(Stop(swap, .button))
                }
            }
            stops += [Stop(block.rest, .staticText), Stop("Last, \(block.last)", .staticText)]
            if block.canRepeat {
                stops.append(Stop("Repeat", .button))
            }
            stops.append(Stop("#, \(block.unit), reps", .staticText))
            for row in block.rows {
                let isDone = row.state == "Done"
                stops.append(Stop(row.summary, value: row.state, .button))
                stops.append(Stop(row.check, value: isDone ? "Done" : "", isDone ? [.button, .selected] : .button))
                if row.state == "Current set" {
                    stops.append(Stop(block.steppers.step, value: block.steppers.weight, .adjustable))
                    stops.append(Stop("1 REP", value: block.steppers.reps, .adjustable))
                }
            }
            stops.append(Stop("+ Add set", .button))
            if !block.remaining.isEmpty {
                stops.append(Stop("REMAINING", [.header, .staticText]))
                stops += block.remaining.map { Stop($0, .button) }
            }
            return stops
        }

        static let pulldown = "Lat Pulldown, set %d, 102.5 pounds, 13 reps"
        static let raiseRow = "Cable Lateral Raise, set %d, 15 pounds, 16 reps"

        /// Upper A's superset in pounds, its six rows in `states` in display order (A1 B1 A2 B2 A3 B3).
        static func upperASuperset(_ states: [String], current: Int, last: String, canRepeat: Bool) -> Block {
            let rows = states.enumerated().map { index, state in
                let number = index / 2 + 1
                let letter = index.isMultiple(of: 2) ? "A" : "B"
                let summary = String(format: index.isMultiple(of: 2) ? pulldown : raiseRow, number)
                return Row(
                    summary: summary,
                    state: state,
                    check: "\(state == "Done" ? "Undo" : "Log") set \(letter)\(number)"
                )
            }
            return Block(
                place: "Superset · block 4 of 4",
                round: "Round 2 of 3",
                legend: [
                    Legend(spoken: "A, Lat Pulldown, 3 × 13 @ 102.5 lb", isCurrent: current == 3),
                    Legend(spoken: "B, Cable Lateral Raise, 3 × 16 @ 15 lb", isCurrent: current == 4)
                ],
                rest: "Rest 1 minute, 15 seconds after B",
                last: last,
                canRepeat: canRepeat,
                rows: rows,
                steppers: current == 3
                    ? Steppers("2.5 LB", "102.5 pounds", "13 reps")
                    : Steppers("2.5 LB", "15 pounds", "16 reps")
            )
        }

        static let raiseBlockInKilograms = Block(
            place: "Superset · block 4 of 4",
            round: "Round 1 of 4",
            legend: [
                Legend(spoken: "A, Lat Pulldown, 3 × 13 @ 46.5 kg", swap: "Swap Lat Pulldown"),
                Legend(spoken: "B, Cable Lateral Raise, 3 × 16 @ 10 kg", isCurrent: true)
            ],
            rest: "Rest 1 minute, 15 seconds after B",
            last: "No history yet",
            unit: "kg",
            rows: [
                .pending("Lat Pulldown, set 1, 46.5 kilograms, 13 reps", log: "Log set A1"),
                .done("Cable Lateral Raise, set 1, 10 kilograms, 16 reps", undo: "Undo set B1"),
                .pending("Lat Pulldown, set 2, 46.5 kilograms, 13 reps", log: "Log set A2"),
                .current("Cable Lateral Raise, set 2, 10 kilograms, 16 reps", log: "Log set B2"),
                .pending("Lat Pulldown, set 3, 46.5 kilograms, 13 reps", log: "Log set A3"),
                .pending("Cable Lateral Raise, set 3, 10 kilograms, 16 reps", log: "Log set B3"),
                .pending("Cable Lateral Raise, drop set, 8.75 kilograms, 16 reps", log: "Log set BD")
            ],
            steppers: Steppers("1.25 KG", "10 kilograms", "16 reps"),
            remaining: ["Barbell Bench Press, 5 × 5", "Incline DB Press, 3 × 11", "Chest-Supported Row, 4 × 8"]
        )
    }
#endif
