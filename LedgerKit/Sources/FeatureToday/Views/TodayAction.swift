import SwiftUI

/// What a tap on Today asks for. The views send one of these and decide nothing; `TodayScreen` answers it.
nonisolated enum TodayAction: Equatable, Sendable {
    /// A control whose model carries a route: the screen hands it to the app.
    case route(TodayRoute)
    /// The rest-day card's "Train off-schedule": the screen presents the sheet.
    case pickOffScheduleDay
    #if DEBUG
        /// A long press on the title, in Debug builds only: the app opens its Debug menu (F07 criterion 7).
        case titleLongPress
    #endif
}

/// `nonisolated`, so the key `@Entry` generates is not main-actor-isolated by this module's default.
nonisolated extension EnvironmentValues {
    /// The moment the resume button's time stands still at: for previews and tests, which pass the moment
    /// their model was made for. Nil in the app, where the button counts by the wall clock.
    @Entry var todayTimerPause: Date?
}
