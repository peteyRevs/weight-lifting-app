import Dependencies
import Foundation
import LedgerDependencies
import LedgerDomain
import Observation

/// A route on its way to the app: `SettingsRoot`'s `.task(id:)` hands it on. The number tells one tap from the
/// next when both ask for the same route.
nonisolated struct SettingsPendingRoute: Hashable, Sendable {
    let number: Int
    let route: SettingsRoute
}

/// The store of Settings (F14 S1; the M1 store convention): the settings the lifter sees, the saves that keep them,
/// and the route waiting for the app. `SettingsRoot`, the screen over it, is S1b's; until then only the tests make
/// one.
///
/// **Intents are synchronous and decide nothing.** A change is applied to the settings on screen and the model is
/// made again before `send` returns, so a control shows the lifter's value at once (N1). The change waits in
/// `pending` until the store's observation gives it back: an earlier save's value that the observation gives in
/// the meantime is kept as the stored one, and never drawn over the lifter's.
///
/// **Saves** run from `SettingsRoot`'s task (`+Sources`), one at a time, each of the whole `Settings`. A change
/// made while one runs is saved next, folded with any others: the last value wins. A save that fails shows
/// "Couldn't save that change." and puts the stored settings back on screen.
///
/// **Unreadable settings** (N2; the F05 input): when the observation ends, the screen draws what it last had, or
/// `Settings.default`, and nothing is saved until the lifter changes something. That change saves the whole value,
/// over the row this app could not read, and the store then follows the settings again.
///
/// **Making one does nothing.** `SettingsRoot` makes a store each time SwiftUI makes the root and `@State` keeps
/// the first, so the initializer only keeps what it is given.
@MainActor @Observable
final class SettingsStore {
    // `stored`, `pending` and `isUnreadable` are observed for the tests, which wait on them; the views read only the
    // model and the route.

    /// What the screen draws; nil until the settings have been read, or found unreadable.
    private(set) var model: SettingsModel?
    /// The route the root hands the app next; nil once the app's handler has returned.
    private(set) var pendingRoute: SettingsPendingRoute?

    /// What the settings' observation last gave; `Settings.default` once it ended without a value.
    var stored: Settings?
    /// The lifter's changes not yet given back by the observation: being saved, waiting to be, or saved.
    var pending: Settings?
    /// The value the last save in this run wrote, until the observation gives it back.
    @ObservationIgnored var written: Settings?
    @ObservationIgnored var saveFailed = false
    /// The observation ended: the settings are followed again after the next save.
    var isUnreadable = false
    /// Marks the run's saver and follower, while a run is on (`+Sources`).
    @ObservationIgnored var saveMark: AsyncStream<Void>.Continuation?
    @ObservationIgnored var followMark: AsyncStream<Void>.Continuation?
    @ObservationIgnored private var routeNumber = 0
    @ObservationIgnored let about: AppAbout

    @ObservationIgnored @Dependency(\.settingsRepository) var settings
    @ObservationIgnored @Dependency(\.locale) private var locale
    @ObservationIgnored @Dependency(\.calendar) private var calendar
    @ObservationIgnored @Dependency(\.logger) private var injectedLogger

    /// The injected logger under the module's own category (standards §8).
    var logger: LedgerLogger {
        injectedLogger.category("settings")
    }

    init(about: AppAbout) {
        self.about = about
    }

    /// The settings on screen: the lifter's latest change, else the stored ones.
    var shown: Settings? {
        pending ?? stored
    }

    // MARK: Intents

    func send(_ action: SettingsAction) {
        if case let .route(route) = action {
            emit(route)
            return
        }
        // Nothing is drawn before the settings are read, so no control can have been tapped.
        guard let current = shown else {
            return
        }
        let next = Self.applying(action, to: current)
        guard next != current else {
            return
        }
        pending = next
        saveFailed = false
        show()
        saveMark?.yield()
    }

    /// `settings` with `action` applied.
    private static func applying(_ action: SettingsAction, to settings: Settings) -> Settings {
        var next = settings
        switch action {
        case let .setUnits(units): next.units = units
        case let .setDefaultRest(rest): next.defaultRest = rest
        case let .setWeekStart(day): next.weekStart = day
        case let .setPlateMath(isOn): next.plateMathEnabled = isOn
        case let .setAutoRest(isOn): next.autoRest = isOn
        case let .setWatchBuzz(isOn): next.watchBuzz = isOn
        case .route: break
        }
        return next
    }

    /// Hands the waiting route to `handler`, once, and forgets it when the handler has returned.
    func deliverRoute(to handler: (SettingsRoute) -> Void) {
        guard let waiting = pendingRoute else {
            return
        }
        handler(waiting.route)
        pendingRoute = nil
    }

    /// One route waits at a time: a tap that arrives before the app was handed the one before is dropped, so a
    /// double tap is one route.
    private func emit(_ route: SettingsRoute) {
        guard pendingRoute == nil else {
            return
        }
        routeNumber += 1
        pendingRoute = SettingsPendingRoute(number: routeNumber, route: route)
    }

    /// Draws the settings on screen. A model equal to the one drawn is not published again.
    func show() {
        guard let onScreen = shown else {
            return
        }
        let next = SettingsPresentation.make(SettingsInput(
            settings: onScreen,
            about: about,
            saveFailed: saveFailed,
            locale: locale,
            calendar: calendar
        ))
        if model != next {
            model = next
        }
    }
}
