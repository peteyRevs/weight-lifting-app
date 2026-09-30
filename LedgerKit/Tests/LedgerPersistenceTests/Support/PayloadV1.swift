import Foundation
import LedgerDomain

/// Payload version 1, frozen with schema v001 (review SF1; orchestrator decision, 2026-09-30): the literal
/// value of every committed fixture in `Fixtures/payload-v001/`.
///
/// **Never edit a fixture or its literal.** Each file is JSON that version 1 of `EnvelopeCodec` or
/// `SettingsCodec` writes (pretty-printed), and rows in that shape exist on lifters' devices. If a change to
/// `EventEnvelope`, `WorkoutEvent`, `WorkoutState` (and the types inside it) or `Settings` in LedgerDomain
/// makes `PayloadV1FixtureTests` fail, that change alters version 1. Ship it as payload version 2: raise the
/// codec's `version` and add a `case` that reads the new shape, keeping `case 1` able to read these files.
/// A renamed key with no version bump is exactly what these tests exist to catch.
enum PayloadV1 {
    /// One committed envelope fixture.
    struct Fixture: Sendable, CustomStringConvertible {
        let file: String
        let envelope: EventEnvelope

        var description: String {
            file
        }
    }

    static let workout = WorkoutID(uuid(0x100))
    static let phone = DeviceID(uuid(0xD01))
    static let watch = DeviceID(uuid(0xD02))
    static let exercise = WorkoutExerciseID(uuid(0xE01))
    static let firstSet = SetID(uuid(0x5E1))
    static let addedSet = SetID(uuid(0x5E2))
    /// 2026-09-16T05:20:00Z.
    static let start = Date(timeIntervalSinceReferenceDate: 811_228_800)

    /// `seconds` after `start`; the sub-millisecond ones are the F04 stamps a lossy store alters.
    static func at(_ seconds: Double) -> Date {
        start.addingTimeInterval(seconds)
    }

    static let fixtures: [Fixture] = [
        Fixture(file: "event-started", envelope: envelope(.started(snapshot), phone, seq: 1, at: at(0))),
        Fixture(
            file: "event-exerciseSelected",
            envelope: envelope(.exerciseSelected(exerciseIndex: 0, setIndex: 1), phone, seq: 2, at: at(3))
        ),
        Fixture(file: "event-setLogged", envelope: envelope(
            .setLogged(
                exerciseIndex: 0,
                setID: firstSet,
                weight: .pounds(185),
                reps: reps(5),
                doneAt: at(10.493_826_8)
            ),
            watch, seq: 1, at: at(10.493_827_3)
        )),
        Fixture(
            file: "event-setUnlogged",
            envelope: envelope(.setUnlogged(exerciseIndex: 0, setID: firstSet), phone, seq: 3, at: at(12))
        ),
        Fixture(file: "event-setTargetChanged", envelope: envelope(
            .setTargetChanged(
                exerciseIndex: 0,
                setID: firstSet,
                weight: .kilograms(83.75),
                reps: reps(4)
            ),
            phone, seq: 4, at: at(14)
        )),
        Fixture(file: "event-setAdded", envelope: envelope(
            .setAdded(exerciseIndex: 0, set: LoggedSet(
                id: addedSet, weight: .pounds(52.5), reps: reps(8), kind: .added,
                doneAt: at(20.25)
            )),
            watch, seq: 2, at: at(20.5)
        )),
        Fixture(file: "event-allSetsRepeated", envelope: envelope(
            .allSetsRepeated(exerciseIndex: 0, weight: .pounds(190), reps: reps(5)), phone, seq: 5, at: at(30)
        )),
        Fixture(file: "event-exerciseSwapped", envelope: envelope(
            .exerciseSwapped(
                exerciseIndex: 0,
                exerciseID: ExerciseID(uuid(0xE02)),
                name: "Incline DB Press",
                alsoUpdateProgram: true
            ),
            phone, seq: 6, at: at(40)
        )),
        Fixture(file: "event-restStarted", envelope: envelope(
            .restStarted(endsAt: at(200.493_826_8), total: .seconds(150)), watch, seq: 3, at: at(50)
        )),
        Fixture(file: "event-restExtended", envelope: envelope(
            .restExtended(amount: .seconds(30), extendsShownRest: true, tappedAt: at(60.125)), watch, seq: 4,
            at: at(60.2)
        )),
        // The largest seq, and a NaN stamp: version 1 writes it as the string "NaN".
        Fixture(file: "event-restSkipped", envelope: envelope(
            .restSkipped, watch, seq: .max, at: Date(timeIntervalSinceReferenceDate: .nan)
        )),
        // A payload date of +∞: version 1 writes it as the string "+Infinity".
        Fixture(file: "event-finished", envelope: envelope(
            .finished(endedAt: Date(timeIntervalSinceReferenceDate: .infinity)), phone, seq: 7, at: at(3600)
        )),
        Fixture(file: "event-discarded", envelope: envelope(
            .discarded(endedAt: Date(timeIntervalSinceReferenceDate: -.infinity)), watch, seq: 1 << 63, at: at(3601)
        ))
    ]

    /// `event`'s case name. The switch is exhaustive on purpose: a new `WorkoutEvent` case does not compile
    /// until it is listed here and in `allCaseNames`, and then `everyEventCase_hasAFixture` fails until it
    /// has a fixture.
    static func caseName(_ event: WorkoutEvent) -> String {
        switch event {
        case .started, .exerciseSelected, .setLogged, .setUnlogged, .setTargetChanged, .setAdded, .allSetsRepeated,
             .exerciseSwapped, .restStarted, .restExtended, .restSkipped, .finished, .discarded:
            Mirror(reflecting: event).children.first?.label ?? String(describing: event)
        }
    }

    static let allCaseNames: Set = [
        "started", "exerciseSelected", "setLogged", "setUnlogged", "setTargetChanged", "setAdded",
        "allSetsRepeated", "exerciseSwapped", "restStarted", "restExtended", "restSkipped", "finished", "discarded"
    ]
}

extension PayloadV1 {
    /// A live snapshot with every optional field set, so a renamed optional key cannot decode as `nil` unseen.
    static let snapshot = WorkoutState(
        id: workout,
        source: WorkoutSource(programID: ProgramID(uuid(0x9A)), weekIndex: 2, dayTemplateID: DayTemplateID(uuid(0xDA))),
        name: "Upper A — Push focus",
        tag: "UA",
        isDeload: false,
        exercises: [WorkoutExercise(
            id: exercise,
            slotID: SlotID(uuid(0x51)),
            exerciseID: ExerciseID(uuid(0xE01)),
            originalExerciseID: ExerciseID(uuid(0xE01)),
            name: "Barbell Bench Press",
            equipment: .barbell,
            step: .pounds(5),
            rest: rest(150),
            rpe: rpe(8.5),
            isSupersetWithPrevious: false,
            targetSets: 2,
            targetReps: 5,
            targetLoad: .pounds(185),
            sets: [
                LoggedSet(id: firstSet, weight: .pounds(185), reps: reps(5), kind: .working, doneAt: at(9.493_826_8)),
                LoggedSet(id: SetID(uuid(0x5E0)), weight: .pounds(185), reps: reps(5), kind: .drop)
            ],
            lastPerformance: LastPerformance(date: at(-604_800), sets: 5, reps: 5, load: .pounds(180))
        )],
        cursor: Cursor(exerciseIndex: 0, setIndex: 1),
        rest: RestTimer(endsAt: at(159.5), total: .seconds(150)),
        startedAt: at(0),
        endedAt: at(7200),
        phase: .live,
        originDevice: phone,
        autoRest: false,
        units: .kg,
        programUpdates: [SlotID(uuid(0x51)): ExerciseID(uuid(0xE02))]
    )

    /// Every field away from `Settings.default`.
    static let settings = Settings(
        units: .kg,
        defaultRest: rest(120),
        plateMathEnabled: false,
        autoRest: false,
        watchBuzz: false,
        weekStart: .sunday,
        plateInventory: [
            .kg: PlateInventory(bar: .kilograms(15), plates: [.kilograms(25), .kilograms(0.5)]),
            .lb: PlateInventory(bar: .pounds(35), plates: [.pounds(45), .pounds(1.25)])
        ]
    )

    /// `a` and `b` are the same envelope, bit for bit in the stamp: `==` alone fails on a NaN stamp.
    static func identical(_ lhs: EventEnvelope, _ rhs: EventEnvelope) -> Bool {
        lhs.event == rhs.event && lhs.workoutID == rhs.workoutID && lhs.key == rhs.key
            && lhs.wallClock.timeIntervalSinceReferenceDate.bitPattern
            == rhs.wallClock.timeIntervalSinceReferenceDate.bitPattern
    }

    private static func envelope(
        _ event: WorkoutEvent,
        _ device: DeviceID,
        seq: UInt64,
        at stamp: Date
    ) -> EventEnvelope {
        EventEnvelope(event: event, workoutID: workout, device: device, seq: seq, wallClock: stamp)
    }

    /// 00000000-0000-0000-0000-0000000NNNNN.
    private static func uuid(_ number: Int) -> UUID {
        func byte(_ shift: Int) -> UInt8 {
            UInt8(truncatingIfNeeded: number >> shift)
        }
        return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte(24), byte(16), byte(8), byte(0)))
    }

    private static func reps(_ value: Int) -> Reps {
        Reps(clamping: value)
    }

    private static func rest(_ seconds: Int) -> RestDuration {
        guard let rest = RestDuration(seconds: seconds) else {
            preconditionFailure("a fixture rest must be valid, got \(seconds) s")
        }
        return rest
    }

    private static func rpe(_ value: Decimal) -> RPE {
        guard let rpe = RPE(value) else {
            preconditionFailure("a fixture RPE must be valid, got \(value)")
        }
        return rpe
    }
}
