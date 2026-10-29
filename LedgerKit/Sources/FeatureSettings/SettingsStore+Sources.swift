import Foundation
import LedgerDomain

/// What `SettingsStore` does while `SettingsRoot`'s task runs (F14 S1, N1, N2): it follows the stored settings and
/// saves the lifter's changes, in one task group, so nothing outlives the screen.
///
/// Each kind of work waits on a channel that keeps only the newest mark: a change marks the saver, which saves
/// what is pending until nothing is, so changes made during a save are folded into the next one. The follower is
/// marked at the start of the run and each time the saver goes idle after writing or failing: it then ends the
/// observation it was following and starts a new one, whose first value is the row as it is now (F14-S1a-R1-1).
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

    /// Starts an observation of the settings each time it is marked: at the start of the run, and each time the saver
    /// goes idle after writing or failing (F14-S1a-R1-1), which also follows the settings again after they could not
    /// be read (N2). Each new observation retires the one before (F14-S1a-R2-1): the old one is cancelled at once,
    /// which ends its stream, so at most two are open, and only while one hands over to the next. Every observation
    /// is a child of this task, so cancelling the run cancels them all.
    private func follow(_ marks: AsyncStream<Void>) async {
        await withTaskGroup(of: Void.self) { group in
            for await _ in marks {
                retireObservation?.finish()
                observationNumber += 1
                let number = observationNumber
                let (retired, retire) = AsyncStream<Void>.makeStream()
                retireObservation = retire
                group.addTask { await self.observe(number, until: retired) }
            }
        }
    }

    /// Runs the observation numbered `number` until it ends by itself or `retired` finishes, whichever comes first,
    /// and then cancels the other. The group is this one observation's alone and ends here, so cancelling all of it
    /// cancels nothing else; the follower's own group is never cancelled (every task added to a cancelled group
    /// starts cancelled).
    private func observe(_ number: Int, until retired: AsyncStream<Void>) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.observe(number) }
            group.addTask {
                for await _ in retired {}
            }
            await group.next()
            group.cancelAll()
        }
    }

    /// Receives the values of the observation numbered `number` while it is the follower's latest. One that ends by
    /// itself could not read the row: the screen keeps what it had, or the defaults.
    ///
    /// Its first value is the row read afresh only when no save has returned since it started: one that has may have
    /// committed after the observation's first read, which is then older than the row.
    private func observe(_ number: Int) async {
        let writesBefore = writes
        var isFirst = true
        for await value in settings.observe() {
            guard !Task.isCancelled, number == observationNumber else {
                return
            }
            receive(value, readsTheRowAfresh: isFirst && writes == writesBefore)
            isFirst = false
        }
        guard !Task.isCancelled, number == observationNumber else {
            return
        }
        // Logged here, once, and not by each change then drawn over the defaults.
        logger.log.error("The settings could not be read: Settings shows what it last had, or the defaults")
        isUnreadable = true
        stored = stored ?? .default
        show()
    }

    /// A value of the observation. An observation's first value read after every save of this store returned
    /// (`readsTheRowAfresh`) is the row as it is now: when no save is running, it is what is committed, whatever is
    /// pending, and the store forgets what it wrote (F14-S1a-R2-3). Any later value (an echo of a save, or a change
    /// made elsewhere) is the stored one, and is drawn only while the store has written nothing since the row was
    /// last read afresh.
    private func receive(_ value: Settings, readsTheRowAfresh: Bool) {
        stored = value
        isUnreadable = false
        if readsTheRowAfresh, !isSaving {
            written = nil
        }
        show()
    }

    /// Saves the pending change, then the one made during that save, until what is pending is committed. Only one
    /// save runs at a time, whichever run started it, and a run whose task is cancelled starts no further save.
    ///
    /// A failure puts the screen back to what is committed and drops every pending change, the ones made during the
    /// failed save too (F14-S1-1, ruled), with the failure's line. Once idle after writing or failing, the saver has
    /// the row read afresh.
    private func savePending() async {
        guard !isSaving else {
            return
        }
        isSaving = true
        var hasWrittenOrFailed = false
        defer {
            isSaving = false
            if pending != nil, pending != committed {
                // Left by a run cancelled between saves: the current run's saver takes it.
                saveMark?.yield()
            } else if hasWrittenOrFailed {
                followMark?.yield()
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
                hasWrittenOrFailed = true
                show()
                return
            }
            written = wanted
            writes += 1
            hasWrittenOrFailed = true
        }
        if let wanted = pending, wanted == committed {
            // Written: the screen shows what is committed, which is the lifter's value.
            pending = nil
        }
    }
}
