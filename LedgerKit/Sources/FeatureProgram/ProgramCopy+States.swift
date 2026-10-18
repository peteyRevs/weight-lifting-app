import Foundation

/// The texts of the builder when it has no program to show, and of a change that was not saved (`ProgramCopy`;
/// standards §7). Pete's decision 6, the default wording.
nonisolated extension ProgramCopy {
    // MARK: No program

    static var noProgramTitle: String {
        String(
            localized: "No program yet",
            bundle: .module,
            comment: "Title shown in place of the Program builder when no program is active"
        )
    }

    static var noProgramBody: String {
        String(
            localized: "Your program appears here once you have set one up.",
            bundle: .module,
            comment: "Under the title shown when no program is active"
        )
    }

    // MARK: When the program cannot be shown

    static var failedTitle: String {
        String(
            localized: "Can't show your program right now",
            bundle: .module,
            comment: "Title shown in place of the Program builder when its data cannot be read"
        )
    }

    static var failedBody: String {
        String(
            localized: "Your workouts are still on this iPhone. Open the app again to try once more.",
            bundle: .module,
            comment: "Under the title shown when the Program builder's data cannot be read"
        )
    }

    // MARK: A change that was not saved

    static var saveFailed: String {
        String(
            localized: "That change wasn't saved. Try again.",
            bundle: .module,
            comment: "Shown under the block when an edit could not be stored; the program is shown as stored"
        )
    }
}
