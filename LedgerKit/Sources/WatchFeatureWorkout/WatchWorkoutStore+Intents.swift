import Foundation
import LedgerDomain

/// A tap on the watch's workout, as the screens send it (spec §5.2 as F18 binds it).
nonisolated enum WatchAction: Equatable, Sendable {
    /// "Start" on the screen before a workout: today's session. "−" / "+" on the reps.
    case start, stepReps(StepDirection)
    /// The crown's `onChange` and `onIdle`; "Done set"; the rest's "+30s" and "Skip".
    case crownRotated(Double), crownRested, logSet, extendRest, skipRest
    /// The exercise's name, the list's back and a row; "End workout" and the end overlay's buttons; summary's "Done".
    case openList, closeList, selectExercise(Int), openEnd, keepLifting, save, dismissSummary
    /// "Discard". The end overlay offers it only while no set is logged, and the pump discards only a workout that
    /// still has none when the discard's turn comes (`WatchEndModel.offersDiscard(loggedSetCount:)`).
    case discard
}

/// A tap that changes the workout, as it waits for the pump: what it names is fixed when it is made, and what it
/// sends is planned at its turn on the newest workout (`events(_:in:)`).
nonisolated enum WatchCommand: Equatable, Sendable {
    case start, skipRest, selectExercise(Int), stepReps(CrownWeightModel.Target, StepDirection)
    case commitWeight(CrownWeightModel.Commit), logSet(CrownWeightModel.Target, doneAt: Date),
         extendRest(tappedAt: Date)
    case save(endedAt: Date), discard(endedAt: Date)
}

extension WatchWorkoutStore {
    func send(_ action: WatchAction) {
        switch action {
        case .start:
            // A second tap waits behind the first, which finds the workout live (or resumes it) and starts nothing.
            if case let .plan(plan)? = idle, plan.start != nil, mode == .idle {
                enqueue(.start)
            }
        case let .stepReps(direction):
            crown.reading.map { enqueue(.stepReps($0.target, direction)) }
        case let .crownRotated(value):
            crown.rotate(to: value)
        case .crownRested:
            crown.rotationEnded().map { enqueue(.commitWeight($0)) }
        case .logSet:
            logSet()
        case .extendRest:
            enqueue(.extendRest(tappedAt: date.now))
        case .skipRest:
            enqueue(.skipRest)
        default:
            answerOverlay(action)
        }
    }

    /// The list, the end overlay and the summary's "Done".
    private func answerOverlay(_ action: WatchAction) {
        switch action {
        case .openList, .keepLifting:
            overlay = mode.isLive ? .list : overlay
        case .closeList:
            overlay = overlay == .list ? nil : overlay
        case let .selectExercise(index):
            overlay = nil
            enqueue(.selectExercise(index))
        case .openEnd:
            overlay = mode.isLive ? .end : overlay
        case .save where end?.canSave == true:
            enqueue(.save(endedAt: date.now))
        case .discard:
            enqueue(.discard(endedAt: date.now))
        case .dismissSummary:
            isSummaryDismissed = mode == .summary || isSummaryDismissed
        default:
            break
        }
    }

    /// "Done set" logs the shown set as it reads: a turn not yet at rest is committed first, at the weight on screen.
    private func logSet() {
        guard let reading = crown.reading else {
            return
        }
        hasAskedForHealth = hasAskedForHealth || health == .denied
        if crown.isRotating, let commit = crown.rotationEnded() {
            enqueue(.commitWeight(commit))
        }
        enqueue(.logSet(reading.target, doneAt: date.now))
    }

    func enqueue(_ command: WatchCommand) {
        queue.append(command)
        wake?.yield()
    }

    func pump() async {
        let (signals, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        wake = continuation
        continuation.yield()
        for await _ in signals {
            await drain()
        }
    }

    /// Applies every waiting tap, oldest first, while the session is heard. A change the session refuses drops the
    /// taps behind it, as the phone's pump does: they were made on a screen that never came to be.
    func drain() async {
        guard !isDraining else {
            return
        }
        isDraining = true
        defer { isDraining = false }
        while let command = queue.first, hasHeardSession {
            if await perform(command) {
                queue.removeFirst()
            } else {
                queue = []
            }
        }
    }

    /// Performs one tap; false when the session refused it. A workout ended by another hand is no refusal.
    private func perform(_ command: WatchCommand) async -> Bool {
        do {
            switch command {
            case .start:
                try await start()
            case let .save(endedAt):
                _ = try await session.finish(endedAt: endedAt)
            case let .discard(endedAt):
                try await discard(endedAt: endedAt)
            default:
                guard let shown = ahead ?? live else {
                    return true
                }
                for event in Self.events(command, in: shown) {
                    let answer = try await session.apply(event)
                    ahead = answer == workout ? nil : answer
                }
            }
            return true
        } catch {
            ahead = nil
            if case WorkoutSessionError.noLiveWorkout = error {
                return true
            }
            logger.log.error("The watch's change was refused: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// "Discard", on the session's newest workout: refused, and the end overlay left up to show "Save workout", once a
    /// set is logged there, whoever logged it since the overlay was drawn. No workout is nothing to discard.
    private func discard(endedAt: Date) async throws {
        guard let newest = try await session.current() else {
            return
        }
        guard WatchEndModel.offersDiscard(loggedSetCount: newest.doneSets) else {
            logger.log.notice("Discard refused: the workout has \(newest.doneSets, privacy: .public) sets logged")
            return
        }
        try await session.discard(endedAt: endedAt)
    }

    /// "Start": today's session of the active program (`WatchTodayStart`). A workout that is live by the time it
    /// runs (the phone's start won) is the one the stream shows, and nothing is started over it.
    private func start() async throws {
        guard workout?.phase != .live else {
            return
        }
        let today = WatchTodayStart(
            session: session, programs: programs, exercises: exerciseRepository, stats: stats,
            settings: settingsRepository, device: device, calendar: calendar, now: { [date] in date.now },
            newID: { [uuid] in uuid() }, logger: logger
        )
        try await today.start()
    }

    /// What `command` sends on `state`, as the phone's `WorkoutEditPlan` plans it: nothing for a set gone or logged (a
    /// second "Done set" logs nothing), reps by one and never under one, the rest panel's "+30s" and "Skip" (decision
    /// #7), and a selected exercise's first set not logged, in round order in a superset.
    nonisolated static func events(_ command: WatchCommand, in state: WorkoutState) -> [WorkoutEvent] {
        switch command {
        case let .stepReps(target, direction):
            let reps = openSet(target, in: state)
                .map { Reps(clamping: $0.reps.value + (direction == .upward ? 1 : -1)) }
            return reps == openSet(target, in: state)?.reps ? [] : [.setTargetChanged(
                exerciseIndex: target.exerciseIndex, setID: target.setID, weight: nil, reps: reps
            )]
        case let .commitWeight(commit):
            let weight = openSet(commit.target, in: state)?.weight
            return weight == nil || weight == commit.weight ? [] : [.setTargetChanged(
                exerciseIndex: commit.target.exerciseIndex, setID: commit.target.setID, weight: commit.weight, reps: nil
            )]
        case let .logSet(target, doneAt):
            return openSet(target, in: state).map { set in [.setLogged(
                exerciseIndex: target.exerciseIndex, setID: set.id, weight: set.weight, reps: set.reps, doneAt: doneAt
            )] } ?? []
        case let .extendRest(tappedAt):
            return state.shownRest.map { shown in [.restExtended(
                amount: .seconds(30), extendsShownRest: shown.remaining(at: tappedAt) > .zero, tappedAt: tappedAt
            )] } ?? []
        case .skipRest:
            return state.shownRest == nil ? [] : [.restSkipped]
        case let .selectExercise(index):
            return firstOpenSet(of: index, in: state).map { [.exerciseSelected(exerciseIndex: index, setIndex: $0)] }
                ?? []
        case .start, .save, .discard:
            return []
        }
    }

    private nonisolated static func openSet(_ target: CrownWeightModel.Target, in state: WorkoutState) -> LoggedSet? {
        guard state.exercises.indices.contains(target.exerciseIndex) else {
            return nil
        }
        return state.exercises[target.exerciseIndex].sets.first { $0.id == target.setID && !$0.isDone }
    }

    private nonisolated static func firstOpenSet(of index: Int, in state: WorkoutState) -> Int? {
        guard state.exercises.indices.contains(index) else {
            return nil
        }
        let sets = state.exercises[index].sets
        let block = SupersetRounds.blocks(in: state.exercises).first { $0.exerciseIndices.contains(index) }
        let order = block.map { block in
            SupersetRounds.displayOrder(block: block, exercises: state.exercises)
                .filter { $0.exerciseIndex == index }.map(\.setIndex)
        } ?? Array(sets.indices)
        return order.first { !sets[$0].isDone }
    }
}
