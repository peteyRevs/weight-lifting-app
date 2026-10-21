import LedgerDomain
import SwiftUI

/// Which screen the iPhone's root shows once the database is open (F08): onboarding while there is no active
/// program, the tabs while there is one. `MainRoot` draws `destination`; `AppRoot` runs `follow` from the task
/// that runs the launch. The gate starts no task of its own, so nothing here outlives the view.
///
/// The gate navigates, not onboarding: onboarding's one exit is the active program it saves, which arrives
/// here as the store's next value. A program deleted (Settings' "Delete all data", F14) or added by another
/// route (iCloud, F28) while the app is open arrives the same way.
@MainActor
@Observable
final class RootGate {
    nonisolated enum Destination: Sendable {
        /// No answer yet: the root draws the ground colour and nothing else, so neither screen flashes by.
        case loading
        /// There is no active program.
        case onboarding
        /// There is an active program: the tabs.
        case main
    }

    private(set) var destination = Destination.loading

    /// Awaits `launch`, then follows the active program of the store it returns until the task is cancelled.
    ///
    /// - `launch` runs the launch's asynchronous pass (the seed, the settings, then the live workout's
    ///   recovery) and returns the store of programs, or nil while the database is not open. Nothing is read
    ///   and nothing is decided before it returns: a lifter who taps through onboarding at once must find the
    ///   catalog seeded, or its seed failed and ready to be retried (ruling O12), and the first screen is drawn
    ///   once, with the workout it resumes already known.
    /// - Each value of `ProgramRepository.observeActive()` decides, the current one first: one read, then one
    ///   for each change.
    /// - A stream that ends on a task nobody cancelled is an active program that cannot be read. The root then
    ///   shows the tabs, never onboarding, which would save a second program beside the one that is there.
    /// - A cancelled call changes nothing, not even with a value the store gave before the cancellation and the
    ///   loop had not yet taken. The root starts the call again when the scene's phase changes, and
    ///   `destination` stays what it was until the new call's first value: the screen shown keeps its place in
    ///   the tree, and with it onboarding's step and picks.
    func follow(after launch: @MainActor () async -> (any ProgramRepository)?) async {
        guard let programs = await launch(), !Task.isCancelled else {
            return
        }
        for await program in programs.observeActive() {
            guard !Task.isCancelled else {
                break
            }
            destination = program == nil ? .onboarding : .main
        }
        if !Task.isCancelled {
            destination = .main
        }
    }

    /// `follow(after:)` for the app: `composition`'s launch in `phase`, then, in a UI test that asked for it, the
    /// seed program (`UITestProgram`), then its store of programs.
    func follow(_ composition: AppComposition, in phase: ScenePhase) async {
        await follow {
            await composition.resume(in: phase)
            await composition.saveUITestProgramIfAsked()
            return composition.stores?.programs
        }
    }
}
