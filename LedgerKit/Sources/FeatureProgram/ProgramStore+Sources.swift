import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain

/// What `ProgramStore` follows (F11 S13, criteria 7 to 9): the active program, the settings, the exercises
/// and the newest finished workout, in one task group for as long as `ProgramRoot`'s task runs, and the
/// weeks that hold a finished workout, read again on every run, whenever the program's block or the newest
/// workout changes, and before a write that removes the last week.
///
/// The model is made once every source has spoken and the logged weeks are read; what they said is kept
/// across runs, so once loaded the builder is never loading again. An observation that ends while its task
/// runs, or a read that fails, is logged and shows the failed state; the next run tries again.
extension ProgramStore {
    /// How many finished workouts are followed: a workout finished meanwhile is the newest.
    static let followedWorkouts = 1

    func run() async {
        hasFailed = false
        let (marks, mark) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.followProgram(mark) }
            group.addTask { await self.followSettings() }
            group.addTask { await self.followExercises() }
            group.addTask { await self.followRecentWorkouts(mark) }
            for await _ in marks {
                await refreshLoggedWeeks()
            }
        }
    }

    /// The weeks of `program` that hold a finished workout of it, by their place in the block. Every week of
    /// the block is read, from a week before its first day (a workout started before midnight in another
    /// zone) on, so the set is right whichever week is last.
    func readLoggedWeeks(of program: Program) async throws -> Set<Int> {
        // A program week is counted from the block's first day whatever the week start; any one will do.
        let weeks = WeekCalendar(startDate: program.startDate, weekStart: .monday, calendar: calendar)
        let finished = try await workouts.workouts(in: weeks.bounds(ofWeek: -1).lowerBound ..< .distantFuture)
        return Set(finished.compactMap { $0.source?.programID == program.id ? $0.source?.weekIndex : nil })
    }

    /// Each program the store emits goes to the session. The first selects the week that holds today, unless
    /// a week was asked for; a new block (another program, or another first day) has its weeks read again.
    private func followProgram(_ mark: AsyncStream<Void>.Continuation) async {
        // The block whose weeks were read in this run; nil until the first program.
        var read: Block??
        await follow(programs.observeActive()) { program in
            session.hear(program)
            if selectedWeek == nil, let program {
                let weeks = WeekCalendar(startDate: program.startDate, weekStart: .monday, calendar: calendar)
                select(week: weeks.weekIndex(for: date()))
            }
            let block = program.map { Block(id: $0.id, start: $0.startDate) }
            if read != .some(block) {
                read = .some(block)
                mark.yield()
            }
        }
    }

    private func followSettings() async {
        await follow(settingsRepository.observe()) { settings = $0 }
    }

    private func followExercises() async {
        await follow(exerciseRepository.observeAll()) { all in
            exercises = Dictionary(all.map { ($0.id, $0) }) { first, _ in first }
        }
    }

    private func followRecentWorkouts(_ mark: AsyncStream<Void>.Continuation) async {
        await follow(workouts.observeRecent(limit: Self.followedWorkouts)) { _ in mark.yield() }
    }

    /// Reads the logged weeks of the program the session holds; none without a program.
    private func refreshLoggedWeeks() async {
        guard session.hasHeard else {
            return
        }
        guard let program = session.stored else {
            loggedWeeks = []
            return
        }
        do {
            let read = try await readLoggedWeeks(of: program)
            if !Task.isCancelled {
                loggedWeeks = read
            }
        } catch {
            if !Task.isCancelled {
                logger.log.error("The program's workouts were not read: \(String(describing: error), privacy: .public)")
                hasFailed = true
            }
        }
    }

    /// Hands each value of an observation to `keep`. One that ends while the task still runs has failed.
    private func follow<Value: Sendable>(_ values: AsyncStream<Value>, keep: (Value) -> Void) async {
        for await value in values {
            guard !Task.isCancelled else {
                return
            }
            keep(value)
        }
        if !Task.isCancelled {
            logger.log.error("A store's observation ended while the program was on screen")
            hasFailed = true
        }
    }
}

/// What the logged weeks depend on: which program, and the day its block began.
private nonisolated struct Block: Equatable {
    let id: ProgramID
    let start: CivilDate
}
