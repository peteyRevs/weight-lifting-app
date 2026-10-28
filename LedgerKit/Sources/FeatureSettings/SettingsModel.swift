import LedgerDomain

/// Everything Settings draws and speaks, as `SettingsPresentation.make(_:)` builds it. Every string is final and
/// every control carries the `SettingsAction` its tap means: the views draw the model and decide nothing.
nonisolated struct SettingsModel: Equatable, Sendable {
    /// "Settings": the screen's heading.
    let title: String
    /// "Couldn't save that change.", under the title, after a save failed; nil otherwise.
    let problem: String?
    /// TRAINING.
    let training: String
    let units: Units
    let rest: Rest
    let weekStart: WeekStart
    /// Plate math, Auto rest timer, Watch haptic at zero, in that order.
    let switches: [Switch]
    /// DATA.
    let data: String
    let health: Status
    /// "Diagnostics", in Debug builds only; nil in Release.
    let diagnostics: Link?
    /// "Ledger 0.14.0 · build 74": the foot of the page. Never empty.
    let about: String

    /// "Units" with its two options, "LB" and "KG". VoiceOver reads the control as a group named `title`.
    struct Units: Equatable, Sendable {
        let title: String
        let detail: String
        /// Exactly one is selected.
        let options: [Option]
    }

    struct Option: Equatable, Sendable, Identifiable {
        /// The option's place, from 0.
        let id: Int
        /// "LB".
        let title: String
        /// "pounds".
        let spokenLabel: String
        let isSelected: Bool
        /// Chooses this option. The selected option carries it too: it changes nothing.
        let action: SettingsAction
    }

    /// "Default rest", stepped: to VoiceOver one adjustable element, its label with `spokenValue`, and `detail`
    /// as its hint.
    struct Rest: Equatable, Sendable {
        let title: String
        let detail: String
        /// "1:30", as the Day editor writes a rest (`RestDuration.label`).
        let value: String
        /// "1 minute, 30 seconds".
        let spokenValue: String
        /// 15 s shorter; nil at 30 s.
        let decrement: SettingsAction?
        /// 15 s longer; nil at 300 s.
        let increment: SettingsAction?
    }

    /// "Week starts on", a menu of the seven weekdays, listed from the calendar's first weekday.
    struct WeekStart: Equatable, Sendable {
        let title: String
        let detail: String
        /// The chosen weekday's name: what the menu shows, and its spoken value.
        let value: String
        let days: [Day]
        /// The `id` of the chosen day.
        let selected: Int
    }

    struct Day: Equatable, Sendable, Identifiable {
        /// The weekday's ISO number, Monday 1 … Sunday 7.
        let id: Int
        /// "Monday", in the lifter's locale.
        let title: String
        let action: SettingsAction
    }

    /// A preference that is on or off. To VoiceOver a switch: `title`, on or off, and `detail` as its hint.
    struct Switch: Equatable, Sendable, Identifiable {
        let id: SwitchKind
        let title: String
        let detail: String
        let isOn: Bool
        /// Turns it to the other state.
        let action: SettingsAction
    }

    enum SwitchKind: Hashable, Sendable {
        case plateMath, autoRest, watchBuzz
    }

    /// A row that shows a status and does nothing: "Apple Health", "Not connected" (Pete's question 4, A).
    struct Status: Equatable, Sendable {
        let title: String
        let value: String
    }

    /// A row that goes somewhere.
    struct Link: Equatable, Sendable {
        let title: String
        let action: SettingsAction
    }
}
