import Foundation
import LedgerDomain

/// What `SettingsStore` does while `SettingsRoot`'s task runs (F14 S1, N1, N2): it follows the stored settings and
/// saves the lifter's changes, in one task group, so nothing outlives the screen.
///
/// Each kind of work waits on a channel that keeps only the newest mark: a change marks the saver, which saves
/// what is pending until nothing is, so changes made during a save are folded into the next one; the end of the
/// observation, then a save, marks the follower, which follows the settings again.
extension SettingsStore {
    func run() async {
        let (saves, saveMark) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let (follows, followMark) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.saveMark = saveMark
        self.followMark = followMark
        followMark.yield()
        if pending != nil {
            // A change made while no run was on.
            saveMark.yield()
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.follow(follows) }
            for await _ in saves {
                await savePending()
            }
        }
        self.saveMark = nil
        self.followMark = nil
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

    /// A value of the observation: the stored settings, and the end of the change that wrote it.
    private func receive(_ value: Settings) {
        stored = value
        isUnreadable = false
        if value == pending {
            pending = nil
            written = nil
        }
        show()
    }

    /// Saves the pending change, then the one made during that save, until the last one written is the one
    /// pending. A failure drops every pending change and shows the stored settings with the failure's line.
    private func savePending() async {
        while let wanted = pending, wanted != written {
            do {
                try await settings.save(wanted)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                logger.log.error("A change to the settings was not saved: \(String(describing: error))")
                pending = nil
                written = nil
                saveFailed = true
                show()
                return
            }
            written = wanted
        }
        // Here what is pending, if anything, is what was written last.
        guard pending != nil else {
            // The observation gave it back while it was being saved.
            written = nil
            return
        }
        if isUnreadable {
            // The row is readable again: the follower's new observation gives the saved value back.
            followMark?.yield()
        } else if pending == stored {
            // A save that changed nothing stored, which the observation gives nothing back for.
            pending = nil
            written = nil
        }
    }
}
