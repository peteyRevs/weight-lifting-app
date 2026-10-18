import Dependencies
@testable import FeatureOnboarding
import Foundation
import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// One onboarding store over probed in-memory stores, with the part of the root a host test stands in for: the
/// task that runs `save` once for each new attempt, and the `prepareRetry` step it is given.
final class AdversarialScene {
    /// What the scene is built on. `Fixtures`' date, calendar and locale unless a test passes its own.
    struct Setup {
        var seed: InMemoryStores.Seed
        var now = Fixtures.now
        var calendar = Fixtures.calendar
        var locale = Fixtures.locale
        var logger = LedgerLogger.disabled

        /// The bundled catalog and `settings`.
        static func seeded(_ settings: Settings = .default) throws -> Setup {
            try Setup(seed: InMemoryStores.Seed(catalog: ExerciseCatalog.seed(), settings: settings))
        }

        /// A first launch whose catalog was never seeded (product decision #28).
        static let unseeded = Setup(seed: .empty)
    }

    let stores: InMemoryStores
    let programs: ProbedPrograms
    let settings: ProbedSettings
    let exercises: ProbedExercises
    let journal: Journal
    let ids: DrawnIDs
    let store: OnboardingStore
    let now: Date
    let calendar: Calendar
    /// What the retry step does, between the journal's `prepare.start` and `prepare.end`.
    var onPrepare: @MainActor () async -> Void = {}

    init(_ setup: Setup) {
        let moment = setup.now
        let memory = InMemoryStores(seed: setup.seed, now: { moment })
        let notes = Journal()
        let drawn = DrawnIDs()
        let probedPrograms = ProbedPrograms(memory.programs, notes)
        let probedSettings = ProbedSettings(memory.settings, notes)
        let probedExercises = ProbedExercises(memory.exercises, notes)
        // Only what the store declares is bound: any other key it read would fail the test, naming the key.
        store = withTestDependencies {
            $0.date = .constant(moment)
            $0.calendar = setup.calendar
            $0.locale = setup.locale
            $0.logger = setup.logger
            $0.uuid = drawn.generator
            $0.programRepository = probedPrograms
            $0.settingsRepository = probedSettings
            $0.exerciseRepository = probedExercises
        } operation: {
            OnboardingStore()
        }
        stores = memory
        programs = probedPrograms
        settings = probedSettings
        exercises = probedExercises
        journal = notes
        ids = drawn
        now = moment
        calendar = setup.calendar
    }

    /// The retry step the root would be given.
    func prepareRetry() async {
        journal.note("prepare.start")
        await onPrepare()
        journal.note("prepare.end")
    }

    /// What the root's task does: one call of `save`.
    func runSave() async {
        await store.save(prepareRetry: { [self] in await prepareRetry() })
    }

    /// A tap, then the root's task if the tap made a new attempt (`.task(id:)` runs again only then).
    func tap(_ action: OnboardingAction) async {
        let before = store.attempt
        store.send(action)
        if store.attempt != before {
            await runSave()
        }
    }

    /// Walks to step 3 with `goal` and `days` picked, as a lifter would.
    func walk(goal: TrainingGoal, days: DaysPerWeek) {
        store.send(.pickGoal(goal))
        store.send(.advance)
        store.send(.pickDays(days))
        store.send(.advance)
    }

    /// The block the Domain's generator writes for `goal` and `days` from what is stored and injected now, given
    /// the ids `saved` was written with: its own id, and the injected generator's from its first week's onward.
    func expectedProgram(goal: TrainingGoal, days: DaysPerWeek, idsOf saved: Program) async throws -> Program {
        let stored = try await stores.settings.load()
        let catalog = try await stores.exercises.all()
        let start = try #require(
            ProgramTemplates.startDate(containing: now, weekStart: stored.weekStart, calendar: calendar)
        )
        let drawn = ids.all
        let firstWeek = try #require(saved.weeks.first?.id.rawValue)
        let index = try #require(drawn.firstIndex(of: firstWeek), "the first week's id is not the generator's")
        var rest = drawn[index...].makeIterator()
        return try ProgramTemplates.program(
            ProgramTemplates.Request(goal: goal, days: days, units: stored.units, startDate: start),
            catalog: catalog,
            id: saved.id,
            newID: { rest.next() ?? Fixtures.uuid(0) }
        )
    }

    /// Exactly one program is stored (of `offered` handed to the store: more than one only after a refused
    /// save), it is the active one, and it is the generator's for `goal` and `days`, with ids from the injected
    /// generator only.
    func expectOneProgram(
        goal: TrainingGoal,
        days: DaysPerWeek,
        offered: Int = 1,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        #expect(programs.offered.count == offered, "programs handed to save", sourceLocation: sourceLocation)
        let saved = try #require(programs.saved.first, "nothing was saved", sourceLocation: sourceLocation)
        #expect(programs.saved.count == 1, sourceLocation: sourceLocation)
        let active = try await stores.programs.active()
        #expect(active == saved, "the saved program is the active one", sourceLocation: sourceLocation)
        #expect(saved.isActive, sourceLocation: sourceLocation)
        let expected = try await expectedProgram(goal: goal, days: days, idsOf: saved)
        #expect(saved == expected, sourceLocation: sourceLocation)
        #expect(
            ids.all.contains(saved.id.rawValue),
            "the program's id is the generator's",
            sourceLocation: sourceLocation
        )
        #expect(journal.count(of: "programs.setActive") == 0, sourceLocation: sourceLocation)
        #expect(journal.count(of: "programs.delete") == 0, sourceLocation: sourceLocation)
        #expect(
            journal.count(of: "settings.save") == 0,
            "onboarding writes no settings",
            sourceLocation: sourceLocation
        )
    }
}

/// The texts of the brief's "Copy (exact)" and of the S2 criteria, typed here from the brief.
nonisolated enum BriefCopy {
    /// One option of step 1: its goal, its label and the line under it.
    struct GoalOption: Sendable {
        let goal: TrainingGoal
        let title: String
        let detail: String
    }

    /// One option of step 2.
    struct DaysOption: Sendable {
        let days: DaysPerWeek
        let title: String
        let detail: String
    }

    static let goalTitle = "What are you training for?"
    static let goalBody = "This sets how your loads progress week to week."
    static let goals = [
        GoalOption(goal: .strength, title: "Get stronger", detail: "Low reps, linear load increases"),
        GoalOption(goal: .hypertrophy, title: "Build muscle", detail: "Moderate reps, volume tracking"),
        GoalOption(goal: .both, title: "Both, honestly", detail: "Barbell strength + accessory volume"),
        GoalOption(goal: .consistency, title: "Stay consistent", detail: "Habit first, numbers second")
    ]
    static let daysTitle = "How many days a week?"
    static let daysBody = "Pick the number you will actually hit, not the one you want to hit."
    static let days = [
        DaysOption(days: .three, title: "3 days", detail: "Full body each session"),
        DaysOption(days: .four, title: "4 days", detail: "Upper / lower split"),
        DaysOption(days: .five, title: "5 days", detail: "Push, pull, legs + accessories"),
        DaysOption(days: .six, title: "6 days", detail: "Body-part split")
    ]
    static let programTitle = "Your program"
    static let programNames: [DaysPerWeek: String] = [
        .three: "Full Body", .four: "Upper / Lower", .five: "Push / Pull / Legs", .six: "Body-Part Split"
    ]
    static let continueTitle = "Continue"
    static let startTraining = "Start training"
    static let skipSetup = "Skip setup"
    static let back = "Back"
    static let retry = "Retry"
    static let saveFailed = "Couldn't save your program. Try again."

    static func unit(_ units: Units) -> String {
        units == .kg ? "kilograms" : "pounds"
    }

    /// "{program name}, 8 weeks, {pounds|kilograms}. Editable any time."
    static func programBody(_ days: DaysPerWeek, _ units: Units) -> String {
        "\(programNames[days] ?? "?"), 8 weeks, \(unit(units)). Editable any time."
    }

    static func step(_ number: Int) -> String {
        "Step \(number) of 3"
    }

    /// Step 3's rows for a split, from the Domain's own data: the name with " — " drawn as " · ", and its line.
    static func dayRows(_ days: DaysPerWeek) -> [(title: String, detail: String)] {
        ProgramTemplates.preview(days: days).days.map {
            ($0.name.replacingOccurrences(of: " — ", with: " · "), $0.line)
        }
    }

    /// The four-day rows as the brief and spec §6.7 spell them.
    static let fourDayRows: [(title: String, detail: String)] = [
        ("Upper A · Push focus", "Bench, incline, row, pulldown, laterals"),
        ("Lower A · Squat focus", "Squat, RDL, leg press, calves"),
        ("Upper B · Pull focus", "Weighted pull-up, OHP, row, curls"),
        ("Lower B · Hinge focus", "Deadlift, front squat, leg curl")
    ]
}
