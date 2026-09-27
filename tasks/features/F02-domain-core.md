# F02 — Domain core: models, units, rules, protocols

| | |
|---|---|
| Milestone | M0 |
| Status | ready |
| Depends on | F00 |
| Branch | `feat/F02-domain-core` |
| Design refs | none (pure logic) |
| Spec refs | `docs/product-spec.md` §6.1, §7.1–§7.7; `docs/product-decisions.md` #3–#5, #7, #9, #14, #15, #18; `docs/architecture.md` §5 |

## Goal
`LedgerDomain` becomes the single source of truth for every type and rule in the app: typed identifiers, exact weight arithmetic, program/prescription/progression, session building, superset rounds, 1RM, PRs, plate math, time estimates, week calendar, miss tracking, and the protocols every other module implements. It imports Foundation only and is tested to ≥ 95 %. F04 (engine), F05 (persistence) and every feature build on these names exactly.

## User stories
- As an engineer, I can compute next week's prescription for any slot with one pure call and trust the result.
- As a lifter, weights never drift from float rounding (185.00000001 lb never appears).

## Scope
**In:** everything in "Domain changes" below, with tests.
**Out:** `WorkoutEvent`/`WorkoutEngine` (F04), the exercise JSON (F03), any I/O.

## Touches
- `LedgerKit/Sources/LedgerDomain/Identifiers.swift`
- `LedgerKit/Sources/LedgerDomain/Units/{Weight,Reps,RPE,RestDuration,Volume,Units}.swift`
- `LedgerKit/Sources/LedgerDomain/Model/{Exercise,Program,Week,DayTemplate,Slot,Prescription,WorkoutState,WorkoutExercise,LoggedSet,RestTimer,WorkoutSummary,PersonalRecord,Settings,PlateInventory,LastPerformance}.swift`
- `LedgerKit/Sources/LedgerDomain/Rules/{ProgressionRules,SessionBuilder,SupersetRounds,OneRepMax,PersonalRecords,PlateMath,TimeEstimate,WeekCalendar,MissTracking}.swift`
- `LedgerKit/Sources/LedgerDomain/Protocols/{Repositories,HealthStore,Transports}.swift`
- `LedgerKit/Sources/LedgerDomain/Errors.swift`
- `LedgerKit/Tests/LedgerDomainTests/**` (mirrors the folders above)

## Domain changes

### Identifiers and units
```swift
public struct ExerciseID: Hashable, Codable, Sendable { public let rawValue: UUID; public init(_ rawValue: UUID = UUID()) }
// identically: ProgramID, WeekID, DayTemplateID, SlotID, WorkoutID, WorkoutExerciseID, SetID, DeviceID

public enum Units: String, Codable, Sendable, CaseIterable { case lb, kg }

/// Exact mass in grams. 1 lb = 453.59237 g. Never a Double.
public struct Weight: Hashable, Codable, Sendable, Comparable, AdditiveArithmetic {
    public let grams: Int
    public init(grams: Int)
    public static func pounds(_ lb: Decimal) -> Weight          // rounds to nearest gram
    public static func kilograms(_ kg: Decimal) -> Weight
    public var pounds: Decimal; public var kilograms: Decimal
    public func value(in units: Units) -> Decimal
    public func rounded(toStep step: Weight, _ rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Weight
    public func scaled(by factor: Decimal) -> Weight            // exact Decimal math, then nearest gram
    public func formatted(in units: Units) -> String            // "185", "52.5", "0"; no unit suffix
    public static let zero: Weight
}
public struct Reps: Hashable, Codable, Sendable, Comparable { public let value: Int; public init?(_ value: Int) /* ≥ 1 */; public static let one: Reps }
public struct RPE: Hashable, Codable, Sendable, Comparable { public let value: Decimal; public init?(_ value: Decimal) /* 5…10 in 0.5 steps */ }
public struct RestDuration: Hashable, Codable, Sendable { public let seconds: Int; public init?(seconds: Int) /* 30…300 in 15 s steps */; public var label: String /* "45s", "2 min", "1:30" per rule 39 */ }
/// Σ weight × reps, in gram·reps.
public struct Volume: Hashable, Codable, Sendable, AdditiveArithmetic { public let gramReps: Int; public func formatted(in: Units) -> String /* "24,180" */; public func compact(in: Units) -> String /* "41.2k" */ }
public enum Equipment: String, Codable, Sendable, CaseIterable { case barbell, dumbbell, cable, machine, bodyweight, kettlebell, band
    public func defaultStep(in units: Units) -> Weight }        // lb: barbell 5, others 2.5 · kg: barbell 2.5, others 1.25
public enum MuscleGroup: String, Codable, Sendable, CaseIterable { case chest, back, shoulders, quads, hamstrings, glutes, calves, biceps, triceps, forearms, core }
public enum MovementPattern: String, Codable, Sendable, CaseIterable { case horizontalPush, horizontalPull, verticalPush, verticalPull, squat, hinge, lunge, carry, isolation, core }
public enum Progression: String, Codable, Sendable, CaseIterable { case linear, double, fixed }
public enum Weekday: Int, Codable, Sendable, CaseIterable { case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday }
public enum TrainingGoal: String, Codable, Sendable, CaseIterable { case strength, hypertrophy, both, consistency }
```

### Model
```swift
public struct Exercise: Identifiable, Hashable, Codable, Sendable {
    public let id: ExerciseID; public var name: String; public var shortName: String
    public var equipment: Equipment; public var primaryMuscle: MuscleGroup; public var secondaryMuscles: [MuscleGroup]
    public var pattern: MovementPattern; public var defaultStartLoad: [Units: Weight]; public var isCustom: Bool
    public var curatedAlternatives: [ExerciseID]
}
public struct Program: Identifiable, Hashable, Codable, Sendable {
    public let id: ProgramID; public var name: String; public var startDate: Date /* first day of week 0 */
    public var weeks: [Week] /* ≥ 2, indices contiguous */; public var days: [DayTemplate]
    public var goal: TrainingGoal?; public var daysPerWeek: Int?; public var isActive: Bool
    public init(...) throws   // ProgramValidationError.tooFewWeeks, .nonContiguousWeeks, .danglingSchedule
}
public struct Week: Identifiable, Hashable, Codable, Sendable { public let id: WeekID; public var index: Int; public var isDeload: Bool; public var schedule: [Weekday: DayTemplateID] }
public struct DayTemplate: Identifiable, Hashable, Codable, Sendable { public let id: DayTemplateID; public var name: String /* "Upper A — Push focus" */; public var tag: String /* "UA" */; public var slots: [Slot]
    public var shortTitle: String /* text before " — " */ }
public struct Slot: Identifiable, Hashable, Codable, Sendable {
    public let id: SlotID; public var exerciseID: ExerciseID
    public var sets: Int /* 1…12 */; public var reps: Int /* 1…30 */; public var repsHi: Int /* 2…40, > reps */
    public var rpe: RPE; public var rest: RestDuration; public var progression: Progression
    public var startLoad: Weight? /* nil → exercise.defaultStartLoad[units] */; public var step: Weight? /* nil → equipment.defaultStep(in:) */
    public var isSupersetWithPrevious: Bool; public var dropSets: Int /* 0 or 1 */; public var misses: Set<Int> /* week indices */
    public init(...) throws   // SlotValidationError with a case per violated range (rule 1–3)
}
public struct Prescription: Hashable, Sendable { public let load: Weight, sets: Int, reps: Int, rpe: RPE, rest: RestDuration, step: Weight, progression: Progression, isHeld: Bool, isDeload: Bool
    public func targetLine(units: Units) -> String /* "5 × 5 @ 185 lb · RPE 8" */ }

public enum WorkoutPhase: String, Codable, Sendable { case live, finished, discarded }
public struct WorkoutSource: Hashable, Codable, Sendable { public let programID: ProgramID; public let weekIndex: Int; public let dayTemplateID: DayTemplateID }
public struct Cursor: Hashable, Codable, Sendable { public var exerciseIndex: Int; public var setIndex: Int }
public struct RestTimer: Hashable, Codable, Sendable { public var endsAt: Date; public var total: Duration; public func remaining(at now: Date) -> Duration; public func fraction(at now: Date) -> Double }
public struct WorkoutState: Identifiable, Hashable, Codable, Sendable {
    public let id: WorkoutID; public var source: WorkoutSource?; public var name: String; public var tag: String; public var isDeload: Bool
    public var exercises: [WorkoutExercise]; public var cursor: Cursor?; public var rest: RestTimer?
    public var startedAt: Date; public var endedAt: Date?; public var phase: WorkoutPhase; public var originDevice: DeviceID
    public var doneSets: Int; public var totalSets: Int; public var volume: Volume; public func elapsed(at now: Date) -> Duration
}
public struct WorkoutExercise: Identifiable, Hashable, Codable, Sendable {
    public let id: WorkoutExerciseID; public var slotID: SlotID?; public var exerciseID: ExerciseID; public let originalExerciseID: ExerciseID
    public var name: String; public var equipment: Equipment; public var step: Weight; public var rest: RestDuration; public var rpe: RPE
    public var isSupersetWithPrevious: Bool; public var targetSets: Int; public var targetReps: Int; public var targetLoad: Weight
    public var sets: [LoggedSet]; public var lastPerformance: LastPerformance?
}
public enum SetKind: String, Codable, Sendable { case working, drop, added, warmup }
public struct LoggedSet: Identifiable, Hashable, Codable, Sendable { public let id: SetID; public var weight: Weight; public var reps: Reps; public var kind: SetKind; public var doneAt: Date?; public var isDone: Bool { doneAt != nil } }
public struct LastPerformance: Hashable, Codable, Sendable { public let date: Date; public let sets: Int; public let reps: Int; public let load: Weight; public func line(units: Units, calendar: Calendar) -> String /* "Aug 12 · 5×5 @ 180 lb" */ }
public struct WorkoutSummary: Hashable, Codable, Sendable { public let workoutID: WorkoutID; public let elapsed: Duration; public let doneSets: Int; public let totalSets: Int; public let volume: Volume; public let prs: [PersonalRecord]; public let rows: [ReceiptRow] }
public struct ReceiptRow: Hashable, Codable, Sendable { public let name: String; public let target: String /* "5 × 5 @ 185 lb" */; public let actual: String /* "5 × 185×5" or "—" (rule 30) */ }
public enum PRKind: Hashable, Codable, Sendable { case estimatedOneRepMax(Weight), weightAtReps(Weight, Reps) }
public struct PersonalRecord: Hashable, Codable, Sendable { public let exerciseID: ExerciseID; public let kind: PRKind; public let previous: PRKind?; public let achievedAt: Date; public let workoutID: WorkoutID }
public struct PlateInventory: Hashable, Codable, Sendable { public var bar: Weight; public var plates: [Weight] /* descending */; public static func standard(_ units: Units) -> PlateInventory /* lb: 45 bar, 45/25/10/5/2.5 · kg: 20 bar, 20/15/10/5/2.5/1.25 */ }
public struct Settings: Hashable, Codable, Sendable {
    public var units: Units; public var defaultRest: RestDuration /* 90 s */; public var plateMathEnabled: Bool; public var autoRest: Bool /* true */
    public var watchBuzz: Bool /* true */; public var weekStart: Weekday; public var plateInventory: [Units: PlateInventory]
    public static let `default`: Settings
}
```

### Pure services (exact rules)
```swift
public enum ProgressionRules {
    /// Spec §7.2. adv = count of i < weekIndex with i ∉ slot.misses. held = (weekIndex − 1) ∈ misses.
    /// deload: load = (load × 0.85).rounded(toStep: step); sets = max(1, sets − 1); rpe = max(5, rpe − 2).
    public static func prescribe(week: Week, weekIndex: Int, slot: Slot, exercise: Exercise, units: Units) -> Prescription
}
public enum SessionBuilder {
    /// Spec §7.3: one WorkoutExercise per slot; sets = p.sets rows {w: p.load, r: p.reps, kind: .working};
    /// dropSets == 1 → append {w: (p.load × 0.85).rounded(toStep: step), r: p.reps, kind: .drop};
    /// lastPerformance from history (nil on first ever session). Cursor starts at (0, 0). phase = .live.
    public static func build(program: Program, weekIndex: Int, day: DayTemplate, exercises: [ExerciseID: Exercise], history: [ExerciseID: LastPerformance], settings: Settings, id: WorkoutID, device: DeviceID, now: Date) throws -> WorkoutState
}
public enum SupersetRounds {
    public struct Block: Hashable, Sendable { public let exerciseIndices: [Int] }              // consecutive exercises joined by isSupersetWithPrevious
    public struct SetRef: Hashable, Sendable { public let exerciseIndex: Int; public let setIndex: Int }
    public static func blocks(in exercises: [WorkoutExercise]) -> [Block]
    public static func displayOrder(block: Block, exercises: [WorkoutExercise]) -> [SetRef]   // round-major A1 B1 A2 B2 …, then drop rows as their own final round
    public static func isLastOfRound(_ ref: SetRef, block: Block, exercises: [WorkoutExercise]) -> Bool
    public static func groupRest(block: Block, exercises: [WorkoutExercise]) -> RestDuration     // max of members
    public static func letter(forMemberAt position: Int) -> String                              // "A"…"E"
}
public enum OneRepMax {
    /// Brzycki: w × 36 / (37 − r). nil when reps > 12 or reps == 37 guard. Result rounded to the nearest gram;
    /// presentation rounds to a whole unit: 195 lb × 5 → 219 lb (the prototype's "218" was illustrative).
    public static func brzycki(weight: Weight, reps: Reps) -> Weight?
}
public enum PersonalRecords {
    /// Decision #3: for each exercise with ≥ 1 done working/added set: new best e1RM (strictly greater) → .estimatedOneRepMax;
    /// new best weight at ≥ the same reps → .weightAtReps. Both may fire; deload workouts never produce PRs.
    public static func detect(workout: WorkoutState, bestE1RM: [ExerciseID: Weight], bestWeightAtReps: [ExerciseID: [Reps: Weight]], now: Date) -> [PersonalRecord]
}
public enum PlateMath {
    public struct Breakdown: Hashable, Sendable { public let perSide: [(plate: Weight, count: Int)]; public func line(units: Units) -> String /* "45 + 2×10 + 2.5 / side" */ }
    /// Rule 38: perSide = (load − bar) / 2; nil if perSide < smallest plate; greedy descending.
    public static func perSide(load: Weight, inventory: PlateInventory) -> Breakdown?
}
public enum TimeEstimate {
    /// Decision #14: Σ over slots of (sets + dropSets) × 42 s + rest, where a superset block counts one rest per round (max of members). Rounded to whole minutes.
    public static func minutes(day: DayTemplate, prescriptions: [SlotID: Prescription]) -> Int
}
public struct WeekCalendar: Sendable {
    public init(startDate: Date, weekStart: Weekday, calendar: Calendar)
    public func weekIndex(for date: Date) -> Int                   // may exceed program.weeks.count − 1 → block ended
    public func bounds(ofWeek index: Int) -> Range<Date>
    public func weekday(of date: Date) -> Weekday
    public func isoWeekKey(for date: Date) -> WeekKey                // struct WeekKey: Hashable, Comparable { year, week }
    public func previousCompleteWeek(before date: Date) -> Range<Date>
}
public enum MissTracking {
    /// Decision #5: missed if any .working set is not done or has reps < targetReps, or fewer done .working sets than targetSets.
    /// .drop/.added never count. isDeload → slot unchanged. Returns the slot with misses updated (insert or remove weekIndex).
    public static func update(slot: Slot, exercise: WorkoutExercise, weekIndex: Int, isDeload: Bool) -> Slot
}
```

### Protocols (implemented in F05 / F16 / F17 / F19)
```swift
public protocol ExerciseRepository: Sendable {
    func all() async throws -> [Exercise]; func exercise(id: ExerciseID) async throws -> Exercise?
    func search(_ query: String, equipment: Equipment?, muscle: MuscleGroup?) async throws -> [Exercise]
    func save(_ exercise: Exercise) async throws; func seedIfNeeded(_ catalog: [Exercise], version: Int) async throws
    func observeAll() -> AsyncStream<[Exercise]>
}
public protocol ProgramRepository: Sendable { func active() async throws -> Program?; func save(_ program: Program) async throws; func setActive(_ id: ProgramID) async throws; func delete(_ id: ProgramID) async throws; func observeActive() -> AsyncStream<Program?> }
public protocol WorkoutRepository: Sendable {
    func materialize(_ workout: WorkoutState, summary: WorkoutSummary, prs: [PersonalRecord], slotUpdates: [Slot]) async throws
    func workout(id: WorkoutID) async throws -> WorkoutState?; func recent(limit: Int) async throws -> [WorkoutState]
    func workouts(in range: Range<Date>) async throws -> [WorkoutState]; func updateSets(workoutExerciseID: WorkoutExerciseID, sets: [LoggedSet]) async throws
    func delete(id: WorkoutID) async throws; func observeRecent(limit: Int) -> AsyncStream<[WorkoutState]>
}
public protocol WorkoutEventStore: Sendable {   // EventEnvelope is defined in F04; this protocol is declared in F04 too — F02 reserves the name only
}
public protocol SettingsRepository: Sendable { func load() async throws -> Settings; func save(_ settings: Settings) async throws; func observe() -> AsyncStream<Settings> }
public protocol StatsQueries: Sendable {
    func lastPerformance(exerciseID: ExerciseID) async throws -> LastPerformance?
    func bestSet(exerciseID: ExerciseID) async throws -> (weight: Weight, reps: Reps)?
    func bestE1RM(exerciseID: ExerciseID) async throws -> Weight?
    func e1RMByWeek(exerciseID: ExerciseID, lastWeeks: Int, calendar: WeekCalendar) async throws -> [WeekKey: Weight]
    func weeklyVolume(in range: Range<Date>) async throws -> Volume
    func sessionsCompleted(in range: Range<Date>) async throws -> Int
    func sessionCount(exerciseID: ExerciseID) async throws -> Int
    func personalRecords(exerciseID: ExerciseID) async throws -> [PersonalRecord]
    func recentlyLogged(limit: Int) async throws -> [ExerciseID]
}
public protocol HealthStore: Sendable { /* shape only; full contract in F16 */ }
public protocol LiveWorkoutTransport: Sendable { /* shape only; full contract in F17 */ }
public protocol CompanionTransport: Sendable { /* shape only; full contract in F19 */ }
```

## Acceptance criteria
1. Given `Weight.pounds(185)`, when converted, then `grams == 83915` and `formatted(in: .lb) == "185"`, `.kg` → `"83.9"`.
2. Given `Weight.pounds(242.25).rounded(toStep: .pounds(5))`, then result is 240 lb; `.pounds(242.5)` → 245 lb (away from zero on ties).
3. Given the Incline DB slot (reps 10, repsHi 12, step 2.5 lb, start 50 lb, double), when prescribed for weeks 0…3 with no misses, then loads/reps are 50×10, 50×11, 50×12, 52.5×10.
4. Given Back Squat (start 250 lb, step 5, linear) at week index 7 with no misses and `isDeload == true`, then load = 240 lb, sets = 4 (from 5), rpe = 6 (from 8).
5. Given a linear slot with `misses == {1}` at week index 3, then `adv == 2`, `load == start + 2·step`, and `isHeld == false`; at week index 2, `isHeld == true`.
6. Given `PlateMath.perSide(load: 185 lb, inventory: .standard(.lb))`, then line is `"45 + 25 / side"`; 180 → `"45 + 2×10 + 2.5 / side"`; 250 → `"2×45 + 10 + 2.5 / side"`; 47.5 → `nil`.
7. Given `OneRepMax.brzycki(195 lb, 5)`, then presentation value is 219 lb; reps 13 → `nil`.
8. Given a superset block of two exercises with 3 sets each plus one drop set on the first, then `displayOrder` is A1 B1 A2 B2 A3 B3 AD and `isLastOfRound` is true only for B1, B2, B3, AD.
9. Given a day of 5 straight slots (5×5 rest 150; 3×10 rest 90; 4×8 rest 90; 3×12 rest 75; 3×15 rest 60), then `TimeEstimate.minutes` is the spec value computed by the formula (state it in the test) and a superset of two 3-set slots with rest 90/60 counts 3 rests of 90 s.
10. Given a `WeekCalendar(startDate: 2026-08-17 (Mon), weekStart: .monday)`, then 2026-08-19 → week 0, Wednesday; 2026-09-14 → week 4; `previousCompleteWeek(before: 2026-09-16)` is Sep 7–14.
11. Given a workout where set 2 of a 5-set working slot was logged with 4 reps (target 5), then `MissTracking.update` inserts the week; given the same with `isDeload`, the slot is unchanged; a missed drop set alone does not insert.
12. Given a finished workout with a 200 lb × 5 bench when best e1RM was 219 lb, then `PersonalRecords.detect` returns `.estimatedOneRepMax` (200×5 → 225 lb) and `.weightAtReps` if 200 lb at ≥ 5 reps is a new best.
13. Given any invalid range (sets 13, reps 0, repsHi ≤ reps, rpe 4.75, rest 100), when constructing a `Slot`, then the matching `SlotValidationError` case is thrown.
14. Given the module, when `swift build` runs, then `LedgerDomain` has no imports other than Foundation (asserted by `scripts/check-package-graph.sh` plus a grep test).

## Test plan
- Unit (LedgerDomainTests, Swift Testing, parameterized): `WeightTests` (conversion, rounding ties, formatting, arithmetic, Codable round-trip), `RepsRPERestTests` (bounds, labels), `VolumeTests`, `SlotValidationTests` (every range), `ProgressionRulesTests` (criteria 3–5 + fixed + double range exhaustion + deload rounding to 2.5 kg steps), `SessionBuilderTests` (rows, drop row, first-session nil history, cursor), `SupersetRoundsTests` (criterion 8, three-member block, no-superset passthrough), `OneRepMaxTests`, `PersonalRecordsTests` (criterion 12, no PR on deload, ties are not PRs), `PlateMathTests` (criterion 6, kg cases 60 kg → "20 / side", 62.5 → "20 + 1.25 / side"), `TimeEstimateTests`, `WeekCalendarTests` (criterion 10, Sunday week start, DST week), `MissTrackingTests` (criterion 11), `ReceiptRowTests` (rule 30 grouping), `LastPerformanceLineTests`.
- Property-style (`.tags(.property)`): `Weight` round-trip lb→g→lb is identity at 0.5 lb resolution; `rounded(toStep:)` is idempotent; `displayOrder` is a permutation of all set refs.
- Snapshot / UI: none.

## Non-functional
- Every type `Sendable`; no classes. `Decimal` for unit math, `Int` grams storage.
- No `Date()` / `UUID()` calls inside rules; all inputs explicit.

## Risks / unknowns
- `Duration` Codable support — encode as seconds `Int64` via a custom coding wrapper if needed.
- Brzycki expected value: the spec's sample said 218; decision #4 chooses the formula, so tests assert 219. Record this in `implementation-notes.md`.

## Definition of Done
Inherits `docs/engineering-standards.md` §12, plus:
- [ ] `LedgerDomain` coverage ≥ 95 % in the PR coverage table.
- [ ] Public API has doc comments stating the spec rule number each function implements.

---
_Filled in by agents during delivery:_
- `F02-domain-core/implementation-notes.md`
- `F02-domain-core/test-findings.md`
- `F02-domain-core/review.md`
