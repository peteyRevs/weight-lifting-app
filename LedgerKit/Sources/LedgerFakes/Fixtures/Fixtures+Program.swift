#if DEBUG
    import Foundation
    import LedgerDomain

    // MARK: - Exercises (catalog ids)

    public extension Fixtures {
        /// The catalog ids of the sixteen exercises in the spec's seed program (§6.4), as `exercises.json`
        /// holds them.
        enum CatalogID {
            public static let benchPress = id("270DE1C9-481F-4904-BE85-070381E296C0")
            public static let inclineDBPress = id("34ABACC5-2E75-4EE1-9F67-DC9E925E6D37")
            public static let chestSupportedRow = id("A9ED72CF-D506-430B-A12F-501D15B18E44")
            public static let latPulldown = id("5F043F91-CD6E-4E9B-B12C-5B33ECB9B049")
            public static let cableLateralRaise = id("18EC9F77-0DD1-4037-B7B8-8214744142AC")
            public static let backSquat = id("73EE7555-DC9F-4D98-A87F-08C8817876F1")
            public static let romanianDeadlift = id("C6C70E2B-BB44-4A53-98DD-D4861B70E8D7")
            public static let legPress = id("80834235-1B66-4070-8F6A-5A87794792FC")
            public static let standingCalfRaise = id("87EF983A-8D62-488E-9AAE-7BECDBF6F5EF")
            public static let weightedPullUp = id("0865DC39-D829-4DFD-8E6D-6EE9302EB777")
            public static let overheadPress = id("DA5CE9D0-60A1-41BC-B634-A3516D27B544")
            public static let barbellRow = id("90383748-7413-4398-99FA-6EB6E5F2969A")
            public static let barbellCurl = id("6C2540C1-DAF5-4ECB-B66E-C9EA231EB0CE")
            public static let deadlift = id("F5CB98F6-7533-4BE9-85FA-8013FF01B1C6")
            public static let frontSquat = id("223208C8-E7BB-4514-A335-6FCC43A62E18")
            public static let seatedLegCurl = id("60C1A421-610C-4FC2-8416-0DAC57FE29BC")

            private static func id(_ text: String) -> ExerciseID {
                ExerciseID(UUID(uuidString: text) ?? Fixtures.uuid(0))
            }
        }

        /// Barbell Bench Press exactly as the bundled catalog holds it.
        static let benchPress = Exercise(
            id: CatalogID.benchPress,
            name: "Barbell Bench Press",
            shortName: "BENCH",
            equipment: .barbell,
            primaryMuscle: .chest,
            secondaryMuscles: [.triceps, .shoulders],
            pattern: .horizontalPush,
            defaultStartLoad: [.lb: .pounds(45), .kg: .kilograms(20)],
            curatedAlternatives: [
                "EB0FC0F1-59AF-4445-8560-3198F298EF59",
                "10775544-0350-413A-835D-EA958A0902A0",
                "2BF340CA-A558-40D2-81D9-5BF2DF1EB60F",
                "46D64A8D-675A-4D62-8319-7C61894FE94B"
            ].compactMap { UUID(uuidString: $0).map(ExerciseID.init) }
        )
    }

    // MARK: - Days and the program (spec §6.4)

    public extension Fixtures {
        /// "Upper A — Push focus": five slots, the last two a superset.
        static func upperA() throws -> DayTemplate {
            try day(300, "Upper A — Push focus", "UA", [
                SeedSlot(exercise: CatalogID.benchPress, sets: 5, reps: 5, rest: 150, pounds: 180),
                SeedSlot(
                    exercise: CatalogID.inclineDBPress,
                    sets: 3,
                    reps: 10,
                    rest: 90,
                    progression: .double,
                    pounds: 50
                ),
                SeedSlot(exercise: CatalogID.chestSupportedRow, sets: 4, reps: 8, rest: 90, pounds: 65),
                SeedSlot(
                    exercise: CatalogID.latPulldown,
                    sets: 3,
                    reps: 12,
                    rpe: 9,
                    rest: 75,
                    progression: .double,
                    pounds: 100
                ),
                SeedSlot(
                    exercise: CatalogID.cableLateralRaise, sets: 3, reps: 15, rpe: 9, rest: 60, progression: .double,
                    pounds: 12.5, superset: true
                )
            ])
        }

        /// "Lower A — Squat focus": four slots, the last two a superset.
        static func lowerA() throws -> DayTemplate {
            try day(310, "Lower A — Squat focus", "LA", [
                SeedSlot(exercise: CatalogID.backSquat, sets: 5, reps: 5, rest: 180, pounds: 250),
                SeedSlot(exercise: CatalogID.romanianDeadlift, sets: 3, reps: 8, rest: 120, pounds: 205),
                SeedSlot(
                    exercise: CatalogID.legPress,
                    sets: 3,
                    reps: 12,
                    rpe: 9,
                    rest: 90,
                    progression: .double,
                    pounds: 320
                ),
                SeedSlot(
                    exercise: CatalogID.standingCalfRaise, sets: 4, reps: 12, rpe: 9, rest: 60, progression: .fixed,
                    pounds: 160, superset: true
                )
            ])
        }

        /// "Upper B — Pull focus": four slots, the curl with a drop set.
        static func upperB() throws -> DayTemplate {
            try day(320, "Upper B — Pull focus", "UB", [
                SeedSlot(exercise: CatalogID.weightedPullUp, sets: 4, reps: 6, rest: 150, pounds: 35),
                SeedSlot(exercise: CatalogID.overheadPress, sets: 4, reps: 6, rest: 120, pounds: 115),
                SeedSlot(exercise: CatalogID.barbellRow, sets: 3, reps: 10, rest: 90, pounds: 155),
                SeedSlot(
                    exercise: CatalogID.barbellCurl, sets: 3, reps: 12, rpe: 9, rest: 60, progression: .double,
                    pounds: 75,
                    dropSets: 1
                )
            ])
        }

        /// "Lower B — Hinge focus": three slots.
        static func lowerB() throws -> DayTemplate {
            try day(330, "Lower B — Hinge focus", "LB", [
                SeedSlot(exercise: CatalogID.deadlift, sets: 4, reps: 4, rest: 210, pounds: 315),
                SeedSlot(exercise: CatalogID.frontSquat, sets: 3, reps: 8, rest: 120, pounds: 185),
                SeedSlot(
                    exercise: CatalogID.seatedLegCurl,
                    sets: 3,
                    reps: 12,
                    rpe: 9,
                    rest: 75,
                    progression: .double,
                    pounds: 90
                )
            ])
        }

        /// The spec's seed program (§6.4), active: 8 weeks from Monday 2026-08-17; weeks 1–7 run Upper A on
        /// Monday, Lower A on Wednesday, Upper B on Friday and Lower B on Saturday, and week 8 is a deload of
        /// the first three.
        static func seedProgram() throws -> Program {
            let days = try [upperA(), lowerA(), upperB(), lowerB()]
            let weekdays: [Weekday] = [.monday, .wednesday, .friday, .saturday]
            let full = Dictionary(uniqueKeysWithValues: zip(weekdays, days.map(\.id)))
            let deload = full.filter { $0.key != .saturday }
            let weeks = (0 ..< 8).map { index in
                Week(
                    id: WeekID(uuid(200 + index)),
                    index: index,
                    isDeload: index == 7,
                    schedule: index == 7 ? deload : full
                )
            }
            guard let start = CivilDate(year: 2026, month: 8, day: 17) else {
                throw Invalid(fixture: "seedProgram.startDate")
            }
            return try Program(
                id: programID,
                name: "Upper / Lower",
                startDate: start,
                weeks: weeks,
                days: days,
                goal: .both,
                daysPerWeek: 4,
                isActive: true
            )
        }

        /// The live session Today starts at `now`: Upper A in week 5 of `seedProgram`, no set logged yet, built
        /// by `SessionBuilder` over the bundled catalog.
        static func seedSession() throws -> WorkoutState {
            let program = try seedProgram()
            return try SessionBuilder.build(
                program: program,
                weekIndex: 4,
                day: program.days[0],
                exercises: catalogByID(),
                history: [:],
                settings: settingsLb,
                id: sessionID,
                device: deviceID,
                now: now
            )
        }
    }

    extension Fixtures {
        /// One row of spec §6.4's table: `mk(name, sets, reps, rpe, rest)`, the prototype's `W0` load in pounds,
        /// and the overrides (`prog`, `sup`, `drop`).
        struct SeedSlot {
            let exercise: ExerciseID
            let sets: Int
            let reps: Int
            var rpe: Decimal = 8
            let rest: Int
            var progression: Progression = .linear
            let pounds: Decimal
            var superset = false
            var dropSets = 0
        }

        /// Day `number` with its rows as slots `number + 1`, `number + 2`, …: `repsHi = reps + 2` and the
        /// equipment's default step, as `mk` builds them.
        static func day(_ number: Int, _ name: String, _ tag: String, _ rows: [SeedSlot]) throws -> DayTemplate {
            let slots = try rows.enumerated().map { index, row in
                try Slot(
                    id: SlotID(uuid(number + 1 + index)),
                    exerciseID: row.exercise,
                    sets: row.sets,
                    reps: row.reps,
                    repsHi: row.reps + 2,
                    rpe: row.rpe,
                    restSeconds: row.rest,
                    progression: row.progression,
                    startLoad: .pounds(row.pounds),
                    isSupersetWithPrevious: row.superset,
                    dropSets: row.dropSets
                )
            }
            return DayTemplate(id: DayTemplateID(uuid(number)), name: name, tag: tag, slots: slots)
        }

        /// The bundled catalog by id.
        static func catalogByID() throws -> [ExerciseID: Exercise] {
            try Dictionary(ExerciseCatalog.seed().map { ($0.id, $0) }) { first, _ in first }
        }
    }
#endif
