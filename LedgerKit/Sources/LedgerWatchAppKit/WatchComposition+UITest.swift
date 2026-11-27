import Dependencies
import Foundation

/// A UI test's watch in the composition (F18 S7, `WatchUITest`): the moved clock the screens follow, and the seed
/// program saved once the launch's pass has run.
extension WatchComposition {
    /// The seconds the app's clock is moved by: a UI test's date (`WatchUITest`), else 0. The screens' timers, which
    /// count by the wall clock, are moved with it.
    var clockOffset: TimeInterval {
        environment.uiTest.clockOffset ?? 0
    }

    /// A UI test's date: the screens' clock (`date`) is the launch's, moved.
    func bindUITestDate(_ values: inout DependencyValues) {
        if environment.uiTest.clockOffset != nil {
            values.date = DateGenerator(environment.now)
        }
    }

    /// The UI test's heart-rate script, for the live-sync group (`WatchUITest.scriptHeartRate`); nil in the app.
    var uiTestHeartRateScript: (@Sendable () async -> Void)? {
        guard let scripted = environment.uiTest.healthStore else {
            return nil
        }
        let (clock, now) = (environment.syncClock, environment.now)
        return { await WatchUITest.scriptHeartRate(of: scripted, clock: clock, now: now) }
    }

    /// A UI test's program (`WatchUITest`, `-LEDGER_UITEST_PROGRAM seed`), as the iPhone's root saves its own: once the
    /// launch's pass has seeded the catalog, the seed program is saved as the active one when there is none. The
    /// screen before a workout observes the program, so it shows the day once saved. Once in a process; a failure is
    /// logged, and the test then finds "No program on watch". A call whose task is cancelled does not count.
    func saveUITestProgramIfAsked() async {
        guard environment.uiTest.seedsProgram, !isUITestProgramDone, !Task.isCancelled, let stores else {
            return
        }
        do {
            try await WatchUITest.saveSeedProgramIfNone(in: stores.programs)
            isUITestProgramDone = true
        } catch {
            guard !Task.isCancelled else {
                return
            }
            isUITestProgramDone = true
            let reason = String(describing: error)
            environment.logger.log.error("The UI test's program was not saved: \(reason, privacy: .public)")
        }
    }
}
