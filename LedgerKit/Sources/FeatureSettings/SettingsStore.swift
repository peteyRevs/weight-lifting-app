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
/// `pending` until it is written.
///
/// **What is committed** is the last value the store knows is in the row: the newest of its own saves whose echo
/// the observation has not given back yet (`unechoed`, oldest first), else the observation's last value (`stored`).
/// An echo of an earlier save only drops that save, and those before it, from `unechoed`; while a later one is still
/// there, the screen keeps showing the later one, so a late echo never draws over a newer value (F14-S1-3).
///
/// **Saves** run one at a time, whichever run of `SettingsRoot`'s task starts them (`+Sources`; F14-S1-4), each of
/// the whole `Settings`. A change made while one runs is saved next, folded with any others: the last value wins. A
/// save that fails shows "Couldn't save that change." and puts the whole screen back to what is committed: the
/// changes queued behind it are dropped with it (F14-S1-1, ruled; F14-S1-2).
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
    /// The lifter's latest change while it is not yet written: being saved, or waiting to be.
    var pending: Settings?
    /// The values this store wrote that the observation has not given back yet, oldest first.
    @ObservationIgnored var unechoed: [Settings] = []
    @ObservationIgnored var saveFailed = false
    /// The observation ended: the settings are followed again after the next save.
    var isUnreadable = false
    /// A save is running, in whichever run started it: no other starts until it returns.
    @ObservationIgnored var isSaving = false
    /// Marks the current run's saver and follower (`+Sources`), and that run's number: a run that ends clears the
    /// marks only while they are still its own.
    @ObservationIgnored var saveMark: AsyncStream<Void>.Continuation?
    @ObservationIgnored var followMark: AsyncStream<Void>.Continuation?
    @ObservationIgnored var runNumber = 0
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

    /// The last value the store knows is in the row: its newest save not yet echoed, else the observation's last.
    var committed: Settings? {
        unechoed.last ?? stored
    }

    /// The settings on screen: the lifter's latest change, else what is committed.
    var shown: Settings? {
        pending ?? committed
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
