import Dependencies
import LedgerPersistence
import SwiftUI

/// A step of the watch launch (F07 brief, "Launch sequence"; architecture §4), in the order the steps run. The
/// watch is the primary workout session (ADR-005), so it assigns no mirroring handler.
public enum LaunchStep: String, Sendable, CaseIterable {
    /// In `App.init`, synchronously (`boot()`).
    case openDatabase
    /// After the first frame (`resume(in:)`).
    case seedCatalog, loadSettings, activateCompanionSession
}

/// What the launch records: each step as it begins, and each step that fails (after logging it at fault level).
public enum LaunchEvent: Hashable, Sendable {
    case began(LaunchStep)
    case failed(LaunchStep)
}

extension WatchComposition {
    /// The launch's synchronous part, from `App.init`: the database is open before the first frame.
    func boot() {
        openDatabase()
    }

    /// The launch's asynchronous part, from the root view's `.task(id: scenePhase)`. The first call, in whatever
    /// phase (a workout can launch the watch app in the background), seeds the catalog, loads the settings and
    /// activates WatchConnectivity. Each later call, on return to the foreground, retries what failed: opening
    /// the database (product decision #29), then seeding (#28). A settings row that cannot be read is not retried.
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

    /// Opens the database and binds the keys, or shows decision #29's screen; the file is never deleted, moved or
    /// replaced here.
    private func openDatabase() {
        environment.record(.began(.openDatabase))
        do {
            stores = try LedgerStores.open(
                at: environment.databaseURL,
                kind: .watch,
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

    /// Decision #28: logged, and the launch carries on; retried on the next launch or foreground.
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
