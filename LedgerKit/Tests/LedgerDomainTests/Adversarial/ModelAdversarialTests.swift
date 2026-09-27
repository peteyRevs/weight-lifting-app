import Foundation
@testable import LedgerDomain
import Testing

@Suite("Models (adversarial)", .tags(.domain))
struct ModelAdversarialTests {
    static func bench(_ rows: [LoggedSet], targetSets: Int = 5) throws -> WorkoutExercise {
        try Adversarial.exercise(rows: rows, targetSets: targetSets, targetReps: 5)
    }

    static func row(
        _ number: Int,
        _ weight: String,
        _ reps: Int,
        kind: SetKind = .working,
        done: Bool = true
    ) -> LoggedSet {
        Adversarial.row(number, weight: pounds(weight), reps: reps, kind: kind, done: done)
    }
}

extension ModelAdversarialTests {
    @Test("RestTimer counts down from total to zero and never goes negative (rule 23).")
    func restTimer_remainingAndFraction() {
        let timer = RestTimer(endsAt: Fixtures.now, total: .seconds(90))
        #expect(timer.remaining(at: Fixtures.now.addingTimeInterval(-90)) == .seconds(90))
        #expect(timer.remaining(at: Fixtures.now.addingTimeInterval(-30)) == .seconds(30))
        #expect(timer.remaining(at: Fixtures.now.addingTimeInterval(45)) == .zero)
        #expect(timer.fraction(at: Fixtures.now.addingTimeInterval(-45)) == 0.5)
        #expect(timer.fraction(at: Fixtures.now.addingTimeInterval(-90)) == 1)
        #expect(timer.fraction(at: Fixtures.now.addingTimeInterval(5)) == 0)
        #expect(timer.fraction(at: Fixtures.now.addingTimeInterval(-200)) == 1)
        #expect(RestTimer(endsAt: Fixtures.now, total: .zero).fraction(at: Fixtures.now) == 0)
    }

    @Test("Workout totals count set rows; volume sums only done sets (rule 34).")
    func workoutState_totalsAndVolume() throws {
        let rows = [
            Self.row(1, "185", 5), Self.row(2, "185", 5, done: false), Self.row(3, "155", 8, kind: .drop),
            Self.row(4, "185", 3, kind: .added)
        ]
        let workout = try Fixtures.workout([Self.bench(rows), Self.bench([Self.row(5, "100", 10)])])
        #expect(workout.doneSets == 4)
        #expect(workout.totalSets == 5)
        let grams = pounds("185").grams * 5 + pounds("155").grams * 8 + pounds("185").grams * 3 + pounds("100")
            .grams * 10
        #expect(workout.volume.gramReps == grams)
    }

    @Test("Elapsed time runs from start, freezes at the end and is never negative (rule 24).")
    func workoutState_elapsed() throws {
        var workout = try Fixtures.workout([Self.bench([Self.row(1, "185", 5)])])
        let start = workout.startedAt
        #expect(workout.elapsed(at: start.addingTimeInterval(125)) == .seconds(125))
        #expect(workout.elapsed(at: start.addingTimeInterval(-60)) == .zero)
        workout.endedAt = start.addingTimeInterval(3000)
        #expect(workout.elapsed(at: start.addingTimeInterval(9000)) == .seconds(3000))
    }

    @Test("The last-performance line is 'MMM d · s×r @ load unit' in the calendar's zone, locale-independent.")
    func lastPerformance_line() throws {
        let last = LastPerformance(date: Fixtures.date(2026, 8, 12, hour: 2), sets: 5, reps: 5, load: pounds("180"))
        #expect(last.line(units: .lb, calendar: Fixtures.calendar) == "Aug 12 · 5×5 @ 180 lb")
        var angeles = Fixtures.calendar
        angeles.timeZone = try Fixtures.zone("America/Los_Angeles")
        #expect(last.line(units: .lb, calendar: angeles) == "Aug 11 · 5×5 @ 180 lb")
        var german = Fixtures.calendar
        german.locale = Locale(identifier: "de_DE")
        #expect(last.line(units: .lb, calendar: german) == "Aug 12 · 5×5 @ 180 lb")
        let kilo = LastPerformance(date: Fixtures.date(2026, 1, 3), sets: 3, reps: 10, load: kilos("22.5"))
        #expect(kilo.line(units: .kg, calendar: Fixtures.calendar) == "Jan 3 · 3×10 @ 22.5 kg")
    }

    @Test("Receipt rows run-length-group done sets and show '—' when none were done (rule 30).")
    func receiptRow_grouping() throws {
        let grouped = try Self.bench([
            Self.row(1, "185", 5),
            Self.row(2, "185", 5),
            Self.row(3, "185", 5),
            Self.row(4, "185", 5),
            Self.row(5, "185", 4)
        ])
        let row = ReceiptRow(exercise: grouped, units: .lb)
        #expect(row.target == "5 × 5 @ 185 lb")
        #expect(row.actual == ["4 × 185×5", "185×4"])
        #expect(row.name == Fixtures.bench.name)
        let none = try Self.bench([Self.row(1, "185", 5, done: false)])
        #expect(ReceiptRow(exercise: none, units: .lb).actual == ["—"])
        let gapped = try Self.bench([Self.row(1, "185", 5), Self.row(2, "185", 5, done: false), Self.row(3, "185", 5)])
        #expect(ReceiptRow(exercise: gapped, units: .lb).actual == ["2 × 185×5"])
        let alternating = try Self.bench([Self.row(1, "185", 5), Self.row(2, "180", 5), Self.row(3, "185", 5)])
        #expect(ReceiptRow(exercise: alternating, units: .lb).actual == ["185×5", "180×5", "185×5"])
        let drop = try Self.bench([Self.row(1, "75", 12), Self.row(2, "75", 12), Self.row(3, "65", 12, kind: .drop)])
        #expect(ReceiptRow(exercise: drop, units: .lb).actual == ["2 × 75×12", "65×12"])
        #expect(ReceiptRow(exercise: grouped, units: .kg).target == "5 × 5 @ 83.9 kg")
    }

    @Test(
        "shortTitle is the text before ' — ' (rule 45).",
        arguments: [
            ("Upper A — Push focus", "Upper A"), ("Legs", "Legs"), ("A — B — C", "A"), (
                "Upper A - Push",
                "Upper A - Push"
            ),
            ("", ""), ("New day", "New day")
        ]
    )
    func dayTemplate_shortTitle(name: String, title: String) {
        #expect(DayTemplate(id: DayTemplateID(Fixtures.uuid(1)), name: name, tag: "X").shortTitle == title)
    }

    @Test("The last-performance line stays Gregorian and English under a Buddhist calendar.")
    func lastPerformance_buddhistCalendar() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = Fixtures.utc
        buddhist.locale = Locale(identifier: "th_TH")
        let last = LastPerformance(date: Fixtures.date(2026, 8, 12, hour: 9), sets: 5, reps: 5, load: pounds("180"))
        #expect(last.line(units: .lb, calendar: buddhist) == "Aug 12 · 5×5 @ 180 lb")
    }

    @Test("Settings.default carries the documented defaults (rule 3, decisions #7, #9).")
    func settings_defaults() {
        let settings = Settings.default
        #expect(settings.units == .lb)
        #expect(settings.defaultRest.seconds == 90)
        #expect(settings.autoRest)
        #expect(settings.watchBuzz)
        #expect(settings.plateInventory[.lb] == .standard(.lb))
        #expect(settings.plateInventory[.kg] == .standard(.kg))
    }

    @Test("Derived child IDs are deterministic and distinct per workout, exercise and index.")
    func derivedIDs_distinct() {
        let workouts = (0 ..< 20).map { WorkoutID(Fixtures.uuid(5000 + $0)) }
        let exercises = workouts.flatMap { workout in (0 ..< 10).map { WorkoutExerciseID.derived(
            from: workout,
            index: $0
        ) } }
        #expect(Set(exercises).count == exercises.count)
        let sets = exercises.flatMap { exercise in (0 ..< 13).map { SetID.derived(from: exercise, index: $0) } }
        #expect(Set(sets).count == sets.count)
        #expect(Set(sets.map(\.rawValue)).isDisjoint(with: exercises.map(\.rawValue)))
        #expect(WorkoutExerciseID.derived(from: workouts[0], index: 3) == WorkoutExerciseID.derived(
            from: workouts[0],
            index: 3
        ))
    }
}
