import Foundation
import LedgerDomain

/// What `SettingsStore` does while `SettingsRoot`'s task runs (F14 S1, N1, N2): it follows the stored settings and
/// saves the lifter's changes, in one task group, so nothing outlives the screen.
///
/// Each kind of work waits on a channel that keeps only the newest mark: a change marks the saver, which saves
/// what is pending until nothing is, so changes made during a save are folded into the next one; the end of the
/// observation, then a save, marks the follower, which follows the settings again.
///
/// **One save at a time across runs** (F14-S1-4). The task restarts on the same store (a tab switched away and
/// back): the old run, cancelled, may still be waiting for its save. `isSaving` keeps the new run from starting a
/// second; the old run starts no further save once its task is cancelled, and hands what is left to the current
/// run's saver. A run clears the marks at its end only while they are still its own.
extension SettingsStore {
    func run() async {
        let (saves, saveMark) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let (follows, followMark) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        runNumber += 1
        let number = runNumber
        self.saveMark = saveMark
        self.followMark = followMark
        followMark.yield()
        if pending != nil {
            // A change made while no run was on, or left by a run that ended.
            saveMark.yield()
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.follow(follows) }
            for await _ in saves {
                await savePending()
            }
        }
        if runNumber == number {
            self.saveMark = nil
            self.followMark = nil
        }
    }

    /// Follows the stored settings each time it is marked: at the start of the run, and after a save that follows
    /// an observation that ended.
    private func follow(_ marks: AsyncStream<Void>) async {
        for await _ in marks {
            for await value in settings.observe() {
                guard !Task.isCancelled else {
                    return
                }
                receive(value)
            }
            guard !Task.isCancelled else {
                return
            }
            // Logged here, once, and not by each change then drawn over the defaults.
            logger.log.error("The settings could not be read: Settings shows what it last had, or the defaults")
            isUnreadable = true
            stored = stored ?? .default
            show()
        }
    }

    /// A value of the observation. When it is the echo of a save of this store's, that save and those before it are
    /// echoed; any other value is a change made elsewhere, which is what is committed now.
    private func receive(_ value: Settings) {
        if let echoed = unechoed.firstIndex(of: value) {
            unechoed.removeFirst(echoed + 1)
        } else {
            unechoed = []
        }
        stored = value
        isUnreadable = false
        show()
    }

    /// Saves the pending change, then the one made during that save, until what is pending is committed. Only one
    /// save runs at a time, whichever run started it, and a run whose task is cancelled starts no further save.
    ///
    /// A failure puts the screen back to what is committed and drops every pending change, the ones made during the
    /// failed save too (F14-S1-1, ruled), with the failure's line.
    private func savePending() async {
        guard !isSaving else {
            return
        }
        isSaving = true
        defer {
            isSaving = false
            if pending != nil, pending != committed {
                // Left by a run cancelled between saves: the current run's saver takes it.
                saveMark?.yield()
            }
        }
        while let wanted = pending, wanted != committed, !Task.isCancelled {
            do {
                try await settings.save(wanted)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                logger.log.error("A change to the settings was not saved: \(String(describing: error))")
                pending = nil
                saveFailed = true
                show()
                return
            }
            unechoed.append(wanted)
        }
        guard let wanted = pending, wanted == committed else {
            return
        }
        // Written: the screen shows what is committed, which is the lifter's value.
        pending = nil
        if isUnreadable {
            // The row is readable again: the follower's new observation gives the saved value back.
            followMark?.yield()
        }
    }
}
