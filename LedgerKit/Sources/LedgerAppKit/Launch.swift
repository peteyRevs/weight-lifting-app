import Dependencies
import LedgerPersistence
import SwiftUI

/// A step of the iPhone launch (F07 brief, "Launch sequence"; architecture §4), in the order the steps run.
public enum LaunchStep: String, Sendable, CaseIterable {
    /// In `App.init`, synchronously (`boot()`): no `await` can run before these.
    case assignMirroringHandler, openDatabase
    /// After the first frame (`resume(in:)`).
    case seedCatalog, loadSettings, activateCompanionSession
}

/// What the launch records: each step as it begins, and each step that fails (after logging it at fault level).
public enum LaunchEvent: Hashable, Sendable {
    case began(LaunchStep)
    case failed(LaunchStep)
}

extension AppComposition {
    /// The launch's synchronous part, from `App.init`. It is not `async`, so the compiler guarantees that no
    /// `await` runs before the mirroring handler is assigned (ADR-005, criterion 6); the handler goes first so a
    /// launch the watch's mirroring started gets its session even if the database then fails to open.
    func boot() {
        environment.record(.began(.assignMirroringHandler))
        environment.assignMirroringHandler()
        openDatabase()
    }

    /// The launch's asynchronous part, from the root view's `.task(id: scenePhase)`. The first call, in whatever
    /// phase, seeds the catalog, loads the settings and activates WatchConnectivity. Each later call, on return to
    /// the foreground, retries what failed: opening the database (product decision #29), then seeding (#28).
    /// A settings row that cannot be read is not retried: it reads the same until the lifter saves.
    public func resume(in phase: ScenePhase) async {
        guard state != .idle else {
            return
        }
        if hasResumed {
            guard phase == .active else {
                return
            }
            if state == .databaseUnavailable {
                openDatabase()
            }
        }
        hasResumed = true
        if let stores {
            if !isCatalogSeeded {
                await seedCatalog(stores)
            }
            if !hasLoadedSettings {
                await loadSettings(stores)
            }
        }
        if !isCompanionActive {
            environment.record(.began(.activateCompanionSession))
            isCompanionActive = true
            environment.activateCompanionSession()
        }
    }

    /// Opens the database and binds the keys, or shows decision #29's screen. The file is never deleted, moved or
    /// replaced here, whatever the error: a damaged or locked file stays for the next attempt.
    private func openDatabase() {
        environment.record(.began(.openDatabase))
        do {
            stores = try LedgerStores.open(
                at: environment.databaseURL,
                kind: .phone,
                now: environment.now,
                newID: environment.newID
            )
            if environment.preparesDependencies {
                prepareDependencies { bind(&$0) }
            }
            state = .ready
        } catch {
            state = .databaseUnavailable
            fail(.openDatabase, error)
        }
    }

    /// Decision #28: a failure is logged and the launch carries on; the lifter's own data stays readable, and
    /// the seed, rolled back whole with its version unapplied, is retried on the next launch or foreground.
    private func seedCatalog(_ stores: LedgerStores) async {
        environment.record(.began(.seedCatalog))
        do {
            try await stores.seedCatalog()
            isCatalogSeeded = true
        } catch {
            fail(.seedCatalog, error)
        }
    }

    /// A row this app cannot read leaves `settings` at `Settings.default`, in memory only (F05 input).
    private func loadSettings(_ stores: LedgerStores) async {
        environment.record(.began(.loadSettings))
        hasLoadedSettings = true
        do {
            settings = try await stores.settings.load()
        } catch {
            fail(.loadSettings, error)
        }
    }

    private func fail(_ step: LaunchStep, _ error: any Error) {
        environment.logger.log.fault(
            "Launch step \(step.rawValue, privacy: .public) failed: \(String(describing: error))"
        )
        environment.record(.failed(step))
    }
}
