import Foundation

/// The lifter's log as CSV (F14 S2, criterion 5, N13–N15): one row per set, in RFC 4180's shape.
///
/// - Columns: `date,time,workout,tag,exercise,set,kind,weight_<unit>,reps,done,e1rm_<unit>`, every weight in the one
///   unit asked for (Pete's question 5, A), with the unit in the column's title.
/// - `date` is the day the workout started in the lifter's calendar (`YYYY-MM-DD`, decision #26), `time` its start
///   (`HH:mm`). `set` counts from 1 within the exercise; `kind` is the set's kind as stored (`working`, `warmup`,
///   `drop`, `added`); `done` is `1` or `0`. Every set is written, done or not (question 5, A).
/// - A weight is a plain decimal: a `.` separator, no grouping, rounded to hundredths (225 lb is `102.06` kg).
/// - `e1rm` is Brzycki's estimate (decision #4) of a done set of 12 reps or fewer, and empty otherwise.
/// - No health value is written (architecture §16): the workout's own rows hold none.
/// - Rows end with CRLF. A field that holds a comma, a quote, a CR or an LF is quoted, its quotes doubled (RFC 4180),
///   and a text field that starts with `=`, `+`, `-`, `@`, a tab or a CR is given a leading `'` first, so a
///   spreadsheet opens it as text and never as a formula (OWASP's CSV injection rule, N14). Numbers are never
///   prefixed.
///
/// `header(units:)` and `lines(for:units:calendar:)` let a writer stream the file workout by workout; `render` is
/// both, in one `String`. The file's encoding, UTF-8 with a byte-order mark (N15), is the writer's: `byteOrderMark`.
public enum CSVExport {
    /// Written before the header, so a spreadsheet reads the file as UTF-8 ("Développé").
    public static let byteOrderMark = "\u{FEFF}"
    static let rowEnd = "\r\n"
    /// What makes a text field read as a formula when it starts with one.
    static let formulaStarts: Set<Unicode.Scalar> = ["=", "+", "-", "@", "\t", "\r"]
    /// What makes a field need quotes.
    static let quotedScalars: Set<Unicode.Scalar> = [",", "\"", "\r", "\n"]

    /// The header row, with its CRLF.
    public static func header(units: Units) -> String {
        let unit = units.rawValue
        return "date,time,workout,tag,exercise,set,kind,weight_\(unit),reps,done,e1rm_\(unit)" + rowEnd
    }

    /// The rows of every set of `workout`, each with its CRLF; nothing for a workout with no set.
    public static func lines(for workout: WorkoutState, units: Units, calendar: Calendar) -> String {
        let date = CivilDate(workout.startedAt, in: calendar)?.description ?? ""
        let clock = calendar.dateComponents([.hour, .minute], from: workout.startedAt)
        let time = String(format: "%02d:%02d", clock.hour ?? 0, clock.minute ?? 0)
        var text = ""
        for exercise in workout.exercises {
            for (index, set) in exercise.sets.enumerated() {
                let estimate = set.isDone ? OneRepMax.brzycki(weight: set.weight, reps: set.reps) : nil
                let fields = [
                    date, time, textField(workout.name), textField(workout.tag), textField(exercise.name),
                    String(index + 1), set.kind.rawValue, number(set.weight, in: units), String(set.reps.value),
                    set.isDone ? "1" : "0", estimate.map { number($0, in: units) } ?? ""
                ]
                text += fields.joined(separator: ",") + rowEnd
            }
        }
        return text
    }

    /// The header and every workout's rows, in the order given.
    public static func render(workouts: [WorkoutState], units: Units, calendar: Calendar) -> String {
        workouts.reduce(header(units: units)) { $0 + lines(for: $1, units: units, calendar: calendar) }
    }

    /// `weight` in `units`, rounded to hundredths, as plain digits.
    static func number(_ weight: Weight, in units: Units) -> String {
        DecimalText.encode(weight.value(in: units).rounded(scale: 2, .toNearestOrAwayFromZero))
    }

    /// A name or tag as a field: guarded against formulas (N14), then quoted when it must be.
    static func textField(_ text: String) -> String {
        let guarded = text.unicodeScalars.first.map(formulaStarts.contains) == true ? "'" + text : text
        guard guarded.unicodeScalars.contains(where: quotedScalars.contains) else {
            return guarded
        }
        // Scalar by scalar: a quote followed by a combining mark is one `Character`, which a search by characters
        // would not find.
        var quoted = String.UnicodeScalarView(["\""])
        for scalar in guarded.unicodeScalars {
            if scalar == "\"" {
                quoted.append("\"")
            }
            quoted.append(scalar)
        }
        quoted.append("\"")
        return String(quoted)
    }
}
