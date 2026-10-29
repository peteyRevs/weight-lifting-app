#if DEBUG
    @testable import FeatureHistory
    @testable import FeatureWorkout
    import Foundation
    import LedgerDomain
    import LedgerTestSupport
    import Testing

    /// F13 S2 adversarial (G2), N13: for random finished workouts (warm-ups, added and drop sets, sets edited off their
    /// target, sets not done, converted weights, no exercise at all, nothing done, long and zero times) with none, one
    /// or several of the records they can hold, the detail in either unit equals F10's receipt of the same workout
    /// drawn in that unit, string for string, in seven locales.
    @Suite("Adversarial F13 S2 · the detail is the receipt")
    struct WorkoutDetailParityAdversarialTests {
        static let locales = ["en_US", "en_GB", "de_DE", "fr_FR", "ar_EG", "ja_JP", "hi_IN"]
            .map(Locale.init(identifier:))

        /// How the detail of `recorded` in `units` differs from F10's receipt of it drawn in `units`; nil when equal.
        static func mismatch(_ recorded: RecordedWorkout, units: Units, locale: Locale) -> String? {
            var drawn = recorded.workout
            drawn.units = units
            let receipt = WorkoutPresentation.receipt(
                drawn,
                records: recorded.records,
                locale: locale,
                calendar: Fixtures.calendar
            )
            let detail = WorkoutDetailPresentation.make(WorkoutDetailInput(
                recorded: recorded,
                units: units,
                calendar: Fixtures.calendar,
                locale: locale
            ))
            if detail.receipt.tiles != receipt.page.tiles {
                return "tiles \(detail.receipt.tiles) vs \(receipt.page.tiles)"
            }
            if detail.receipt.records != receipt.page.records {
                let records = (detail.receipt.records, receipt.page.records)
                return "records \(String(describing: records.0)) vs \(String(describing: records.1))"
            }
            if detail.receipt != receipt.page {
                let pairs = zip(detail.receipt.rows, receipt.page.rows).first { $0 != $1 }
                return "rows: \(pairs.map { "\($0.0) vs \($0.1)" } ?? "counts differ")"
            }
            if detail.date != receipt.header.date || detail.title != receipt.header.title {
                return "header \(detail.date) \(detail.title) vs \(receipt.header.date) \(receipt.header.title)"
            }
            return nil
        }

        @Test("N13. Random workouts, both units, seven locales: the detail is F10's receipt drawn in that unit")
        func detail_isTheReceipt_inBothUnits_everywhere() {
            var compared = (records: Set<Int>(), empty: 0, kinds: Set<String>())
            for seed in UInt64(1) ... 120 {
                let recorded = ParityWorkouts.workout(seed: seed)
                compared.records.insert(min(recorded.records.count, 2))
                compared.empty += recorded.workout.exercises.isEmpty ? 1 : 0
                for set in recorded.workout.exercises.flatMap(\.sets) {
                    compared.kinds.insert("\(set.kind)")
                }
                for units in [Units.lb, .kg] {
                    for locale in Self.locales {
                        let difference = Self.mismatch(recorded, units: units, locale: locale)
                        #expect(difference == nil, "seed \(seed), \(units), \(locale.identifier)")
                    }
                }
            }
            #expect(compared.records == [0, 1, 2], "no record, one, and several")
            #expect(compared.empty > 0, "a workout with no exercise")
            #expect(compared.kinds.count == 4, "every kind of set")
        }

        @Test("N13. A pound workout drawn in kilograms reads 90.7 for 200 lb, as the receipt in kilograms would")
        func poundWorkout_inKilograms_readsTheConversion() throws {
            let recorded = ParityWorkouts.workout(seed: 7)
            var workout = recorded.workout
            workout.units = .lb
            for index in workout.exercises.indices {
                workout.exercises[index].targetLoad = .pounds(200)
                for set in workout.exercises[index].sets.indices {
                    workout.exercises[index].sets[set].weight = .pounds(200)
                }
            }
            let pounds = RecordedWorkout(workout: workout, records: recorded.records)
            try #require(!workout.exercises.isEmpty)
            let detail = WorkoutDetailPresentation.make(WorkoutDetailInput(
                recorded: pounds,
                units: .kg,
                calendar: Fixtures.calendar,
                locale: Fixtures.locale
            ))
            let targets = detail.receipt.rows.map(\.target)
            #expect(targets.allSatisfy { $0.contains("90.7") }, "\(targets)")
            #expect(Self.mismatch(pounds, units: .kg, locale: Fixtures.locale) == nil)
        }
    }

    /// The random finished workouts the parity is checked on, each rebuilt from its seed.
    nonisolated enum ParityWorkouts {
        /// SplitMix64, so a failing workout can be rebuilt from its seed.
        struct Generator: RandomNumberGenerator {
            var state: UInt64

            mutating func next() -> UInt64 {
                state &+= 0x9E37_79B9_7F4A_7C15
                var value = state
                value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
                value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
                return value ^ (value >> 31)
            }
        }

        static func pick<Value>(_ values: [Value], _ rng: inout Generator) -> Value {
            values[Int.random(in: 0 ..< values.count, using: &rng)]
        }

        static let rpe: RPE = {
            guard let value = RPE(8) else {
                preconditionFailure("RPE 8 is valid")
            }
            return value
        }()

        static let weights: [Weight] = [
            .pounds(185), .pounds(102.5), .pounds(Decimal(string: "102.3") ?? 0), .kilograms(47.5), .kilograms(60),
            .pounds(200), .zero, .pounds(1_234_567), .kilograms(Decimal(string: "90.7") ?? 0)
        ]

        /// Exercise `index` of workout `seed`: some sets on target, some edited off it, every kind, some not done.
        static func exercise(_ index: Int, seed: UInt64, start: Date, _ rng: inout Generator) -> WorkoutExercise {
            let target = pick(weights, &rng)
            let sets = (0 ..< Int.random(in: 0 ... 7, using: &rng)).map { position in
                LoggedSet(
                    id: SetID(Fixtures.uuid(20000 + Int(seed % 1000) * 100 + index * 10 + position)),
                    weight: Bool.random(using: &rng) ? target : pick(weights, &rng),
                    reps: Reps(clamping: pick([0, 1, 3, 5, 8, 12, 20], &rng)),
                    kind: pick([.working, .working, .warmup, .added, .drop], &rng),
                    doneAt: Int.random(in: 0 ..< 10, using: &rng) < 8 ? start.addingTimeInterval(60) : nil
                )
            }
            return WorkoutExercise(
                id: WorkoutExerciseID(Fixtures.uuid(30000 + Int(seed % 1000) * 10 + index)),
                slotID: nil,
                exerciseID: ExerciseID(Fixtures.uuid(40000 + index)),
                originalExerciseID: ExerciseID(Fixtures.uuid(40000 + index)),
                name: pick(["Bench Press", "Squat", "Romanian Deadlift with a very long name to wrap"], &rng),
                equipment: .barbell,
                step: pick([.pounds(5), .kilograms(2.5)], &rng),
                rest: .defaultRest,
                rpe: rpe,
                isSupersetWithPrevious: false,
                targetSets: Int.random(in: 1 ... 5, using: &rng),
                targetReps: pick([1, 5, 8, 12], &rng),
                targetLoad: target,
                sets: sets
            )
        }

        /// The records `workout` sets over a tiny best for every lift (a lift's first session sets none).
        static func records(of workout: WorkoutState) -> [PersonalRecord] {
            let lifts = Set(workout.exercises.map(\.exerciseID))
            let tiny = Weight(grams: 1)
            let repsBests = Dictionary(uniqueKeysWithValues: [1, 3, 5, 8, 12, 20].map { (Reps(clamping: $0), tiny) })
            return PersonalRecords.detect(
                workout: workout,
                bestE1RM: Dictionary(uniqueKeysWithValues: lifts.map { ($0, tiny) }),
                bestWeightAtReps: Dictionary(uniqueKeysWithValues: lifts.map { ($0, repsBests) }),
                now: workout.startedAt
            )
        }

        /// Workout `seed`, with some of the records it sets: none, one or several.
        static func workout(seed: UInt64) -> RecordedWorkout {
            var rng = Generator(state: seed)
            let start = Fixtures.now.addingTimeInterval(-86400 * Double(Int.random(in: 1 ... 400, using: &rng)))
            let length = pick([0, 59, 1462, 3600, 3725, 36000], &rng)
            let exercises = (0 ..< Int.random(in: 0 ... 4, using: &rng)).map { index in
                exercise(index, seed: seed, start: start, &rng)
            }
            let workout = WorkoutState(
                id: WorkoutID(Fixtures.uuid(50000 + Int(seed % 1000))),
                source: nil,
                name: "Session \(seed)",
                tag: "S",
                isDeload: false,
                exercises: exercises,
                cursor: nil,
                startedAt: start,
                endedAt: start.addingTimeInterval(TimeInterval(length)),
                phase: .finished,
                originDevice: Fixtures.deviceID,
                units: pick([.lb, .kg], &rng)
            )
            let all = records(of: workout)
            return RecordedWorkout(
                workout: workout,
                records: Array(all.prefix(Int.random(in: 0 ... all.count, using: &rng)))
            )
        }
    }
#endif
