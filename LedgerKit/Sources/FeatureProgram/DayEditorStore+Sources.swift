import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain

/// What `DayEditorStore` follows (F11 S14): the active program, the settings and the exercises, in one task
/// group for as long as `DayEditorRoot`'s task runs. Each program the store emits goes to the session, and
/// may tell the editor that its day is gone. An observation that ends while its task runs is logged and shows
/// the failed state until the next run.
extension DayEditorStore {
    /// Follows the active program, the settings and the exercises for as long as the root's task runs.
    func run() async {
        hasEndedInThisRun = false
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.followProgram() }
            group.addTask { await self.followSettings() }
            group.addTask { await self.followExercises() }
        }
    }

    private func followProgram() async {
        await follow(programs.observeActive()) { program in
            session.hear(program)
            if !hasEndedInThisRun {
                hasEnded = false
            }
            closeIfDone()
        }
    }

    private func followSettings() async {
        await follow(settingsRepository.observe()) { settings = $0 }
    }

    private func followExercises() async {
        await follow(exerciseRepository.observeAll()) { all in
            exercises = all
            exercisesByID = Dictionary(all.map { ($0.id, $0) }) { first, _ in first }
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
            logger.log.error("A store's observation ended while a day was being edited")
            hasEnded = true
            hasEndedInThisRun = true
        }
    }
}
